# frozen_string_literal: true

require 'timeout'
require 'net/http'
require 'uri'
require 'async'
require 'async/queue'
require 'async/websocket/adapters/rack'
require 'twitter_cldr'
require_relative '../agents/ai_user_agent'
require_relative '../agents/context_extractor_agent'
require_relative 'boolean_parser'
require_relative 'extra_logger'
require_relative 'ssl_configuration'
require_relative 'string_utils'
require_relative '../shared_tools/monadic_session_state'

# Load WebSocket sub-modules
require_relative 'websocket/connection_manager'
require_relative 'websocket/app_data'
require_relative 'websocket/tts_handler'
require_relative 'websocket/message_editor'
require_relative 'websocket/audio_handler'
require_relative 'websocket/pdf_handler'

Monadic::Utils::SSLConfiguration.configure! if defined?(Monadic::Utils::SSLConfiguration)

module WebSocketHelper
  include AIUserAgent
  include ContextExtractorAgent
  include Monadic::SharedTools::MonadicSessionState

  # Access Rack session from thread-local storage in WebSocket context
  # This is necessary because WebSocket connections don't use the normal HTTP request/response cycle
  def session
    Thread.current[:rack_session] || (defined?(super) ? super : {})
  end

  # Safe session parameter access that handles both symbol and string keys
  # This ensures compatibility between import (uses :parameters) and runtime (uses "parameters")
  def get_session_params
    session[:parameters] || session["parameters"] || {}
  end

  def sync_session_state!
    session_id = Thread.current[:websocket_session_id]
    return unless session_id

    params = get_session_params || {}
    Monadic::Utils::ExtraLogger.log { "[sync_session_state!] Session synced: #{session_id}" }

    WebSocketHelper.update_session_state(
      session_id,
      messages: session[:messages] || [],
      parameters: params
    )
  end

  # Realtime TTS buffer configuration
  # Minimum character length for TTS processing:
  # - Sentences ≤ this length are buffered
  # - Buffer is flushed when total exceeds this length
  # Larger values (e.g., 50) reduce API calls and errors, improve fluency
  # but may slightly increase initial response delay
  # Configurable via AUTO_TTS_MIN_LENGTH environment variable (default: 50, range: 20-200)
  def self.realtime_tts_min_length
    value = (ENV['AUTO_TTS_MIN_LENGTH'] || '50').to_i
    # Enforce bounds: minimum 20, maximum 200
    [[value, 20].max, 200].min
  end

  # For backward compatibility and convenience
  REALTIME_TTS_MIN_LENGTH = realtime_tts_min_length

  # Sentence segmentation using TwitterCLDR (faster and better RTL support than PragmaticSegmenter)
  # Returns an array of sentence strings
  def self.segment_sentences(text)
    return [] if text.nil? || text.empty?

    # Note: Must use .to_a before .map because the enumerator yields strings when iterated directly,
    # but returns [text, start_pos, end_pos] arrays when converted to array first
    TwitterCldr::Segmentation::BreakIterator.new(:en).each_sentence(text).to_a.map do |segment|
      # TwitterCLDR returns [text, start_pos, end_pos], extract just the text
      segment[0].strip
    end.reject(&:empty?)
  end

  # Initialize token counting in a background thread
  def initialize_token_counting(text, encoding_name="o200k_base")
    # Return immediately if no text
    return nil if text.nil? || text.empty?
    
    # Store in thread local variable to avoid creating too many threads
    Thread.current[:token_count_in_progress] = true
    
    # Use Thread.new with lower priority to avoid impacting TTS
    Thread.new do
      result = nil
      begin
        # Add a small delay to prioritize TTS thread startup if running concurrently
        sleep 0.05 if Thread.list.any? { |t| t[:type] == :tts }
        
        # Set thread type for identification
        Thread.current[:type] = :token_counter
        
        # Do the actual token counting - this now uses the caching mechanism
        # in FlaskAppClient for better performance
        result = MonadicApp::TOKENIZER.count_tokens(text, encoding_name)
        
        # Store for later use in check_past_messages
        Thread.current[:token_count_result] = result
      rescue => e
        # Log token counting errors for debugging
        if defined?(logger) && logger && CONFIG["EXTRA_LOGGING"]
          logger.warn "Token counting error: #{e.message}"
        end
        # Continue without blocking the operation
      ensure
        Thread.current[:token_count_in_progress] = false
      end
      
      # Thread's return value
      result
    end
  end

  # check if the total tokens of past messages is less than max_tokens in obj
  # token count is calculated using tiktoken
  def check_past_messages(obj)
    # filter out any messages of type "search"
    # Filter messages by current app_name to prevent cross-app conversation leakage
    current_app_name = obj["app_name"] || session.dig("parameters", "app_name") || session.dig(:parameters, "app_name")
    messages = session[:messages].filter { |m| m["type"] != "search" && m["app_name"] == current_app_name }

    res = false
    max_input_tokens = obj["max_input_tokens"].to_i
    context_size = obj["context_size"].to_i
    tokenizer_available = true

    # Default to o200k_base encoding for GPT models
    encoding_name = "o200k_base"

    begin
      # Batch process messages that need token counting to reduce HTTP requests
      messages_to_count = []
      messages.each do |m|
        # Skip messages that already have token counts
        next if m["tokens"]
        
        # If this is the most recent message and we have precounted tokens, use them
        if m == messages.last && defined?(Thread.current[:token_count_result]) && Thread.current[:token_count_result]
          m["tokens"] = Thread.current[:token_count_result]
        else
          # Otherwise add to batch for counting
          messages_to_count << m
        end
        
        # Mark all messages as active initially
        m["active"] = true
      end
      
      # Now process any messages that still need token counts - these use the cache in FlaskAppClient
      messages_to_count.each do |m|
        m["tokens"] = MonadicApp::TOKENIZER.count_tokens(m["text"], encoding_name)
      end

      # Filter active messages and calculate total token count
      active_messages = messages.select { |m| m["active"] }.reverse
      total_tokens = active_messages.sum { |m| m["tokens"] || 0 }

      # Remove oldest messages until total token count and message count are within limits
      until active_messages.empty? || total_tokens <= max_input_tokens
        last_message = active_messages.pop
        last_message["active"] = false
        total_tokens -= last_message["tokens"] || 0
        res = true
        break if context_size.positive? && active_messages.size <= context_size
      end

      # Calculate total token counts for different roles
      count_total_system_tokens = messages.filter { |m| m["role"] == "system" }.sum { |m| m["tokens"] || 0 }
      count_total_input_tokens = messages.filter { |m| m["role"] == "user" }.sum { |m| m["tokens"] || 0 }
      count_total_output_tokens = messages.filter { |m| m["role"] == "assistant" }.sum { |m| m["tokens"] || 0 }
      count_active_tokens = active_messages.sum { |m| m["tokens"] || 0 }
      count_all_tokens = messages.sum { |m| m["tokens"] || 0 }
    rescue StandardError => e
      STDERR.puts "Error in token counting: #{e.message}"
      tokenizer_available = false
    end

    # Return information about the state of the messages array
    res = { changed: res,
            count_total_system_tokens: count_total_system_tokens,
            count_total_input_tokens: count_total_input_tokens,
            count_total_output_tokens: count_total_output_tokens,
            count_total_active_tokens: count_active_tokens,
            count_all_tokens: count_all_tokens,
            count_messages: messages.size,
            count_active_messages: active_messages.size,
            encoding_name: encoding_name }
    res[:error] = "Error: Token count not available" unless tokenizer_available
    res
  end


  


  
  # Calculate the turn number for an assistant message
  # Turn numbers are 1-indexed based on assistant message order
  # @param messages [Array] The messages array
  # @param message_index [Integer] The index of the message
  # @return [Integer, nil] The turn number or nil if not an assistant message
  def calculate_turn_number(messages, message_index)
    return nil unless messages && message_index

    message = messages[message_index]
    return nil unless message && message["role"] == "assistant"

    # Count assistant messages up to and including this one
    turn = 0
    messages.each_with_index do |m, idx|
      turn += 1 if m["role"] == "assistant"
      return turn if idx == message_index
    end
    nil
  end

  # Get context schema from session
  # @param rack_session [Hash] The session
  # @return [Hash, nil] The context schema or nil
  def get_context_schema(rack_session)
    monadic_state = rack_session[:monadic_state] || rack_session["monadic_state"]
    return nil unless monadic_state

    monadic_state[:context_schema] || monadic_state["context_schema"]
  end

  
  def websocket_handler(env)
    # Falcon/Async handles the event loop automatically
    handle_websocket_connection(env)
  end

  def handle_websocket_connection(env)
    # Get Rack session from environment (or create empty hash if not available)
    session = env['rack.session'] || {}

    # Generate or retrieve session ID with tab isolation
    # Extract tab_id from query parameters for tab-specific session management
    query_params = Rack::Utils.parse_query(env["QUERY_STRING"])
    tab_id = query_params["tab_id"]

    ws_session_id = nil

    # If we have a tab_id, use it as part of the session identifier
    # This ensures each tab has its own isolated session
    if tab_id && !tab_id.empty?
      # Use tab_id as the session identifier directly
      # This ensures complete isolation between tabs
      ws_session_id = tab_id
    else
      # Fallback: For connections without tab_id (e.g., background connections),
      # use a consistent session ID stored in Rack session
      # This ensures page reload preserves the session
      ws_session_id = session[:websocket_session_id] if session.is_a?(Hash)

      if ws_session_id.nil?
        # Generate new UUID only if no session exists
        ws_session_id = SecureRandom.uuid
        session[:websocket_session_id] = ws_session_id if session.is_a?(Hash)
      end
    end

    Monadic::Utils::ExtraLogger.log { "[WebSocket] Session initialized: #{ws_session_id} (tab_id: #{tab_id || 'none'})" }

    # Use async-websocket to handle the connection
    Async::WebSocket::Adapters::Rack.open(env) do |connection|
      WebSocketHelper.add_connection_with_session(connection, ws_session_id)

      Thread.current[:websocket_session_id] = ws_session_id
      Thread.current[:rack_session] = session

      # Tab isolation: Each tab must have completely independent session state
      # Always initialize with empty session first to clear any Rack session data from other tabs
      session[:messages] = []
      session[:parameters] = {}

      # Then restore saved state if it exists (for page refresh/reconnection)
      saved_state = WebSocketHelper.fetch_session_state(ws_session_id)
      if saved_state
        session[:messages] = saved_state[:messages] if saved_state[:messages]
        if saved_state[:parameters]
          session[:parameters] ||= {}
          saved_state[:parameters].each do |key, value|
            session[:parameters][key] = value
          end
        end
      end

      Monadic::Utils::ExtraLogger.log { "[WebSocket] Session state: #{saved_state ? 'restored' : 'new'} (#{ws_session_id})" }

      queue = Queue.new
      thread = nil

      # Send initial load message immediately after connection
      handle_load_message(connection)

      begin
        while message_data = connection.read
          begin
            obj = JSON.parse(message_data)
            obj = BooleanParser.parse_hash(obj)
          rescue JSON::ParserError => e
            DebugHelper.debug("Invalid JSON in WebSocket message: #{message_data[0..100]}", category: :websocket, level: :error)
            send_to_client(connection, { "type" => "error", "content" => "invalid_message_format" })
            next
          end

          msg = obj["message"] || ""

          # Debug logging for all messages when EXTRA_LOGGING is enabled
          if msg == "UPDATE_LANGUAGE"
            Monadic::Utils::ExtraLogger.log { "WebSocket received UPDATE_LANGUAGE message\n  Full obj: #{obj.inspect}" }
          end

      case msg
      when "TTS"
          handle_ws_tts(connection, obj, session)
        when "TTS_STREAM"
          handle_ws_tts_stream(connection, obj, session, thread)
        when "CANCEL"
          # Get session ID for targeted broadcasting
          ws_session_id = Thread.current[:websocket_session_id]

          thread&.kill
          thread = nil
          queue.clear

          cancel_message = { "type" => "cancel" }.to_json
          if ws_session_id
            WebSocketHelper.send_to_session(cancel_message, ws_session_id)
          else
            WebSocketHelper.broadcast_to_all(cancel_message)
          end
        when "PDF_TITLES"
          handle_ws_pdf_titles(connection)
        when "DELETE_PDF"
          handle_ws_delete_pdf(connection, obj, session)
        when "DELETE_ALL_PDFS"
          handle_ws_delete_all_pdfs(connection, session)
        when "CHECK_TOKEN"
          handle_ws_check_token(connection, obj, session)
        when "PING"
          # Send PONG only to the connection that sent PING (connection-specific keepalive)
          send_to_client(connection, { "type" => "pong" })
        when "RESET"
          handle_ws_reset(session)
        when "LOAD"
          # Store ui_language in session parameters if provided
          if obj["ui_language"]
            session[:parameters] ||= {}
            session[:parameters]["ui_language"] = obj["ui_language"]
          end
          handle_load_message(connection)
        when "DELETE"
          handle_delete_message(connection, obj)
        when "EDIT"
          handle_edit_message(connection, obj)
        when "UPDATE_MCP_CONFIG"
          handle_mcp_config_update(connection, obj)
        when "UPDATE_CONTEXT_FROM_CLIENT"
          handle_context_update_from_client(connection, obj)
        when "AI_USER_QUERY"
          handle_ws_ai_user_query(connection, obj, session, thread)
        when "HTML"
          handle_ws_html(connection, obj, session, thread, queue)
        when "UPDATE_PARAMS"
          handle_ws_update_params(connection, obj, session)
        when "SYSTEM_PROMPT"
          handle_ws_system_prompt(connection, obj, session)
        when "SAMPLE"
          handle_ws_sample(connection, obj, session)
        when "AUDIO"
          handle_audio_message(connection, obj)
        when "UPDATE_LANGUAGE"
          handle_ws_update_language(connection, obj, session)
        when "STOP_TTS"
          handle_ws_stop_tts(connection, obj, session)
        when "PLAY_TTS"
          handle_ws_play_tts(connection, obj, session, thread)
        else # fragment
          thread = handle_ws_streaming(connection, obj, session, queue)
        end
      end # end case
    end # end while

    rescue => e
      Monadic::Utils::ExtraLogger.log { "[WebSocket] Error in message loop: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}" }
    ensure
      WebSocketHelper.remove_connection_with_session(connection, ws_session_id)

      Monadic::Utils::ExtraLogger.log { "[WebSocket] Connection closed for session #{ws_session_id}" }

      sync_session_state!

      Thread.current[:websocket_session_id] = nil
      Thread.current[:rack_session] = nil

      thread&.kill
    end
  end

  # ── Extracted WebSocket branch handlers ──────────────────────────

  private def handle_ws_html(connection, obj, session, thread, queue)
    thread&.join
    until queue.empty?
      last_one = queue.shift
      begin
        content = last_one["choices"][0]

        # Always use message content - monadic apps will have JSON in content field
        text = content["text"] || content["message"]["content"]

        # Append tool HTML fragments (e.g., ABC notation from Music Lab).
        # Tools store HTML in session[:tool_html_fragments]; the ABC block
        # extraction below will handle them through the normal pipeline.
        if session[:tool_html_fragments]
          stored_fragments = session.delete(:tool_html_fragments)
          text = text.to_s + "\n\n" + stored_fragments.join("\n\n")
        end
        pp "[DEBUG] WebSocket - text extraction: content keys = #{content.keys}, text = #{text.class}:#{text.to_s[0..100]}..." if session["parameters"]["app_name"]&.include?("Perplexity")
        # Extract thinking content uniformly from message
        thinking = content["message"]["thinking"] || content["message"]["reasoning_content"] || content["thinking"]

        # Check if text contains citation HTML that needs to be extracted
        citation_html = nil
        if text && text.include?("<div data-title='Citations'")
          # Extract citation HTML from the text
          if match = text.match(/(\n\n<div data-title='Citations'[^>]*>.*?<\/div>)/m)
            citation_html = match[1]
            # Remove citation HTML from text so it doesn't get processed by markdown
            text = text.sub(match[1], '')

            if CONFIG["EXTRA_LOGGING"]
              DebugHelper.debug("WebSocket: Extracted citation HTML from text", category: :api, level: :info)
              DebugHelper.debug("WebSocket: Citation HTML: #{citation_html[0..100]}...", category: :api, level: :debug)
            end
          end
        elsif CONFIG["EXTRA_LOGGING"]
          if text && text.match(/\[\d+\]/)
            DebugHelper.debug("WebSocket: Found citation references but no HTML: #{text.scan(/\[\d+\]/).join(', ')}", category: :api, level: :info)
          end
        end


        type_continue = "Press <button class='btn btn-secondary btn-sm contBtn'>continue</button> to get more results\n"
        code_truncated = "[CODE BLOCK TRUNCATED]"

        if content["finish_reason"] && content["finish_reason"] == "length"
          if text.scan(/(?:\A|\n)```/m).size.odd?
            text += "\n```\n\n> #{type_continue}\n#{code_truncated}"
          else
            text += "\n\n> #{type_continue}"
          end
        end

        if content["finish_reason"] && content["finish_reason"] == "safety"
          ws_session_id = Thread.current[:websocket_session_id]
          safety_error = { "type" => "error", "content" => "api_stopped_safety" }.to_json
          if ws_session_id
            WebSocketHelper.send_to_session(safety_error, ws_session_id)
          else
            WebSocketHelper.broadcast_to_all(safety_error)
          end
        end

        # Extract ABC blocks before markdown processing (they're already HTML)
        abc_blocks = []
        text_for_markdown = text.gsub(/<div class="abc-code">.*?<\/div>/m) do |match|
          abc_blocks << match
          "\n\nABC_PLACEHOLDER_#{abc_blocks.size - 1}\n\n"
        end

        params = get_session_params

        # Phase 2: Server-side HTML generation disabled
        # Client-side MarkdownRenderer handles all rendering
        # Keep text in original form with ABC blocks and citations intact

        # For ABC notation, keep the HTML blocks in the text
        # MarkdownRenderer will handle them properly
        final_text = text_for_markdown
        abc_blocks.each_with_index do |block, index|
          final_text = final_text.gsub("ABC_PLACEHOLDER_#{index}", block)
        end

        # Add response suffix if present
        if params["response_suffix"]
          final_text += "\n\n" + params["response_suffix"]
        end

        # Add citation HTML back to text
        if citation_html
          final_text += citation_html
          if CONFIG["EXTRA_LOGGING"]
            DebugHelper.debug("WebSocket: Added citation HTML to final text", category: :api, level: :info)
          end
        end

       new_data = { "mid" => SecureRandom.hex(4),
                    "role" => "assistant",
                    "text" => final_text,
                    "lang" => detect_language(final_text),
                    "app_name" => params["app_name"],
                    "monadic" => params["monadic"],
                    "active" => true } # detect_language is called only once here

        if thinking && !thinking.to_s.strip.empty?
          new_data["thinking"] = thinking
          if CONFIG["EXTRA_LOGGING"]
            DebugHelper.debug("WebSocket: Attaching thinking block (length=#{thinking.to_s.length})", category: :ui, level: :info)
          end
        end

        # Optional: Use provider-reported usage to set assistant tokens
        # This is disabled by default to avoid confusion and keep a
        # single source of truth (tiktoken/Flask) for token counting.
        # Enable via CONFIG["TOKEN_COUNT_SOURCE"] = "provider_only" or "hybrid".
        begin
          source = (defined?(CONFIG) && CONFIG && CONFIG["TOKEN_COUNT_SOURCE"]) ? CONFIG["TOKEN_COUNT_SOURCE"].to_s.downcase : ""
          provider_usage_enabled = %w[provider_only hybrid].include?(source)
        rescue StandardError
          provider_usage_enabled = false
        end

        if provider_usage_enabled
          usage = last_one["usage"] || last_one.dig("choices", 0, "usage")
          if usage && usage.is_a?(Hash)
            tokens = usage["output_tokens"] || usage["completion_tokens"]
            new_data["tokens"] = tokens.to_i if tokens
          end
        end

        # Get session ID for targeted broadcasting
        ws_session_id = Thread.current[:websocket_session_id]

        # Send HTML message (conversation content)
        html_message = {
          "type" => "html",
          "content" => new_data
        }.to_json
        if ws_session_id
          WebSocketHelper.send_to_session(html_message, ws_session_id)
        else
          WebSocketHelper.broadcast_to_all(html_message)
        end

        session[:messages] << new_data
        sync_session_state!
        # Filter messages by current app_name to prevent cross-app conversation leakage
        params = get_session_params
    current_app_name = obj["app_name"] || params["app_name"]
    messages = session[:messages].filter { |m| m["type"] != "search" && m["app_name"] == current_app_name }
        past_messages_data = check_past_messages(params)

        # Send status updates
        if past_messages_data[:changed]
          status_message = { "type" => "change_status", "content" => messages }.to_json
          if ws_session_id
            WebSocketHelper.send_to_session(status_message, ws_session_id)
          else
            WebSocketHelper.broadcast_to_all(status_message)
          end
        end

        info_message = { "type" => "info", "content" => past_messages_data }.to_json
        if ws_session_id
          WebSocketHelper.send_to_session(info_message, ws_session_id)
        else
          WebSocketHelper.broadcast_to_all(info_message)
        end

        # Context extraction for monadic apps (automatic context tracking)
        # This runs AFTER the response is sent to the user, in a background thread
        # Uses direct HTTP API calls to avoid re-triggering WebSocket flow
        if params["monadic"]
          begin
            Monadic::Utils::ExtraLogger.log { "[ContextExtractor] Monadic mode detected, starting context extraction setup" }

            # Get the provider and context_schema from the app settings
            app_name = params["app_name"]
            app = APPS[app_name] if defined?(APPS) && app_name
            provider = app&.settings&.dig("provider") || app&.settings&.dig(:provider) || "openai"
            context_schema = app&.settings&.dig(:context_schema) || app&.settings&.dig("context_schema")

            Monadic::Utils::ExtraLogger.log { "[ContextExtractor] app_name=#{app_name}, provider=#{provider}, context_schema=#{context_schema ? 'present' : 'nil'}" }

            # Find the last user message from session messages
            user_messages = messages.select { |m| m["role"] == "user" }
            last_user_message = user_messages.last
            # Support both "text" and "content" keys for user messages
            user_text = if last_user_message
              last_user_message["text"] ||
              last_user_message[:text] ||
              (last_user_message["content"].is_a?(String) ? last_user_message["content"] : nil) ||
              (last_user_message["content"].is_a?(Array) ? last_user_message["content"].map { |c| c.is_a?(Hash) ? (c["text"] || c[:text]) : c.to_s }.compact.join("\n") : nil) ||
              ""
            else
              ""
            end

            # Capture session data for thread (avoid closure issues)
            thread_session = session.dup
            thread_ws_session_id = ws_session_id
            thread_context_schema = context_schema

            # Only extract context if we have both user message and assistant response
            if !user_text.empty? && !final_text.to_s.empty?
              # Notify client that context extraction is starting
              start_message = { type: "context_extraction_started" }.to_json
              if defined?(WebSocketHelper) && WebSocketHelper.respond_to?(:send_to_session)
                WebSocketHelper.send_to_session(start_message, thread_ws_session_id)
              end

              # Run context extraction in a separate thread to avoid blocking
              Thread.new do
                begin
                  process_and_broadcast_context(
                    thread_session,
                    user_text,
                    final_text,
                    provider,
                    thread_ws_session_id,
                    thread_context_schema
                  )
                rescue StandardError => ctx_err
                  Monadic::Utils::ExtraLogger.log { "[ContextExtractor] Background error: #{ctx_err.message}\n[ContextExtractor] Backtrace: #{ctx_err.backtrace.first(3).join("\n")}" }
                end
              end
            end
          rescue StandardError => ctx_setup_err
            # Don't let context extraction setup errors affect the main flow
            Monadic::Utils::ExtraLogger.log { "[ContextExtractor] Setup error: #{ctx_setup_err.message}" }
          end
        end
      rescue StandardError => e
        STDERR.puts "Error processing request: #{e.message}"
        ws_session_id = Thread.current[:websocket_session_id]
        error_message = { "type" => "error", "content" => "something_went_wrong" }.to_json
        if ws_session_id
          WebSocketHelper.send_to_session(error_message, ws_session_id)
        else
          WebSocketHelper.broadcast_to_all(error_message)
        end
      end
    end
  end

  private def handle_ws_streaming(connection, obj, session, queue)
    # Get session ID for targeted broadcasting throughout streaming
    ws_session_id = Thread.current[:websocket_session_id]

    session[:parameters].merge! obj

    # Start background token counting for the user message immediately
    message_text = obj["message"].to_s
    if !message_text.empty?
      # Use o200k_base encoding for most LLMs
      token_count_thread = initialize_token_counting(message_text, "o200k_base")
      Thread.current[:token_count_thread] = token_count_thread

      # Add user message to session for context extraction
      params = get_session_params
      user_message_data = {
        "mid" => SecureRandom.hex(4),
        "role" => "user",
        "text" => message_text,
        "app_name" => params["app_name"],
        "active" => true
      }
      session[:messages] << user_message_data
      sync_session_state!
    end

    # Extract TTS parameters if auto_speech is enabled
    # Convert string "true" to boolean true for compatibility
    obj["auto_speech"] = true if obj["auto_speech"] == "true"

    # Get auto_tts_realtime_mode setting
    # TEMPORARILY DISABLED (2025-11-07): Realtime mode has a race condition where
    # LLM streaming can split words mid-character (e.g., "チャット" → "チャ" + "ット"),
    # causing the sentence segmenter to mark sentences as "complete" before all characters
    # arrive. This results in truncated TTS audio (e.g., "チャット" → "チャ").
    # Need to add fragment stabilization (wait 50-100ms after sentence boundary)
    # before re-enabling.
    # auto_tts_realtime_mode = obj["auto_tts_realtime_mode"]
    # if auto_tts_realtime_mode.nil?
    #   auto_tts_realtime_mode = defined?(CONFIG) && CONFIG["AUTO_TTS_REALTIME_MODE"].to_s == "true"
    # end
    auto_tts_realtime_mode = false  # Force POST-COMPLETION mode until race condition is fixed

    if obj["auto_speech"]
      provider = obj["tts_provider"]
      if provider == "elevenlabs" || provider == "elevenlabs-flash" || provider == "elevenlabs-multilingual" || provider == "elevenlabs-v3"
        voice = obj["elevenlabs_tts_voice"]
      elsif provider == "gemini-flash" || provider == "gemini-pro"
        voice = obj["gemini_tts_voice"]
      else
        voice = obj["tts_voice"]
      end
      speed = obj["tts_speed"]
      response_format = "mp3"
      model = if defined?(Monadic::Utils::ModelSpec)
                Monadic::Utils::ModelSpec.default_tts_model("openai") || "tts-1"
              else
                "tts-1"
              end
      language = obj["conversation_language"] || "auto"
    end

    thread = Thread.new do
      # Set thread type for identification
      Thread.current[:type] = :tts

      # If we have a token counting thread, wait for it to complete and save result
      if defined?(token_count_thread) && token_count_thread
        begin
          # Don't wait forever, time out after 2 seconds
          Timeout.timeout(2) do
            token_count_result = token_count_thread.value
            if token_count_result
              Thread.current[:token_count_result] = token_count_result
            end
          end
        rescue Timeout::Error
          # Log timeout and continue without precounted tokens
          if defined?(logger) && logger && CONFIG["EXTRA_LOGGING"]
            logger.warn "Token counting timeout - continuing without precount"
          end
        rescue => e
          # Log error but continue operation
          if defined?(logger) && logger && CONFIG["EXTRA_LOGGING"]
            logger.warn "Token counting error in WebSocket handler: #{e.message}"
          end
        end
      end

      buffer = []
      cutoff = false

      # Initialize sequence counter for realtime TTS (once per message)
      @realtime_tts_sequence_counter = 0

      # Initialize short sentence buffer for realtime TTS
      @realtime_tts_short_buffer = []

      # Save original auto_speech and monadic values before they might be overwritten
      # These will be used for final segment processing after streaming completes
      original_auto_speech = obj["auto_speech"]
      original_monadic = obj["monadic"]

      app_name = obj["app_name"]
      app_obj = APPS[app_name]

      unless app_obj
        error_msg = "App '#{app_name}' not found in APPS"
        puts "[ERROR] #{error_msg}"
        error_message = { "type" => "error", "content" => error_msg }.to_json
        if ws_session_id
          WebSocketHelper.send_to_session(error_message, ws_session_id)
        else
          WebSocketHelper.broadcast_to_all(error_message)
        end
        next
      end

      prev_texts_for_tts = []
      responses = app_obj.api_request("user", session) do |fragment|
        # DEBUG: Log all fragment arrivals
        Monadic::Utils::ExtraLogger.log { "[DEBUG] Fragment arrived: type='#{fragment["type"]}', auto_speech=#{obj["auto_speech"]}, cutoff=#{cutoff}, monadic=#{obj["monadic"]}, auto_tts_realtime_mode=#{auto_tts_realtime_mode}" }

        if fragment["type"] == "error"
          error_content = fragment["content"] || fragment.to_s
          fragment_error = { "type" => "error", "content" => error_content }.to_json
          if ws_session_id
            WebSocketHelper.send_to_session(fragment_error, ws_session_id)
          else
            WebSocketHelper.broadcast_to_all(fragment_error)
          end
          break
        elsif fragment["type"] == "clear_fragments"
          # Clear server-side buffers before post-tool response streaming
          # This prevents pre-tool text from being concatenated with post-tool response
          buffer.clear
          @realtime_tts_short_buffer.clear if @realtime_tts_short_buffer

          # Send clear_fragments to frontend to clear the UI temp-card
          clear_msg = { "type" => "clear_fragments" }.to_json
          if ws_session_id
            WebSocketHelper.send_to_session(clear_msg, ws_session_id)
          else
            WebSocketHelper.broadcast_to_all(clear_msg)
          end

          Monadic::Utils::ExtraLogger.log { "[DEBUG] clear_fragments: server buffers cleared, message sent to frontend" }
        elsif fragment["type"] == "fragment"
          text = fragment["content"]
          buffer << text unless text.empty? || text == "DONE"

          segments = WebSocketHelper.segment_sentences(buffer.join)

          Monadic::Utils::ExtraLogger.log {
            msg = "[DEBUG] Fragment received: buffer_text='#{buffer.join[0..100]}...', segments=#{segments.size}"
            segments.each_with_index do |seg, i|
              msg += "\n[DEBUG]   segment[#{i}]: '#{seg[0..50]}...'"
            end
            msg
          }

          # Wait for complete sentences: TwitterCLDR returns 2+ segments when a sentence is complete
          # Process all complete sentences (all except the last incomplete one)
          if !cutoff && segments.size >= 2
            complete_sentences = segments[0...-1]

            if auto_tts_realtime_mode
              # REALTIME MODE: Use http.rb async processing for non-blocking TTS
              Monadic::Utils::ExtraLogger.log { "[DEBUG] REALTIME MODE ACTIVE: auto_speech=#{obj["auto_speech"]}, cutoff=#{cutoff}, monadic=#{obj["monadic"]}, segments=#{segments.size}\n[DEBUG] complete_sentences count: #{segments[0...-1].size}" }

              # Process each complete sentence with buffering for short sentences
              # This prevents pauses between short and long sentence TTS generation
              complete_sentences.each_with_index do |sentence, idx|
                split = sentence.split("---")
                if split.empty?
                  cutoff = true
                  break
                end

                # Process sentence fragments for TTS if auto_speech is enabled
                if obj["auto_speech"] && !cutoff && !obj["monadic"]
                  text = split[0] || ""

                  # Strip Markdown markers and HTML tags before TTS processing
                  text = StringUtils.strip_markdown_for_tts(text)

                  # Filter out very short or emoji-only segments
                  cleaned_text = text.gsub(/[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]/, '')
                  cleaned_text = cleaned_text.gsub(/^\s*[-*]\s+/, '').gsub(/^\s*\d+\.\s+/, '')
                  cleaned_text = cleaned_text.gsub(/[^\p{L}\p{N}\p{P}\p{Z}]+/, ' ')
                  cleaned_text = cleaned_text.strip

                  Monadic::Utils::ExtraLogger.log { "[BUFFER] ============================================\n[BUFFER] Sentence #{idx} received\n[BUFFER] Original text: '#{text}'\n[BUFFER] Cleaned text: '#{cleaned_text}'\n[BUFFER] Cleaned length: #{cleaned_text.length}" }

                  # Skip only if text is empty
                  if text.strip != ""
                    # Check if this is a short sentence (≤REALTIME_TTS_MIN_LENGTH chars cleaned length)
                    if cleaned_text.length <= REALTIME_TTS_MIN_LENGTH
                      # Buffer short sentence instead of sending immediately
                      @realtime_tts_short_buffer << text

                      # Calculate total buffer length
                      total_buffer_length = @realtime_tts_short_buffer.map do |buffered_text|
                        cleaned = buffered_text.gsub(/[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]/, '')
                        cleaned = cleaned.gsub(/^\s*[-*]\s+/, '').gsub(/^\s*\d+\.\s+/, '')
                        cleaned = cleaned.gsub(/[^\p{L}\p{N}\p{P}\p{Z}]+/, ' ')
                        cleaned.strip.length
                      end.sum

                      Monadic::Utils::ExtraLogger.log {
                        msg = "[BUFFER] Decision: BUFFERING (≤#{REALTIME_TTS_MIN_LENGTH} chars)\n[BUFFER] Buffer size: #{@realtime_tts_short_buffer.size} sentence(s)\n[BUFFER] Total buffer length: #{total_buffer_length} chars\n[BUFFER] Buffer contents:"
                        @realtime_tts_short_buffer.each_with_index do |buf_text, buf_idx|
                          msg += "\n[BUFFER]   [#{buf_idx}]: '#{buf_text}'"
                        end
                        msg
                      }

                      # Check if total buffer length exceeds threshold
                      # This prevents long pauses while maintaining gap prevention
                      if total_buffer_length > REALTIME_TTS_MIN_LENGTH
                        # Flush buffer when accumulated length is sufficient
                        # Add space between sentences to prevent words from merging
                        combined_text = @realtime_tts_short_buffer.join(" ")
                        @realtime_tts_short_buffer.clear

                        Monadic::Utils::ExtraLogger.log { "[BUFFER] *** FLUSHING BUFFER (total: #{total_buffer_length} > #{REALTIME_TTS_MIN_LENGTH}) ***\n[BUFFER] Combined text to send to TTS: '#{combined_text}'\n[BUFFER] Combined text length: #{combined_text.length}" }

                        # Increment counters and create sequence ID
                        @realtime_tts_sequence_counter += 1
                        sequence_num = @realtime_tts_sequence_counter
                        sequence_id = "seq#{sequence_num}_#{Time.now.to_f}_#{SecureRandom.hex(2)}"

                        # Submit TTS request immediately
                        Async do
                          tts_api_request_async(
                            combined_text,
                            provider: provider,
                            voice: voice,
                            speed: speed,
                            response_format: response_format,
                            language: language,
                            sequence_id: sequence_id
                          ) do |res_hash|
                            if res_hash && res_hash["type"] != "error"
                              Monadic::Utils::ExtraLogger.log { "[DEBUG] TTS async callback (flushed buffer): sequence_id=#{sequence_id}, type=#{res_hash["type"]}" }
                              # Use captured ws_session_id from outer scope
                              if ws_session_id
                                WebSocketHelper.send_audio_to_session(res_hash.to_json, ws_session_id)
                              else
                                WebSocketHelper.broadcast_to_all(res_hash.to_json)
                              end
                            else
                              Monadic::Utils::ExtraLogger.log { "[DEBUG] TTS failed for flushed buffer: #{res_hash&.[]("content")}" }
                            end
                          end
                        end
                      end
                    else
                      # This is a longer sentence - flush buffer and send combined text
                      Monadic::Utils::ExtraLogger.log { "[BUFFER] Decision: IMMEDIATE SEND (>#{REALTIME_TTS_MIN_LENGTH} chars)\n[BUFFER] Current buffer has #{@realtime_tts_short_buffer.size} sentence(s)" }

                      combined_text = if @realtime_tts_short_buffer.empty?
                                       text
                                     else
                                       # Combine buffered short sentences with current sentence
                                       # Add space between sentences to prevent words from merging
                                       buffered = @realtime_tts_short_buffer.join(" ")
                                       @realtime_tts_short_buffer.clear
                                       "#{buffered} #{text}"
                                     end

                      # Increment counters and create sequence ID
                      @realtime_tts_sequence_counter += 1
                      sequence_num = @realtime_tts_sequence_counter
                      sequence_id = "seq#{sequence_num}_#{Time.now.to_f}_#{SecureRandom.hex(2)}"

                      Monadic::Utils::ExtraLogger.log { "[BUFFER] *** SENDING TO TTS (long sentence) ***\n[BUFFER] Sequence: #{sequence_num}, ID: #{sequence_id}\n[BUFFER] Combined text to send: '#{combined_text}'\n[BUFFER] Combined text length: #{combined_text.length}" }

                      # Submit TTS request immediately
                      Async do
                        tts_api_request_async(
                          combined_text,
                          provider: provider,
                          voice: voice,
                          speed: speed,
                          response_format: response_format,
                          language: language,
                          sequence_id: sequence_id
                        ) do |res_hash|
                          # This callback runs when TTS completes
                          if res_hash && res_hash["type"] != "error"
                            Monadic::Utils::ExtraLogger.log { "[DEBUG] TTS async callback: sequence_id=#{sequence_id}, type=#{res_hash["type"]}" }

                            # Send audio to client (use captured ws_session_id)
                            if ws_session_id
                              WebSocketHelper.send_audio_to_session(res_hash.to_json, ws_session_id)
                            else
                              WebSocketHelper.broadcast_to_all(res_hash.to_json)
                            end
                          else
                            # TTS failed, just log it (fragment already sent)
                            Monadic::Utils::ExtraLogger.log { "[DEBUG] TTS failed for segment: #{res_hash&.[]("content")}" }
                          end
                        end
                      end
                    end
                  end
                end
              end

              # REALTIME MODE: Keep the last incomplete sentence in buffer
              buffer = [segments.last]

              # Send the fragment to display text (after TTS processing)
              if ws_session_id
                WebSocketHelper.send_to_session(fragment.to_json, ws_session_id)
              else
                WebSocketHelper.broadcast_to_all(fragment.to_json)
              end
            else
              # POST-COMPLETION MODE: Just send fragments, keep everything in buffer
              if ws_session_id
                WebSocketHelper.send_to_session(fragment.to_json, ws_session_id)
              else
                WebSocketHelper.broadcast_to_all(fragment.to_json)
              end
            end
          else
            # Just send the fragment without TTS processing
            if ws_session_id
              WebSocketHelper.send_to_session(fragment.to_json, ws_session_id)
            else
              WebSocketHelper.broadcast_to_all(fragment.to_json)
            end
          end
        else
          # Handle other fragment types (including html, message, etc.)
          Monadic::Utils::ExtraLogger.log { "[WebSocket] Forwarding fragment type='#{fragment["type"]}' to frontend" }
          if ws_session_id
            WebSocketHelper.send_to_session(fragment.to_json, ws_session_id)
          else
            WebSocketHelper.broadcast_to_all(fragment.to_json)
          end
        end
        sleep 0.001  # Reduced from 0.01 for faster streaming
      end

      Thread.exit if !responses || responses.empty?

      # Process final segment for realtime mode
      # The last incomplete sentence in buffer needs to be processed after streaming completes
      # Check both auto_speech and auto_tts_realtime_mode to ensure TTS is intentionally enabled
      # auto_speech can be boolean true or string "true" from client
      # Use original_auto_speech saved before streaming started (obj may have been overwritten)
      auto_speech_enabled = original_auto_speech == true || original_auto_speech == "true"

      Monadic::Utils::ExtraLogger.log { "[DEBUG] Checking final segment conditions:\n[DEBUG]   original_auto_speech=#{original_auto_speech.inspect}, auto_speech_enabled=#{auto_speech_enabled}\n[DEBUG]   cutoff=#{cutoff}, original_monadic=#{original_monadic}, auto_tts_realtime_mode=#{auto_tts_realtime_mode}\n[DEBUG]   Buffer contents: #{buffer.inspect}\n[DEBUG]   Short buffer: #{@realtime_tts_short_buffer.inspect}" }

      if auto_speech_enabled && auto_tts_realtime_mode && !cutoff && !original_monadic
        # Prefer the provider-returned full text when available to avoid token loss
        final_text = responses.last && responses.last["text"] ? responses.last["text"].to_s.strip : ""

        # Fallback to buffered join if full text is not present
        if final_text.empty?
          final_text = buffer.join.strip
        end

        Monadic::Utils::ExtraLogger.log { "[DEBUG] Final text from buffer: '#{final_text}'" }

        # Also check if there are any buffered short sentences that haven't been sent yet
        if !@realtime_tts_short_buffer.empty?
          # Combine buffered short sentences with final text
          # Add space between sentences to prevent words from merging
          buffered = @realtime_tts_short_buffer.join(" ")
          final_text = if final_text.empty?
                        buffered
                      else
                        "#{buffered} #{final_text}"
                      end
          @realtime_tts_short_buffer.clear

          Monadic::Utils::ExtraLogger.log { "[DEBUG] REALTIME MODE: Flushing buffered short sentences into final segment" }
        end

        if final_text != ""
          Monadic::Utils::ExtraLogger.log { "[DEBUG] REALTIME MODE: Processing final segment: '#{final_text[0..50]}...' (length=#{final_text.length})" }

          # Generate unique sequence ID for final segment (use same format as streaming segments)
          # Counter should already be initialized by streaming loop above
          @realtime_tts_sequence_counter += 1
          sequence_num = @realtime_tts_sequence_counter
          sequence_id = "seq#{sequence_num}_#{Time.now.to_f}_#{SecureRandom.hex(2)}"

          # Call async TTS for final segment
          tts_api_request_async(
            final_text,
            provider: provider,
            voice: voice,
            speed: speed,
            response_format: response_format,
            language: language,
            sequence_id: sequence_id
          ) do |res_hash|
            if res_hash && res_hash["type"] != "error"
              Monadic::Utils::ExtraLogger.log { "[DEBUG] TTS final segment callback: sequence_id=#{sequence_id}, type=#{res_hash["type"]}" }
              # Use captured ws_session_id from outer scope
              if ws_session_id
                WebSocketHelper.send_audio_to_session(res_hash.to_json, ws_session_id)
              else
                WebSocketHelper.broadcast_to_all(res_hash.to_json)
              end
            else
              Monadic::Utils::ExtraLogger.log { "[DEBUG] TTS failed for final segment: #{res_hash&.[]("content")}" }
            end
          end
        end
      end

      # Post-completion TTS processing when realtime mode is FALSE
      # Use original_auto_speech (saved before fragment loop) because obj may be overwritten
      # Convert string "true" to boolean true for compatibility
      auto_speech_enabled = original_auto_speech == true || original_auto_speech == "true"

      # Check if monadic is nil or empty string (both should be treated as false/disabled)
      monadic_disabled = original_monadic.nil? || original_monadic.to_s.strip.empty?

      # Check for tts_target extracted text (for monadic apps like Voice Interpreter)
      # This must be checked BEFORE the condition so monadic apps with tts_target can use TTS
      tts_text_from_target = session[:tts_text]

      # TTS is allowed if auto_speech is enabled, not cutoff, and not realtime mode
      # The actual text source is determined later:
      # - If tts_text_from_target exists (tool was called), use that
      # - Otherwise, fall back to buffer.join (works for all apps including monadic)
      #
      # NOTE: The server auto-triggers TTS here. The client should NOT also click
      # the Play button to avoid duplicate audio playback. The client-side code
      # in websocket.js has been updated to skip playButton.click() when Auto TTS
      # is expected (server will send audio automatically).
      tts_allowed = auto_speech_enabled && !cutoff && !auto_tts_realtime_mode

      Monadic::Utils::ExtraLogger.log { "[DEBUG] POST-COMPLETION MODE conditions:\n[DEBUG]   original_auto_speech=#{original_auto_speech.inspect}, auto_speech_enabled=#{auto_speech_enabled.inspect}\n[DEBUG]   cutoff=#{cutoff.inspect}\n[DEBUG]   original_monadic=#{original_monadic.inspect}, monadic_disabled=#{monadic_disabled.inspect}\n[DEBUG]   auto_tts_realtime_mode=#{auto_tts_realtime_mode.inspect}\n[DEBUG]   tts_text_from_target=#{tts_text_from_target ? 'present' : 'nil'}\n[DEBUG]   tts_allowed=#{tts_allowed.inspect}" }

      if tts_allowed
        # Stop any existing TTS thread first
        if defined?(@tts_thread) && @tts_thread && @tts_thread.alive?
          @tts_thread.kill
          @tts_thread = nil
        end

        # Get TTS text: prefer tts_target extraction (from session[:tts_text]) over full buffer
        # This allows apps to specify a specific tool parameter for TTS instead of the full response
        text = tts_text_from_target || buffer.join

        # Clear session tts_text after use to avoid reusing on next request
        session.delete(:tts_text) if tts_text_from_target

        Monadic::Utils::ExtraLogger.log { "[DEBUG] POST-COMPLETION TTS: Using #{tts_text_from_target ? 'tts_target extracted text' : 'buffer.join'}" }

        # Only process if there's actual text
        if text.strip != ""
          start_tts_playback(
            text: text,
            provider: provider,
            voice: voice,
            speed: speed,
            response_format: response_format,
            language: language,
            ws_session_id: ws_session_id
          )
        end
      end

      Monadic::Utils::ExtraLogger.log { "[DEBUG] Processing #{responses&.length || 0} responses\n[DEBUG] responses.nil?=#{responses.nil?}, responses.empty?=#{responses&.empty?}" }

      responses.each do |response|
        # if response is not a hash, skip with error message
        unless response.is_a?(Hash)
          STDERR.puts "Invalid API response format: #{response.class}"
          next
        end

        if response.key?("type") && response["type"] == "error"
          # Extract error message if available, otherwise use the full response
          error_content = if response.key?("content") && !response["content"].to_s.empty?
                           response["content"].to_s
                         else
                           "API Error: " + response.to_s
                         end
          api_error_message = { "type" => "error", "content" => error_content }.to_json
          if ws_session_id
            WebSocketHelper.send_to_session(api_error_message, ws_session_id)
          else
            WebSocketHelper.broadcast_to_all(api_error_message)
          end
        else
          # Debug logging for response structure (only with EXTRA_LOGGING)
          Monadic::Utils::ExtraLogger.log { "WebSocket response structure:\nResponse class: #{response.class}\nResponse keys: #{response.is_a?(Hash) ? response.keys.inspect : 'N/A'}\nHas choices?: #{response.is_a?(Hash) ? response.key?("choices") : 'N/A'}\nResponse: #{response.inspect[0..500]}..." }

          # Check for content in standard format or responses API format
          raw_content = nil

          # Try standard format first
          raw_content = response.dig("choices", 0, "message", "content")

          # If not found, try responses API format
          if raw_content.nil? && response["output"]
            Monadic::Utils::ExtraLogger.log { "Trying responses API format. Output items: #{response["output"].length}" }

            # Look for message type in output array
            response["output"].each do |item|
              Monadic::Utils::ExtraLogger.log { "Output item type: #{item["type"]}, has content?: #{item.key?("content")}" }

              if item["type"] == "message" && item["content"]
                # Extract text from content array
                if item["content"].is_a?(Array)
                  item["content"].each do |content_item|
                    # Handle both "text" and "output_text" types
                    if (content_item["type"] == "text" || content_item["type"] == "output_text") && content_item["text"]
                      raw_content ||= ""
                      raw_content += content_item["text"]
                    end
                  end
                elsif item["content"].is_a?(String)
                  raw_content = item["content"]
                end
              end
            end

            Monadic::Utils::ExtraLogger.log { "Extracted content length: #{raw_content&.length || 0}" }
          end

          # If still no content found
          if raw_content.nil?
            Monadic::Utils::ExtraLogger.log { "ERROR: Content not found. Response structure: #{response.inspect[0..300]}..." }
            content_error = { "type" => "error", "content" => "content_not_found" }.to_json
            if ws_session_id
              WebSocketHelper.send_to_session(content_error, ws_session_id)
            else
              WebSocketHelper.broadcast_to_all(content_error)
            end
            break
          end
          if raw_content
            # Fix sandbox URL paths with a more precise regex that ensures we only replace complete paths
            content = raw_content.gsub(%r{\bsandbox:/([^\s"'<>]+)}, '/\1')
            # Fix mount paths in the same way
            content = content.gsub(%r{^/mnt/([^\s"'<>]+)}, '/\1')
          else
            content = ""
            empty_response_error = { "type" => "error", "content" => "empty_response" }.to_json
            if ws_session_id
              WebSocketHelper.send_to_session(empty_response_error, ws_session_id)
            else
              WebSocketHelper.broadcast_to_all(empty_response_error)
            end
          end

          response.dig("choices", 0, "message")["content"] = content

          # Note: TTS for Session State apps is handled via tts_target feature
          # which extracts text from tool parameters (e.g., save_response message)
          # and stores it in session[:tts_text], processed earlier in the pipeline

          queue.push(response)
        end
      end

      Monadic::Utils::ExtraLogger.log { "[DEBUG] Finished processing responses loop" }

      # Send streaming complete message after all responses are processed (session-targeted)
      Monadic::Utils::ExtraLogger.log { "[DEBUG] About to send streaming_complete for session: #{ws_session_id}" }
      streaming_complete = { "type" => "streaming_complete" }.to_json
      if ws_session_id
        WebSocketHelper.send_to_session(streaming_complete, ws_session_id)
      else
        WebSocketHelper.broadcast_to_all(streaming_complete)
      end
      Monadic::Utils::ExtraLogger.log { "[DEBUG] streaming_complete sent successfully" }
    end
    thread  # return the thread for the orchestrator
  end

  private def handle_ws_check_token(connection, obj, session)
    # Store ui_language in session parameters if provided
    if obj["ui_language"]
      session[:parameters] ||= {}
      session[:parameters]["ui_language"] = obj["ui_language"]
    end

    Monadic::Utils::ExtraLogger.log { "CHECK_TOKEN handler started" }

    if CONFIG["ERROR"].to_s == "true"
      send_to_client(connection, { "type" => "error", "content" => "Error reading <code>~/monadic/config/env</code>" })
    else
      token = CONFIG["OPENAI_API_KEY"]

      Monadic::Utils::ExtraLogger.log { "CHECK_TOKEN: token present=#{!token.nil?}" }

      res = nil
      begin
        res = check_api_key(token) if token

        Monadic::Utils::ExtraLogger.log { "CHECK_TOKEN: res=#{res.inspect}\nCHECK_TOKEN: res.is_a?(Hash)=#{res.is_a?(Hash)}, res.key?('type')=#{res.is_a?(Hash) && res.key?('type')}" }

        if token && res.is_a?(Hash) && res.key?("type")
          if res["type"] == "error"
            Monadic::Utils::ExtraLogger.log { "CHECK_TOKEN: Sending token_not_verified (error)" }
            send_to_client(connection, { "type" => "token_not_verified", "token" => "", "content" => "" })
          else
            Monadic::Utils::ExtraLogger.log { "CHECK_TOKEN: Sending token_verified (success)" }
            send_to_client(connection, { "type" => "token_verified",
                      "token" => token, "content" => res["content"],
                      # "models" => res["models"],
                      "ai_user_initial_prompt" => MonadicApp::AI_USER_INITIAL_PROMPT })
            Monadic::Utils::ExtraLogger.log { "CHECK_TOKEN: token_verified message sent" }
          end
        else
          Monadic::Utils::ExtraLogger.log { "CHECK_TOKEN: Sending token_not_verified (invalid response)" }
          send_to_client(connection, { "type" => "token_not_verified", "token" => "", "content" => "" })
        end
      rescue StandardError => e
        Monadic::Utils::ExtraLogger.log { "CHECK_TOKEN: Exception caught - #{e.class}: #{e.message}" }
        send_to_client(connection, { "type" => "open_ai_api_error", "token" => "", "content" => "" })
      end
    end
  end

  private def handle_ws_ai_user_query(connection, obj, session, thread)
    # Get session ID for targeted broadcasting
    ws_session_id = Thread.current[:websocket_session_id]

    # Check if there are enough messages for AI User to work with
    if session[:messages].nil? || session[:messages].size < 2
      error_msg = {
        "type" => "error",
        "content" => "ai_user_requires_conversation"
      }.to_json
      if ws_session_id
        WebSocketHelper.send_to_session(error_msg, ws_session_id)
      else
        WebSocketHelper.broadcast_to_all(error_msg)
      end
      return
    end

    thread&.join

    # Get parameters
    params = obj["contents"]["params"]

    # UI feedback
    wait_msg = { "type" => "wait", "content" => "generating_ai_user_response" }.to_json
    if ws_session_id
      WebSocketHelper.send_to_session(wait_msg, ws_session_id)
    else
      WebSocketHelper.broadcast_to_all(wait_msg)
    end

    started_msg = { "type" => "ai_user_started" }.to_json
    if ws_session_id
      WebSocketHelper.send_to_session(started_msg, ws_session_id)
    else
      WebSocketHelper.broadcast_to_all(started_msg)
    end

    # Process the request
    begin
      # Get AI user response
      result = process_ai_user(session, params)

      # Handle result
      if result["type"] == "error"
        error_result = { "type" => "error", "content" => result["content"] }.to_json
        if ws_session_id
          WebSocketHelper.send_to_session(error_result, ws_session_id)
        else
          WebSocketHelper.broadcast_to_all(error_result)
        end
      else
        # Send response to client
        ai_user_msg = { "type" => "ai_user", "content" => result["content"] }.to_json
        if ws_session_id
          WebSocketHelper.send_to_session(ai_user_msg, ws_session_id)
        else
          WebSocketHelper.broadcast_to_all(ai_user_msg)
        end

        finished_msg = { "type" => "ai_user_finished", "content" => result["content"] }.to_json
        if ws_session_id
          WebSocketHelper.send_to_session(finished_msg, ws_session_id)
        else
          WebSocketHelper.broadcast_to_all(finished_msg)
        end
      end
    rescue => e
      # Error handling
      rescue_error = { "type" => "error", "content" => { "key" => "ai_user_error", "details" => e.message } }.to_json
      if ws_session_id
        WebSocketHelper.send_to_session(rescue_error, ws_session_id)
      else
        WebSocketHelper.broadcast_to_all(rescue_error)
      end
    end
  end

  private def handle_ws_update_params(connection, obj, session)
    incoming = obj["params"]
    unless incoming.is_a?(Hash)
      send_to_client(connection, { "type" => "error", "content" => "invalid_parameters" })
      return
    end

    session[:parameters] ||= {}

    # Check if app is changing - if so, reset conversation context
    current_app = session[:parameters]["app_name"]
    new_app = incoming["app_name"]&.to_s
    if new_app && current_app && new_app != current_app
      # App is changing - reset conversation context
      if session[:monadic_state]
        session[:monadic_state][:conversation_context] = nil
      end
      Monadic::Utils::ExtraLogger.log { "[WebSocket] App changed from #{current_app} to #{new_app} - context reset" }
    end

    sanitized = {}
    incoming.each do |key, value|
      next if key.nil?
      normalized_key = key.to_s
      next if ["message", "images", "audio", "tts_request", "ws_session_id"].include?(normalized_key)
      sanitized[normalized_key] = value
    end

    sanitized["app_name"] = sanitized["app_name"].to_s if sanitized.key?("app_name")

    session[:parameters].merge!(sanitized)

    sync_session_state!

    # Get session ID for targeted broadcasting
    ws_session_id = Thread.current[:websocket_session_id]

    begin
      param_message = {
        "type" => "parameters",
        "content" => session[:parameters],
        "from_param_update" => true
      }.to_json
      if ws_session_id
        WebSocketHelper.send_to_session(param_message, ws_session_id)
      else
        WebSocketHelper.broadcast_to_all(param_message)
      end
    rescue StandardError => e
      DebugHelper.debug("Parameter broadcast failed: #{e.message}", category: :websocket, level: :error) if defined?(DebugHelper)
    end
  end

  private def handle_ws_system_prompt(connection, obj, session)
    text = obj["content"] || ""

    # Initialize runtime settings for this session
    session[:runtime_settings] ||= {
      language: "auto",
      language_updated_at: nil
    }

    # Store conversation language preference in runtime settings (not in system prompt)
    conversation_language = obj["conversation_language"]
    session[:runtime_settings][:language] = conversation_language || "auto"

    Monadic::Utils::ExtraLogger.log { "SYSTEM_PROMPT: Set language to #{session[:runtime_settings][:language]}\n  Full runtime_settings: #{session[:runtime_settings].inspect}" }

    # Don't add language to the stored system prompt
    # It will be injected dynamically during API calls
    # Note: MathJax prompts are now handled by SystemPromptInjector

    params = get_session_params
    new_data = { "mid" => SecureRandom.hex(4),
                 "role" => "system",
                 "text" => text,
                 "app_name" => params["app_name"],
                 "active" => true }
    # Initial prompt is added to messages but not shown as the first message
    # WebSocketHelper.broadcast_to_all({ "type" => "html", "content" => new_data }.to_json)
    session[:messages] << new_data
    sync_session_state!
  end

  private def handle_ws_sample(connection, obj, session)
    # Get session ID for targeted broadcasting
    ws_session_id = Thread.current[:websocket_session_id]

    begin
      text = obj["content"]
      images = obj["images"]
      # Generate a unique message ID
      message_id = SecureRandom.hex(4)

      params = get_session_params
      # Create message data
      new_data = {
        "mid" => message_id,
        "role" => obj["role"],
        "text" => text,
        "app_name" => params["app_name"],
        "active" => true
      }

      # Add images if present
      new_data["images"] = images if images

      # Phase 2: Server-side HTML rendering disabled
      # Client-side MarkdownRenderer now handles all rendering
      # if obj["role"] == "assistant"
      #   mathjax_enabled = params["mathjax"].to_s == "true"
      #   new_data["html"] = markdown_to_html(text, mathjax: mathjax_enabled)
      # else
      #   # For user and system roles, preserve line breaks
      #   new_data["html"] = text
      # end

      # First add to session
      session[:messages] << new_data
      sync_session_state!

      # Phase 2: Send text content, client handles rendering
      # The display_sample message includes both text and role info
      if obj["role"] == "user"
        badge = "<span class='text-secondary'><i class='fas fa-face-smile'></i></span> <span class='fw-bold fs-6 user-color'>User</span>"
      elsif obj["role"] == "assistant"
        badge = "<span class='text-secondary'><i class='fas fa-robot'></i></span> <span class='fw-bold fs-6 assistant-color'>Assistant</span>"
      else # system
        badge = "<span class='text-secondary'><i class='fas fa-bars'></i></span> <span class='fw-bold fs-6 system-color'>System</span>"
      end

      # Send a dedicated message for immediate display
      display_message = {
        "type" => "display_sample",
        "content" => {
          "mid" => message_id,
          "role" => obj["role"],
          "text" => text,
          "badge" => badge
        }
      }.to_json
      if ws_session_id
        WebSocketHelper.send_to_session(display_message, ws_session_id)
      else
        WebSocketHelper.broadcast_to_all(display_message)
      end

      # Also send HTML message for session history
      html_message = { "type" => "html", "content" => new_data }.to_json
      if ws_session_id
        WebSocketHelper.send_to_session(html_message, ws_session_id)
      else
        WebSocketHelper.broadcast_to_all(html_message)
      end

      # Add a success response to confirm message was processed
      success_message = { "type" => "sample_success", "role" => obj["role"] }.to_json
      if ws_session_id
        WebSocketHelper.send_to_session(success_message, ws_session_id)
      else
        WebSocketHelper.broadcast_to_all(success_message)
      end
    rescue => e
      # Log the error
      puts "Error processing SAMPLE message: #{e.message}"
      puts e.backtrace

      # Inform the client
      error_message = { "type" => "error", "content" => "error_processing_sample" }.to_json
      if ws_session_id
        WebSocketHelper.send_to_session(error_message, ws_session_id)
      else
        WebSocketHelper.broadcast_to_all(error_message)
      end
    end
  end

  private def handle_ws_update_language(connection, obj, session)
    # Get session ID for targeted broadcasting
    ws_session_id = Thread.current[:websocket_session_id]

    # Handle language change during session
    old_language = session[:runtime_settings][:language] if session[:runtime_settings]
    new_language = obj["new_language"]

    # Update UI language in parameters as well
    session[:parameters] ||= {}
    session[:parameters]["ui_language"] = new_language

    # Initialize runtime_settings if not exists
    session[:runtime_settings] ||= {
      language: "auto",
      language_updated_at: nil
    }

    if old_language != new_language
      session[:runtime_settings][:language] = new_language
      session[:runtime_settings][:language_updated_at] = Time.now

      Monadic::Utils::ExtraLogger.log { "UPDATE_LANGUAGE: #{old_language} -> #{new_language}\n  Runtime settings: #{session[:runtime_settings].inspect}" }

      # Resend apps data with updated language descriptions
      apps_data = prepare_apps_data(new_language)
      unless apps_data.empty?
        apps_message = { "type" => "apps", "content" => apps_data }.to_json
        if ws_session_id
          WebSocketHelper.send_to_session(apps_message, ws_session_id)
        else
          WebSocketHelper.broadcast_to_all(apps_message)
        end
      end

      # Notify client of successful update
      language_name = if new_language == "auto"
                        "Automatic"
                      else
                        Monadic::Utils::LanguageConfig::LANGUAGES[new_language][:english]
                      end

      language_updated_message = {
        "type" => "language_updated",
        "language" => new_language,
        "language_name" => language_name,
        "text_direction" => Monadic::Utils::LanguageConfig.text_direction(new_language)
      }.to_json
      if ws_session_id
        WebSocketHelper.send_to_session(language_updated_message, ws_session_id)
      else
        WebSocketHelper.broadcast_to_all(language_updated_message)
      end
    end
  end





  private def handle_ws_reset(session)
    session[:messages].clear
    session[:parameters].clear
    session[:progressive_tools]&.clear  # Reset Progressive Tool Disclosure state
    session[:monadic_state]&.clear  # Reset conversation context for Session Context panel
    session[:error] = nil
    session[:obj] = nil
    # Clear provider-specific media references to prevent cross-session leakage
    session.keys
      .select { |k| k.is_a?(Symbol) && (k.to_s.match?(/last_image|last_video/) || k == :tool_html_fragments) }
      .each { |k| session.delete(k) }
    sync_session_state!
  end

  def send_to_client(connection, message_hash)
    connection.write(message_hash.to_json)
    connection.flush
  rescue => e
    Monadic::Utils::ExtraLogger.log { "[WebSocket] Error sending to client: #{e.message}" }
  end

  # Handle MCP configuration update
  def handle_mcp_config_update(connection, obj)
    # Update configuration
    CONFIG["MCP_SERVER_ENABLED"] = obj["enabled"] # Keep as boolean
    CONFIG["MCP_SERVER_PORT"] = obj["port"] if obj["port"]
    
    # Write updated config to file (optional - depends on persistence requirements)
    # This would require implementing a save_config method
    
    # Send updated MCP server status
    if defined?(Monadic::MCP::Server)
      mcp_status = Monadic::MCP::Server.status
      send_to_client(connection, { "type" => "mcp_status", "content" => mcp_status })
    end

    send_to_client(connection, { "type" => "info", "content" => "MCP configuration updated" })
  end

  # Handle context update from client sidebar panel
  # This is called when user edits context directly in the sidebar
  def handle_context_update_from_client(connection, obj)
    current_session = session
    context = obj["context"]

    return unless context.is_a?(Hash)

    # Save context to session state using MonadicSessionState
    begin
      # Use the same key as SessionContext module
      context_key = :conversation_context

      # Save to session state
      result = JSON.parse(monadic_save_state(key: context_key, payload: context, session: current_session))

      if result["success"]
        # Broadcast the update back to confirm (session-specific)
        ws_session_id = Thread.current[:websocket_session_id]
        message = {
          "type" => "context_update",
          "context" => context,
          "timestamp" => Time.now.to_f
        }

        if ws_session_id
          WebSocketHelper.send_to_session(message.to_json, ws_session_id)
        end

        Monadic::Utils::ExtraLogger.log { "[WebSocket] Context updated from client: #{context.keys.join(', ')}" }
      else
        send_to_client(connection, { "type" => "error", "content" => "Failed to save context" })
      end
    rescue StandardError => e
      Monadic::Utils::ExtraLogger.log { "[WebSocket] Context update error: #{e.message}" }
      send_to_client(connection, { "type" => "error", "content" => "Context update error: #{e.message}" })
    end
  end
end
