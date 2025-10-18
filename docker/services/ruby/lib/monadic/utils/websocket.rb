# frozen_string_literal: true

require 'timeout'
require 'set'  # For session management with multiple connections
require 'net/http'
require 'uri'
require_relative '../agents/ai_user_agent'
require_relative 'boolean_parser'
require_relative 'ssl_configuration'
require_relative 'string_utils'

Monadic::Utils::SSLConfiguration.configure! if defined?(Monadic::Utils::SSLConfiguration)

module WebSocketHelper
  include AIUserAgent
  # Handle websocket connection

  # Realtime TTS buffer configuration
  # Minimum character length for TTS processing:
  # - Sentences ≤ this length are buffered
  # - Buffer is flushed when total exceeds this length
  # Larger values (e.g., 50) reduce API calls and errors, improve fluency
  # but may slightly increase initial response delay
  REALTIME_TTS_MIN_LENGTH = 50

  # Class variable to store WebSocket connections with thread safety
  @@ws_connections = []
  @@ws_mutex = Mutex.new
  @@channel = nil  # Store EventMachine channel reference
  
  # Add a connection to the list (thread-safe)
  def self.add_connection(ws)
    @@ws_mutex.synchronize do
      @@ws_connections << ws unless @@ws_connections.include?(ws)
    end
  end
  
  # Remove a connection from the list (thread-safe)
  def self.remove_connection(ws)
    @@ws_mutex.synchronize do
      @@ws_connections.delete(ws)
    end
  end
  
  # Broadcast MCP status to all connected clients (thread-safe)
  def self.broadcast_mcp_status(status)
    message = {
      event: "mcp_status",
      data: status
    }.to_json

    # Create a copy of connections to avoid holding lock during I/O
    connections_copy = @@ws_mutex.synchronize { @@ws_connections.dup }

    connections_copy.each do |ws|
      begin
        # Check if WebSocket is open (Faye::WebSocket uses ready_state)
        if ws && ws.ready_state == Faye::WebSocket::OPEN
          ws.send(message)
        end
      rescue => e
        # Log WebSocket send error and remove dead connection
        puts "[WebSocket] Send error: #{e.message}" if CONFIG["EXTRA_LOGGING"]
        remove_connection(ws)
      end
    end
  end

  # Set the EventMachine channel for broadcasting
  def self.set_channel(channel)
    @@channel = channel
  end

  # Broadcast to all connected clients (thread-safe)
  def self.broadcast_to_all(message)
    # Use EventMachine channel if available (preferred)
    if @@channel
      begin
        @@channel.push(message)
        if CONFIG["EXTRA_LOGGING"]
          puts "[WebSocketHelper] Broadcasted via channel: #{message[0..100]}..."
        end
      rescue => e
        puts "[WebSocketHelper] Channel broadcast error: #{e.message}" if CONFIG["EXTRA_LOGGING"]
      end
    else
      # Fallback to direct WebSocket sending
      connections_copy = @@ws_mutex.synchronize { @@ws_connections.dup }

      connections_copy.each do |ws|
        begin
          # Check if WebSocket is open (Faye::WebSocket uses ready_state)
          if ws && ws.ready_state == Faye::WebSocket::OPEN
            ws.send(message)
          end
        rescue => e
          # Log WebSocket send error and remove dead connection
          puts "[WebSocket] Send error: #{e.message}" if CONFIG["EXTRA_LOGGING"]
          remove_connection(ws)
        end
      end
    end
  end

  # ============= Progress Broadcasting Features =============

  # Session management for progress updates
  # One session ID can have multiple WebSocket connections (e.g., multiple tabs)
  @@connections_by_session = Hash.new { |h, k| h[k] = Set.new }
  @@session_mutex = Mutex.new

  # Feature Flag for progress broadcasting
  def self.progress_broadcast_enabled?
    return false unless defined?(CONFIG)
    CONFIG["WEBSOCKET_PROGRESS_ENABLED"] != false  # Default true
  end

  # Broadcast progress message to specific session or all
  # @param fragment [Hash] Complete fragment object with progress info
  # @param target_session_id [String, nil] Specific session to target
  def self.broadcast_progress(fragment, target_session_id = nil)
    return unless progress_broadcast_enabled?

    # Build complete message
    message = if fragment.is_a?(Hash)
      fragment.merge("timestamp" => Time.now.to_f)
    else
      {
        "type" => "wait",
        "content" => fragment.to_s,
        "timestamp" => Time.now.to_f
      }
    end

    message_json = message.to_json

    # Send to specific session or broadcast to all
    if target_session_id
      send_to_session(message_json, target_session_id)
    else
      broadcast_to_all(message_json)
    end
  rescue => e
    if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
      puts "[WebSocketHelper] Error broadcasting progress: #{e.message}"
    end
  end

  # Send message to specific session
  def self.send_to_session(message_json, session_id)
    return unless session_id

    # IMPORTANT: Always use the channel to ensure messages appear in temp card
    # Messages must go through the channel to be properly displayed in the UI
    if @@channel
      begin
        # Parse the message to add session_id if not present
        message_data = JSON.parse(message_json) rescue {}
        message_data["session_id"] = session_id unless message_data["session_id"]

        # Send via channel - this ensures it appears in temp card
        @@channel.push(message_data.to_json)

        if CONFIG["EXTRA_LOGGING"]
          puts "[WebSocketHelper] Sent to session #{session_id} via channel: #{message_json[0..100]}..."
        end
      rescue => e
        puts "[WebSocketHelper] Channel send error for session #{session_id}: #{e.message}" if CONFIG["EXTRA_LOGGING"]
      end
    else
      # Fallback: direct send if no channel (shouldn't happen normally)
      websockets = @@session_mutex.synchronize { @@connections_by_session[session_id].dup }

      if websockets.empty?
        if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
          puts "[WebSocketHelper] No connections found for session #{session_id}"
        end
        return
      end

      # Collect connections to remove (avoid modification during iteration)
      to_remove = []

      websockets.each do |ws|
        begin
          if ws && ws.ready_state == Faye::WebSocket::OPEN
            ws.send(message_json)
          else
            to_remove << ws
          end
        rescue => e
          if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
            puts "[WebSocketHelper] Error sending to session #{session_id}: #{e.message}"
          end
          to_remove << ws
        end
      end

      # Remove dead connections after iteration
      unless to_remove.empty?
        @@session_mutex.synchronize do
          to_remove.each { |ws| @@connections_by_session[session_id].delete(ws) }
        end

        if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
          puts "[WebSocketHelper] Cleaned up #{to_remove.size} dead connections for session #{session_id}"
        end
      end
    end
  end

  # Add WebSocket connection with session tracking
  def self.add_connection_with_session(ws, session_id = nil)
    # Add to regular connections list
    add_connection(ws)

    # Add to session tracking if session_id provided
    if session_id
      @@session_mutex.synchronize do
        @@connections_by_session[session_id].add(ws)
      end

      if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
        count = @@session_mutex.synchronize { @@connections_by_session[session_id].size }
        puts "[WebSocketHelper] Added connection for session #{session_id}, total: #{count}"
      end
    end
  end

  # Remove WebSocket connection with session tracking
  def self.remove_connection_with_session(ws, session_id = nil)
    # Remove from regular connections list
    remove_connection(ws)

    # Remove from session tracking if session_id provided
    if session_id
      @@session_mutex.synchronize do
        @@connections_by_session[session_id].delete(ws)

        # Remove empty session entries
        if @@connections_by_session[session_id].empty?
          @@connections_by_session.delete(session_id)
        end
      end

      if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
        remaining = @@session_mutex.synchronize { @@connections_by_session[session_id]&.size || 0 }
        puts "[WebSocketHelper] Removed connection for session #{session_id}, remaining: #{remaining}"
      end
    end
  end

  # Send progress fragment with type checking
  def self.send_progress_fragment(fragment, target_session_id = nil)
    return unless fragment.is_a?(Hash)

    # Only send wait or fragment type messages
    if fragment["type"] == "wait" || fragment["type"] == "fragment"
      broadcast_progress(fragment, target_session_id)
    end
  end

  # Clean up stale sessions periodically
  def self.cleanup_stale_sessions
    @@session_mutex.synchronize do
      @@connections_by_session.each do |session_id, websockets|
        # Collect dead connections
        to_remove = []
        websockets.each do |ws|
          if ws.nil? || ws.ready_state != Faye::WebSocket::OPEN
            to_remove << ws
          end
        end

        # Remove after iteration
        to_remove.each { |ws| websockets.delete(ws) }

        # Remove empty sessions
        @@connections_by_session.delete(session_id) if websockets.empty?
      end
    end
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

  # List available ElevenLabs voices
  # @param api_key [String, nil] Optional API key
  # @return [Array] Array of voice data
  def list_elevenlabs_voices(api_key = nil)
    # Use provided API key or default from config
    api_key ||= CONFIG["ELEVENLABS_API_KEY"] if defined?(CONFIG)
    return [] unless api_key
    
    # Direct implementation to avoid dependency issues with InteractionUtils
    begin
      url = URI("https://api.elevenlabs.io/v1/voices")
      http = Net::HTTP.new(url.host, url.port)
      http.use_ssl = true
      request = Net::HTTP::Get.new(url)
      request["xi-api-key"] = api_key
      response = http.request(request)
      
      return [] unless response.is_a?(Net::HTTPSuccess)
      
      voices = response.read_body
      
      begin
        parsed_voices = JSON.parse(voices)
      rescue JSON::ParserError => e
        DebugHelper.debug("Invalid JSON from ElevenLabs API: #{voices[0..200]}", "api", level: :error)
        return []
      end
      
      parsed_voices&.dig("voices")&.map do |voice|
        {
          "voice_id" => voice["voice_id"],
          "name" => voice["name"]
        }
      end || []
    rescue Net::ReadTimeout => e
      DebugHelper.debug("Timeout reading ElevenLabs voices", "api", level: :warning)
      []
    rescue StandardError => e
      []
    end
  end

  # Handle the LOAD message by preparing and sending relevant data
  # @param ws [Faye::WebSocket] WebSocket connection
  def handle_load_message(ws)
    # Handle error if present
    if session[:error]
      ws.send({ "type" => "error", "content" => session[:error] }.to_json)
      session[:error] = nil
    end
    
    # Prepare app data
    apps_data = prepare_apps_data
    
    # Filter and prepare messages
    filtered_messages = prepare_filtered_messages
    
    # Send app data
    push_apps_data(ws, apps_data, filtered_messages)
    
    # Handle voice data
    push_voice_data(ws)
    
    # Send MCP server status if available
    if defined?(Monadic::MCP::Server)
      mcp_status = Monadic::MCP::Server.status
      ws.send({ "type" => "mcp_status", "content" => mcp_status }.to_json)
    end
    
    # Update message status
    update_message_status(ws, filtered_messages)
  end
  
  # Prepare apps data with settings
  # @return [Hash] Apps data with settings
  def prepare_apps_data(ui_language = nil)
    return {} unless defined?(APPS)
    
    # Get UI language from session parameters if not provided
    ui_language ||= session[:parameters]&.[]("ui_language") || "en"
    
    # Debug logging for language selection
    if CONFIG["EXTRA_LOGGING"]
      puts "[DEBUG] prepare_apps_data called with ui_language: #{ui_language}"
    end
    
    apps = {}
    APPS.each do |k, v|
      apps[k] = {}
      v.settings.each do |p, m|
        # Debug log for reasoning_effort in all OpenAI apps
        if p == "reasoning_effort" && CONFIG["EXTRA_LOGGING"]
          extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
          extra_log.puts("[#{Time.now}] WebSocket: #{k} reasoning_effort = #{m.inspect}")
          extra_log.close
        end
        
        # Handle description specially for multi-language support
        if p == "description"
          if m.is_a?(Hash)
            # Multi-language description: select the appropriate language
            # Fallback order: requested language -> English -> first available
            selected_desc = m[ui_language] || m["en"] || m.values.first || ""
            apps[k][p] = selected_desc
            
            # Debug logging for multi-language descriptions
            if CONFIG["EXTRA_LOGGING"] && k == "SampleMultilang"
              puts "[DEBUG] SampleMultilang description selection:"
              puts "  Requested language: #{ui_language}"
              puts "  Available languages: #{m.keys.join(', ')}"
              puts "  Selected description: #{selected_desc[0..50]}..."
            end
          else
            # Single string description (backward compatibility)
            apps[k][p] = m ? m.to_s : ""
          end
        # Special case for models array to ensure it's properly sent as JSON
        elsif p == "models" && m.is_a?(Array)
          apps[k][p] = m.to_json
        elsif p == "tools" && (m.is_a?(Array) || m.is_a?(Hash))
          # Tools need to be sent as proper JSON too
          apps[k][p] = m.to_json
        elsif p == "disabled"
          # Keep disabled as a string for compatibility with frontend
          apps[k][p] = m.to_s
        elsif ["auto_speech", "easy_submit", "initiate_from_assistant", "mathjax", "mermaid", "abc", "sourcecode", "monadic", "image", "pdf", "pdf_vector_storage", "websearch", "jupyter_access", "jupyter", "image_generation", "video"].include?(p.to_s)
          # Preserve boolean values for feature flags
          # These need to be actual booleans, not strings, for proper JavaScript evaluation
          apps[k][p] = m
        else
          apps[k][p] = m ? m.to_s : nil
        end
      end
      v.api_key = settings.api_key if v.respond_to?(:api_key=) && settings.respond_to?(:api_key)
    end
    apps
  end
  
  # Filter and prepare messages for display
  # @return [Array] Filtered and formatted messages
  def prepare_filtered_messages
    # Filter messages by current app_name and exclude search messages
    current_app_name = session["parameters"]["app_name"]
    filtered_messages = session[:messages].filter { |m| m["type"] != "search" && m["app_name"] == current_app_name }
    
    # Convert markdown to HTML for assistant messages if html field is missing
    filtered_messages.each do |m|
      if m["role"] == "assistant" && !m["html"]
        m["html"] = if session["parameters"]&.[]("monadic") && defined?(APPS) && 
                      session["parameters"]["app_name"] && 
                      APPS[session["parameters"]["app_name"]]&.respond_to?(:monadic_html)
                    APPS[session["parameters"]["app_name"]].monadic_html(m["text"])
                  else
                    mathjax_enabled = session["parameters"]["mathjax"].to_s == "true"
                    markdown_to_html(m["text"], mathjax: mathjax_enabled)
                  end
      end
    end
    
    filtered_messages
  end
  
  # Log error with appropriate level based on environment
  # @param message [String] Error message prefix
  # @param error [StandardError] The error object
  # @param level [Symbol] Log level (:info, :warn, :error, etc)
  def log_error(message, error, level = :error)
    # Skip verbose logging in test environment
    return if defined?(RSpec)
    
    # Use Rails logger if available
    if defined?(Rails) && Rails.logger
      Rails.logger.send(level, "#{message}: #{error.message}")
      Rails.logger.debug(error.backtrace.join("\n")) if level == :error
    # Use Ruby logger if available
    elsif defined?(Logger) && instance_variable_defined?(:@logger)
      @logger.send(level, "#{message}: #{error.message}")
      @logger.debug(error.backtrace.join("\n")) if level == :error
    # Fallback to puts for development
    elsif ENV["RACK_ENV"] != "test"
      puts "#{level.to_s.upcase}: #{message}: #{error.message}"
      puts error.backtrace.join("\n") if level == :error
    end
  end
  
  # Push apps data to WebSocket
  # @param ws [Faye::WebSocket] WebSocket connection
  # @param apps [Hash] Apps data
  # @param filtered_messages [Array] Filtered messages
  def push_apps_data(ws, apps, filtered_messages)
    @channel.push({ "type" => "apps", "content" => apps, "version" => session[:version], "docker" => session[:docker] }.to_json) unless apps.empty?
    @channel.push({ "type" => "parameters", "content" => session[:parameters] }.to_json) unless session[:parameters].empty?
    @channel.push({ "type" => "past_messages", "content" => filtered_messages }.to_json) unless session[:messages].empty?
  end
  
  # Push voice data to WebSocket
  # @param ws [Faye::WebSocket] WebSocket connection
  def push_voice_data(ws)
    elevenlabs_voices = list_elevenlabs_voices
    if elevenlabs_voices && !elevenlabs_voices.empty?
      @channel.push({ "type" => "elevenlabs_voices", "content" => elevenlabs_voices }.to_json)
    end
    
    # Send Gemini voices if API key is available
    if CONFIG["GEMINI_API_KEY"]
      gemini_voices = [
        { "voice_id" => "aoede", "name" => "Aoede" },
        { "voice_id" => "charon", "name" => "Charon" },
        { "voice_id" => "fenrir", "name" => "Fenrir" },
        { "voice_id" => "kore", "name" => "Kore" },
        { "voice_id" => "orus", "name" => "Orus" },
        { "voice_id" => "puck", "name" => "Puck" },
        { "voice_id" => "schedar", "name" => "Schedar" },
        { "voice_id" => "zephyr", "name" => "Zephyr" }
      ]
      @channel.push({ "type" => "gemini_voices", "content" => gemini_voices }.to_json)
    end
  end
  
  # Update message status and push info
  # @param ws [Faye::WebSocket] WebSocket connection
  # @param filtered_messages [Array] Filtered messages
  def update_message_status(ws, filtered_messages)
    past_messages_data = check_past_messages(session[:parameters])

    # Reuse filtered_messages for change_status
    @channel.push({ "type" => "change_status", "content" => filtered_messages }.to_json) if past_messages_data[:changed]
    @channel.push({ "type" => "info", "content" => past_messages_data }.to_json)
  end

  # Common TTS playback processing for PLAY_TTS and Auto Speech
  # This method handles text segmentation, prefetching, and threaded TTS generation
  # @param text [String] Text to convert to speech
  # @param provider [String] TTS provider (e.g., "elevenlabs-v3", "gemini-flash")
  # @param voice [String] Voice ID
  # @param speed [Float] Speech speed
  # @param response_format [String] Audio format (e.g., "mp3")
  # @param language [String] Language code
  def start_tts_playback(text:, provider:, voice:, speed:, response_format:, language:)
    # Strip Markdown markers and HTML tags before processing
    text = StringUtils.strip_markdown_for_tts(text)

    # Process text with PragmaticSegmenter to split into sentences
    ps = PragmaticSegmenter::Segmenter.new(text: text)
    segments = ps.segment

    # For Gemini TTS, combine short segments to avoid API failures
    if provider == "gemini-flash" || provider == "gemini-pro"
      combined_segments = []
      current_segment = ""

      segments.each do |segment|
        # Clean and check text
        cleaned_text = segment.gsub(/[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]/, '') # Remove emojis
        cleaned_text = cleaned_text.gsub(/[^\p{L}\p{N}\p{P}\p{Z}]+/, ' ') # Remove special chars
        cleaned_text = cleaned_text.strip

        if current_segment.empty?
          # Start a new segment
          current_segment = segment
        elsif cleaned_text.length < 8  # Increased threshold for safety
          # Current segment is short, combine with existing
          current_segment += " " + segment
        else
          # Check if current accumulated segment should be finalized
          current_cleaned = current_segment.gsub(/[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]/, '')
          current_cleaned = current_cleaned.gsub(/[^\p{L}\p{N}\p{P}\p{Z}]+/, ' ').strip

          if current_cleaned.length < 8  # Combine if still short
            current_segment += " " + segment
          else
            # Finalize current segment and start new one
            combined_segments << current_segment if current_cleaned.length >= 3
            current_segment = segment
          end
        end
      end

      # Don't forget the last segment - but validate it first
      unless current_segment.empty?
        final_cleaned = current_segment.gsub(/[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]/, '')
        final_cleaned = final_cleaned.gsub(/[^\p{L}\p{N}\p{P}\p{Z}]+/, ' ').strip
        combined_segments << current_segment if final_cleaned.length >= 3
      end

      segments = combined_segments
      puts "Gemini TTS: #{ps.segment.length} -> #{segments.length} segments" if ENV["DEBUG_TTS"]
    end

    # Process each segment
    prev_texts_for_tts = []
    segments = Array(segments)

    # ElevenLabs V3: Check if segments should be combined (legacy behavior)
    # Default is false (use segment splitting for prefetch benefits)
    # Set ELEVENLABS_V3_COMBINE_SEGMENTS=true to combine all segments into one
    if provider == "elevenlabs-v3"
      combine_segments = defined?(CONFIG) && CONFIG["ELEVENLABS_V3_COMBINE_SEGMENTS"].to_s == "true"
      if combine_segments
        combined_text = segments.join(" ").strip
        segments = combined_text.empty? ? [] : [combined_text]
        puts "ElevenLabs V3: Combined all segments into one (legacy mode)" if CONFIG["EXTRA_LOGGING"]
      else
        puts "ElevenLabs V3: Using segment splitting for prefetch (#{segments.length} segments)" if CONFIG["EXTRA_LOGGING"]
      end
    end

    # Start a new thread for TTS processing with prefetching
    @tts_thread = Thread.new do
      Thread.current[:type] = :tts_playback

      # Filter and prepare segments
      valid_segments = []
      segments.each do |segment|
        next if segment.strip.empty?

        # Light filtering for Gemini TTS
        if provider == "gemini-flash" || provider == "gemini-pro"
          cleaned_segment = segment.strip
          next if cleaned_segment.length < 3
          valid_segments << cleaned_segment
        else
          valid_segments << segment
        end
      end

      # Prefetch pipeline: Start first 3 TTS requests in parallel (improved from 2)
      tts_futures = []
      # Store futures array in thread local for STOP_TTS cleanup
      Thread.current[:tts_futures] = tts_futures

      # Special handling for Web Speech API - no prefetching needed (no API calls)
      if provider == "webspeech" || provider == "web-speech"
        # Process synchronously for Web Speech API
        valid_segments.each_with_index do |segment, i|
          res_hash = { "type" => "web_speech", "content" => segment }

          prev_texts_for_tts << segment unless provider == "elevenlabs-v3"

          # Send audio and progress
          @channel.push(res_hash.to_json)

          progress_message = {
            "type" => "tts_progress",
            "segment_index" => i,
            "total_segments" => valid_segments.length,
            "progress" => ((i + 1) / valid_segments.length.to_f * 100).round
          }
          @channel.push(progress_message.to_json)
        end
      else
        # Prefetch mode for API-based TTS providers
        # Start first 3 requests to prevent gaps between short sentences
        [0, 1, 2].each do |idx|
          break if idx >= valid_segments.length

          segment = valid_segments[idx]
          # Get previous_text directly from valid_segments for initial prefetch
          previous_text = if provider == "elevenlabs-v3"
                            nil
                          elsif idx > 0
                            valid_segments[idx - 1]
                          else
                            nil
                          end

          tts_futures << Thread.new do
            tts_api_request(segment,
                          previous_text: previous_text,
                          provider: provider,
                          voice: voice,
                          speed: speed,
                          response_format: response_format,
                          language: language)
          end
        end

        # Process segments in order
        valid_segments.each_with_index do |segment, i|
          # Wait for current segment's TTS to complete with error handling
          begin
            res_hash = tts_futures[i]&.value
          rescue => e
            # Thread was killed or errored - create error response
            puts "TTS segment #{i} failed with exception: #{e.message}" if CONFIG["EXTRA_LOGGING"]
            res_hash = {
              "type" => "error",
              "content" => "TTS generation failed for segment #{i + 1}"
            }
          end

          # Add segment information
          if res_hash && res_hash["type"] == "audio"
            res_hash["segment_index"] = i
            res_hash["total_segments"] = valid_segments.length
            res_hash["is_segment"] = true
          end

          # Store for context
          prev_texts_for_tts << segment unless provider == "elevenlabs-v3"

          # Start next segment's TTS request (prefetch i+3 to maintain 3-segment buffer)
          next_idx = i + 3
          if next_idx < valid_segments.length
            next_segment = valid_segments[next_idx]
            # Get previous_text directly from valid_segments for prefetch
            next_previous_text = if provider == "elevenlabs-v3"
                                  nil
                                elsif next_idx > 0
                                  valid_segments[next_idx - 1]
                                else
                                  nil
                                end

            tts_futures << Thread.new do
              tts_api_request(next_segment,
                            previous_text: next_previous_text,
                            provider: provider,
                            voice: voice,
                            speed: speed,
                            response_format: response_format,
                            language: language)
            end
          end

          # Send audio and progress
          if res_hash && res_hash["type"] != "error"
            @channel.push(res_hash.to_json)

            progress_message = {
              "type" => "tts_progress",
              "segment_index" => i,
              "total_segments" => valid_segments.length,
              "progress" => ((i + 1) / valid_segments.length.to_f * 100).round
            }
            @channel.push(progress_message.to_json)
          else
            puts "TTS segment #{i} failed: #{res_hash&.dig("content") || "Unknown error"}"
          end
        end
      end

      # Signal completion
      @channel.push({
        "type" => "tts_complete",
        "total_segments" => valid_segments.length
      }.to_json)
    end
  end
  
  # Handle DELETE message
  # @param ws [Faye::WebSocket] WebSocket connection
  # @param obj [Hash] Parsed message object
  def handle_delete_message(ws, obj)
    # Delete the message
    session[:messages].delete_if { |m| m["mid"] == obj["mid"] }
    
    # Check message status
    past_messages_data = check_past_messages(session[:parameters])
    
    # Filter messages
    filtered_messages = prepare_filtered_messages
    
    # Update status
    @channel.push({ "type" => "change_status", "content" => filtered_messages }.to_json) if past_messages_data[:changed]
    @channel.push({ "type" => "info", "content" => past_messages_data }.to_json)
  end
  
  # Handle EDIT message
  # @param ws [Faye::WebSocket] WebSocket connection
  # @param obj [Hash] Parsed message object
  def handle_edit_message(ws, obj)
    # Find the message to edit
    message_to_edit = session[:messages].find { |m| m["mid"] == obj["mid"] }
    
    if message_to_edit
      # Update the message text
      message_to_edit["text"] = obj["content"]
      
      # Update images if provided in the edit request
      if obj["images"] && obj["images"].is_a?(Array)
        message_to_edit["images"] = obj["images"]
      end
      
      # Generate HTML content if needed
      html_content = generate_html_for_message(message_to_edit, obj["content"])
      
      # Create response with updated HTML for the client
      response = {
        "type" => "edit_success",
        "content" => "Message updated successfully",
        "mid" => obj["mid"],
        "role" => message_to_edit["role"],
        "html" => html_content
      }
      
      # Include images if they exist
      if message_to_edit["images"] && message_to_edit["images"].is_a?(Array) && !message_to_edit["images"].empty?
        response["images"] = message_to_edit["images"]
      end
      
      # Push the response
      @channel.push(response.to_json)
      
      # Update message status
      update_message_status_after_edit
    else
      # Message not found
      @channel.push({ "type" => "error", "content" => "message_not_found_for_editing" }.to_json)
    end
  end
  
  # Generate HTML content for a message
  # @param message [Hash] The message to generate HTML for
  # @param content [String] The text content
  # @return [String, nil] The HTML content or nil
  def generate_html_for_message(message, content)
    return nil unless message["role"] == "assistant"
    
    html_content = if session["parameters"]&.[]("monadic") && 
                     defined?(APPS) && 
                     session["parameters"]["app_name"] && 
                     APPS[session["parameters"]["app_name"]]&.respond_to?(:monadic_html)
                   APPS[session["parameters"]["app_name"]].monadic_html(content)
                 else
                   mathjax_enabled = session["parameters"]["mathjax"].to_s == "true"
                   markdown_to_html(content, mathjax: mathjax_enabled)
                 end
    
    message["html"] = html_content
    html_content
  end
  
  # Update message status after edit
  def update_message_status_after_edit
    past_messages_data = check_past_messages(session[:parameters])

    # Filter messages by current app_name and exclude search messages
    current_app_name = session["parameters"]["app_name"]
    filtered_messages = session[:messages].filter { |m| m["type"] != "search" && m["app_name"] == current_app_name }
    
    # Update status to reflect any changes
    @channel.push({ "type" => "change_status", "content" => filtered_messages }.to_json) if past_messages_data[:changed]
    @channel.push({ "type" => "info", "content" => past_messages_data }.to_json)
  end
  
  # Handle AUDIO message
  # @param ws [Faye::WebSocket] WebSocket connection
  # @param obj [Hash] Parsed message object
  def handle_audio_message(ws, obj)
    if obj["content"].nil?
      @channel.push({ "type" => "error", "content" => "voice_input_empty" }.to_json)
      return
    end
    
    # Decode audio content
    blob = Base64.decode64(obj["content"])
    
    # Get configuration
    model = get_stt_model
    format = obj["format"] || "webm"
    
    # Process the transcription
    process_transcription(ws, blob, format, obj["lang_code"], model)
  end
  
  # Get the speech-to-text model from config
  # @return [String] The model name
  def get_stt_model
    defined?(CONFIG) && CONFIG["STT_MODEL"] ? CONFIG["STT_MODEL"] : "gpt-4o-transcribe"
  end
  
  # Process audio transcription
  # @param ws [Faye::WebSocket] WebSocket connection
  # @param blob [String] The decoded audio data
  # @param format [String] The audio format
  # @param lang_code [String] The language code
  # @param model [String] The model to use
  def process_transcription(ws, blob, format, lang_code, model)
    begin
      # Request transcription
      res = stt_api_request(blob, format, lang_code, model)
      
      if res["text"] && res["text"] == ""
        @channel.push({ "type" => "error", "content" => "text_input_empty" }.to_json)
      elsif res["type"] && res["type"] == "error"
        # Include format information in error message for debugging
        error_message = "#{res["content"]} (using format: #{format}, model: #{model})"
        @channel.push({ "type" => "error", "content" => error_message }.to_json)
      else
        send_transcription_result(ws, res, model)
      end
    rescue StandardError => e
      # Log the error but don't crash the application
      log_error("Error processing transcription", e) 
      
      # Send a generic error message to the client
      @channel.push({ 
        "type" => "error", 
        "content" => "An error occurred while processing your audio"
      }.to_json)
    end
  end
  
  # Calculate confidence and send transcription result
  # @param ws [Faye::WebSocket] WebSocket connection
  # @param res [Hash] The transcription result
  # @param model [String] The model used
  def send_transcription_result(ws, res, model)
    begin
      logprob = calculate_logprob(res, model)
      
      @channel.push({
        "type" => "stt",
        "content" => res["text"],
        "logprob" => logprob
      }.to_json)
    rescue StandardError => e
      # Handle errors in logprob calculation
      @channel.push({
        "type" => "stt",
        "content" => res["text"]
      }.to_json)
    end
  end
  
  # Calculate log probability for transcription confidence
  # @param res [Hash] The transcription result
  # @param model [String] The model used
  # @return [Float, nil] The calculated log probability or nil on error
  def calculate_logprob(res, model)
    # Gemini models do not support logprobs for STT
    return nil if model.start_with?("gemini-")

    case model
    when "whisper-1"
      avg_logprobs = res["segments"].map { |s| s["avg_logprob"].to_f }
    else
      avg_logprobs = res["logprobs"].map { |s| s["logprob"].to_f }
    end

    # Calculate average and convert to probability
    Math.exp(avg_logprobs.sum / avg_logprobs.size).round(2)
  rescue StandardError
    nil
  end

  def websocket_handler(env)
    # Don't start EventMachine if it's already running
    if EventMachine.reactor_running?
      handle_websocket_connection(env)
    else
      EventMachine.run do
        handle_websocket_connection(env)
      end
    end
  end

  def handle_websocket_connection(env)
    queue = Queue.new
    thread = nil
    sid = nil

    # Create a new channel for each connection if it doesn't exist
    @channel ||= EventMachine::Channel.new

    # Share the channel with WebSocketHelper for progress broadcasting
    WebSocketHelper.set_channel(@channel)

    # Generate or retrieve session ID for this WebSocket connection
    ws_session_id = nil

    # Try to get session ID from cookies
    if env["HTTP_COOKIE"]
      cookies = Rack::Utils.parse_cookies(env)
      ws_session_id = cookies["_monadic_session_id"]
    end

    # If no session ID from cookies, try from the rack session if available
    ws_session_id ||= session[:websocket_session_id] if defined?(session) && session.is_a?(Hash)

    # Generate new session ID if none exists
    if ws_session_id.nil?
      ws_session_id = SecureRandom.uuid
      session[:websocket_session_id] = ws_session_id if defined?(session) && session.is_a?(Hash)
    end

    if CONFIG["EXTRA_LOGGING"]
      puts "[WebSocket] Using session ID: #{ws_session_id} for new connection"
    end

    ws = Faye::WebSocket.new(env, nil, { ping: 15 })
    ws.on :open do
      sid = @channel.subscribe { |obj| ws.send(obj) }
      # Add connection with session ID for progress broadcasting
      WebSocketHelper.add_connection_with_session(ws, ws_session_id)

      if CONFIG["EXTRA_LOGGING"]
        puts "[WebSocket] Connection opened for session #{ws_session_id}"
      end
    end

    ws.on :message do |event|
      # Websocket message logging removed for performance

      # Set session ID in Thread.current for downstream processes
      Thread.current[:websocket_session_id] = ws_session_id
      Thread.current[:rack_session] = session if defined?(session) && session.is_a?(Hash)

      begin
        obj = JSON.parse(event.data)
        # Normalize boolean values from JavaScript
        obj = BooleanParser.parse_hash(obj)
      rescue JSON::ParserError => e
        DebugHelper.debug("Invalid JSON in WebSocket message: #{event.data[0..100]}", "websocket", level: :error)
        @channel.push({ "type" => "error", "content" => "invalid_message_format" }.to_json)
        next
      end

      msg = obj["message"] || ""

      # Debug logging for all messages when EXTRA_LOGGING is enabled
      if CONFIG["EXTRA_LOGGING"] && msg == "UPDATE_LANGUAGE"
        extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
        extra_log.puts("[#{Time.now}] WebSocket received UPDATE_LANGUAGE message")
        extra_log.puts("  Full obj: #{obj.inspect}")
        extra_log.close
      end

      # Debug logging for research assistant apps
      if obj["app_name"] && (obj["app_name"].include?("Perplexity") || obj["app_name"].include?("DeepSeek"))
        puts "[DEBUG WebSocket] Received message type: #{msg.inspect}"
        puts "[DEBUG WebSocket] App name from obj: #{obj["app_name"]}"
      end

      case msg
      when "TTS"
          provider = obj["provider"]
          if provider == "elevenlabs" || provider == "elevenlabs-flash" || provider == "elevenlabs-multilingual" || provider == "elevenlabs-v3"
            voice = obj["elevenlabs_voice"]
          elsif provider == "gemini-flash" || provider == "gemini-pro"
            voice = obj["gemini_voice"]
          else
            voice = obj["voice"]
          end
          text = obj["text"]
          elevenlabs_voice = obj["elevenlabs_voice"]
          speed = obj["speed"]
          response_format = obj["response_format"]
          language = obj["conversation_language"] || "auto"
          
          # Special handling for Web Speech API
          if provider == "webspeech" || provider == "web-speech"
            # Create a special response for Web Speech API
            res_hash = { "type" => "web_speech", "content" => text }
          else
            # Generate TTS content for other providers
            puts "TTS: About to call tts_api_request with voice='#{voice}', provider='#{provider}'"
            res_hash = tts_api_request(text,
                                      provider: provider,
                                      voice: voice,
                                      speed: speed,
                                      response_format: response_format,
                                      language: language)
          end
          @channel.push(res_hash.to_json)
        when "TTS_STREAM"
          thread&.join
          provider = obj["provider"]
          if provider == "elevenlabs" || provider == "elevenlabs-flash" || provider == "elevenlabs-multilingual" || provider == "elevenlabs-v3"
            voice = obj["elevenlabs_voice"]
          elsif provider == "gemini-flash" || provider == "gemini-pro"
            voice = obj["gemini_voice"]
          else
            voice = obj["voice"]
          end
          text = obj["text"]
          elevenlabs_voice = obj["elevenlabs_voice"]
          speed = obj["speed"]
          response_format = obj["response_format"]
          language = obj["conversation_language"] || "auto"
          # model = obj["model"]
          
          
          # Special handling for Web Speech API
          if provider == "webspeech" || provider == "web-speech"
            # Create a special response for Web Speech API
            web_speech_response = { "type" => "web_speech", "content" => text }
            @channel.push(web_speech_response.to_json)
          else
            # Generate TTS content for other providers
            tts_api_request(text,
                            provider: provider,
                            voice: voice,
                            speed: speed,
                            response_format: response_format,
                            language: language) do |fragment|
              @channel.push(fragment.to_json)
          end
          end
        when "CANCEL"
          thread&.kill
          thread = nil
          queue.clear
          @channel.push({ "type" => "cancel" }.to_json)
        when "PDF_TITLES"
          ws.send({
            "type" => "pdf_titles",
            "content" => list_pdf_titles
          }.to_json)
        when "DELETE_PDF"
          title = obj["contents"]
          res = EMBEDDINGS_DB.delete_by_title(title)
          if res
            ws.send({ "type" => "pdf_deleted", "res" => "success", "content" => "#{title} deleted successfully" }.to_json)
            # Invalidate caches for mode/presence
            begin
              session[:pdf_cache_version] = (session[:pdf_cache_version] || 0) + 1
            rescue StandardError; end
          else
            ws.send({ "type" => "pdf_deleted", "res" => "failure", "content" => "Error deleting #{title}" }.to_json)
          end
        when "DELETE_ALL_PDFS"
          begin
            titles = EMBEDDINGS_DB.list_titles.map { |t| t[:title] }
            titles.each do |t|
              EMBEDDINGS_DB.delete_by_title(t)
            end
            ws.send({ "type" => "pdf_deleted", "res" => "success", "content" => "All local PDFs deleted" }.to_json)
            ws.send({ "type" => "pdf_titles", "content" => [] }.to_json)
            begin
              session[:pdf_cache_version] = (session[:pdf_cache_version] || 0) + 1
            rescue StandardError; end
          rescue StandardError => e
            ws.send({ "type" => "pdf_deleted", "res" => "failure", "content" => "Error clearing PDFs: #{e.message}" }.to_json)
          end
        when "CHECK_TOKEN"
          # Store ui_language in session parameters if provided
          if obj["ui_language"]
            session[:parameters] ||= {}
            session[:parameters]["ui_language"] = obj["ui_language"]
          end
          
          if CONFIG["ERROR"].to_s == "true"
            ws.send({ "type" => "error", "content" => "Error reading <code>~/monadic/config/env</code>" }.to_json)
          else
            token = CONFIG["OPENAI_API_KEY"]

            res = nil
            begin
              res = check_api_key(token) if token

              if token && res.is_a?(Hash) && res.key?("type")
                if res["type"] == "error"
                  ws.send({ "type" => "token_not_verified", "token" => "", "content" => "" }.to_json)
                else
                  ws.send({ "type" => "token_verified",
                            "token" => token, "content" => res["content"],
                            # "models" => res["models"],
                            "ai_user_initial_prompt" => MonadicApp::AI_USER_INITIAL_PROMPT }.to_json)
                end
              else
                ws.send({ "type" => "token_not_verified", "token" => "", "content" => "" }.to_json)
              end
            rescue StandardError => e
              ws.send({ "type" => "open_ai_api_error", "token" => "", "content" => "" }.to_json)
            end
          end
        when "PING"
          @channel.push({ "type" => "pong" }.to_json)
        when "RESET"
          session[:messages].clear
          session[:parameters].clear
          session[:error] = nil
          session[:obj] = nil
        when "LOAD"
          # Store ui_language in session parameters if provided
          if obj["ui_language"]
            session[:parameters] ||= {}
            session[:parameters]["ui_language"] = obj["ui_language"]
          end
          handle_load_message(ws)
        when "DELETE"
          handle_delete_message(ws, obj)
        when "EDIT"
          handle_edit_message(ws, obj)
        when "UPDATE_MCP_CONFIG"
          handle_mcp_config_update(ws, obj)
        when "AI_USER_QUERY"
          # Check if there are enough messages for AI User to work with
          if session[:messages].nil? || session[:messages].size < 2
            @channel.push({ 
              "type" => "error", 
              "content" => "ai_user_requires_conversation"
            }.to_json)
            next
          end
          
          thread&.join
          
          # Get parameters
          params = obj["contents"]["params"]
          
          # UI feedback
          @channel.push({ "type" => "wait", "content" => "generating_ai_user_response" }.to_json)
          @channel.push({ "type" => "ai_user_started" }.to_json)
          
          # Process the request
          begin
            # Get AI user response
            result = process_ai_user(session, params)
            
            # Handle result
            if result["type"] == "error"
              @channel.push({ "type" => "error", "content" => result["content"] }.to_json)
            else
              # Send response to client
              @channel.push({ "type" => "ai_user", "content" => result["content"] }.to_json)
              @channel.push({ "type" => "ai_user_finished", "content" => result["content"] }.to_json)
            end
          rescue => e
            # Error handling
            @channel.push({ "type" => "error", "content" => { "key" => "ai_user_error", "details" => e.message } }.to_json)
          end
        when "HTML"
          thread&.join
          until queue.empty?
            last_one = queue.shift
            begin
              content = last_one["choices"][0]

              # Always use message content - monadic apps will have JSON in content field
              text = content["text"] || content["message"]["content"]
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
                @channel.push({ "type" => "error", "content" => "api_stopped_safety" }.to_json)
              end

              # Extract ABC blocks before markdown processing (they're already HTML)
              abc_blocks = []
              text_for_markdown = text.gsub(/<div class="abc-code">.*?<\/div>/m) do |match|
                abc_blocks << match
                "\n\nABC_PLACEHOLDER_#{abc_blocks.size - 1}\n\n"
              end

              html = if session["parameters"]["monadic"]
                       APPS[session["parameters"]["app_name"]].monadic_html(text_for_markdown)
                     else
                       mathjax_enabled = session["parameters"]["mathjax"].to_s == "true"
                       markdown_to_html(text_for_markdown, mathjax: mathjax_enabled)
                     end

              # Restore ABC blocks after markdown processing
              abc_blocks.each_with_index do |block, index|
                # Remove <p> wrapper if present
                html.gsub!(/<p>\s*ABC_PLACEHOLDER_#{index}\s*<\/p>/, block)
                # Direct replacement as fallback
                html.gsub!("ABC_PLACEHOLDER_#{index}", block)
              end

              if session["parameters"]["response_suffix"]
                html += "\n\n" + session["parameters"]["response_suffix"]
              end
              
              # Add citation HTML back after markdown processing
              if citation_html
                html += citation_html
                if CONFIG["EXTRA_LOGGING"]
                  DebugHelper.debug("WebSocket: Added citation HTML to final output", category: :api, level: :info)
                end
              end

             new_data = { "mid" => SecureRandom.hex(4),
                          "role" => "assistant",
                          "text" => text,
                          "html" => html,
                          "lang" => detect_language(text),
                          "app_name" => session["parameters"]["app_name"],
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
              rescue
                provider_usage_enabled = false
              end

              if provider_usage_enabled
                usage = last_one["usage"] || last_one.dig("choices", 0, "usage")
                if usage && usage.is_a?(Hash)
                  tokens = usage["output_tokens"] || usage["completion_tokens"]
                  new_data["tokens"] = tokens.to_i if tokens
                end
              end

              @channel.push({
                "type" => "html",
                "content" => new_data
              }.to_json)

              session[:messages] << new_data
              # Filter messages by current app_name to prevent cross-app conversation leakage
    current_app_name = obj["app_name"] || session["parameters"]["app_name"]
    messages = session[:messages].filter { |m| m["type"] != "search" && m["app_name"] == current_app_name }
              past_messages_data = check_past_messages(session[:parameters])

              @channel.push({ "type" => "change_status", "content" => messages }.to_json) if past_messages_data[:changed]
              @channel.push({ "type" => "info", "content" => past_messages_data }.to_json)
            rescue StandardError => e
              STDERR.puts "Error processing request: #{e.message}"
              @channel.push({ "type" => "error", "content" => "something_went_wrong" }.to_json)
            end
          end
        when "SYSTEM_PROMPT"
          text = obj["content"] || ""
          
          # Initialize runtime settings for this session
          session[:runtime_settings] ||= {
            language: "auto",
            language_updated_at: nil
          }
          
          # Store conversation language preference in runtime settings (not in system prompt)
          conversation_language = obj["conversation_language"]
          session[:runtime_settings][:language] = conversation_language || "auto"
          
          if CONFIG["EXTRA_LOGGING"]
            extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
            extra_log.puts("[#{Time.now}] SYSTEM_PROMPT: Set language to #{session[:runtime_settings][:language]}")
            extra_log.puts("  Full runtime_settings: #{session[:runtime_settings].inspect}")
            extra_log.close
          end
          
          # Don't add language to the stored system prompt
          # It will be injected dynamically during API calls

          if obj["mathjax"]
            # the blank line at the beginning is important!
            text << <<~SYSPSUFFIX

            You use the MathJax notation to write mathematical expressions. In doing so, you should follow the format requirements: Use double dollar signs `$$` to enclose MathJax/LaTeX expressions that should be displayed as a separate block; Use single dollar signs `$` before and after the expressions that should appear inline with the text. Without these, the expressions will not render correctly. Either type of MathJax expression should be presntend without surrounding backticks.
              SYSPSUFFIX

            if obj["monadic"] || obj["jupyter"]
              # the blank line at the beginning is important!
              text << <<~SYSPSUFFIX

              Make sure to escape properly in the MathJax expressions.

                Good examples of inline MathJax expressions:
                - `$1 + 2 + 3 + … + k + (k + 1) = \\\\frac{k(k + 1)}{2} + (k + 1)$`
                - `$\\\\textbf{a} + \\\\textbf{b} = (a_1 + b_1, a_2 + b_2)$`
                - `$\\\\begin{align} 1 + 2 + … + k + (k+1) &= \\\\frac{k(k+1)}{2} + (k+1)\\\\end{align}$`
                - `$\\\\sin(\\\\theta) = \\\\frac{\\\\text{opposite}}{\\\\text{hypotenuse}}$`

              Good examples of block MathJax expressions:
                - `$$1 + 2 + 3 + … + k + (k + 1) = \\\\frac{k(k + 1)}{2} + (k + 1)$$`
                - `$$\\\\textbf{a} + \\\\textbf{b} = (a_1 + b_1, a_2 + b_2)$$`
                - `$$\\\\begin{align} 1 + 2 + … + k + (k+1) &= \\\\frac{k(k+1)}{2} + (k+1)\\\\end{align}$$`
                - `$$\\\\sin(\\\\theta) = \\\\frac{\\\\text{opposite}}{\\\\text{hypotenuse}}$$`
              SYSPSUFFIX
            else
              # the blank line at the beginning is important!
              text << <<~SYSPSUFFIX

              Good examples of inline MathJax expressions:
                - `$1 + 2 + 3 + … + k + (k + 1) = \frac{k(k + 1)}{2} + (k + 1)$`
                - `$\textbf{a} + \textbf{b} = (a_1 + b_1, a_2 + b_2)$`
                - `$\begin{align} 1 + 2 + … + k + (k+1) &= \frac{k(k+1)}{2} + (k+1)\end{align}$`
                - `$\sin(\theta) = \frac{\text{opposite}}{\text{hypotenuse}}$`

              Good examples of block MathJax expressions:
                - `$$1 + 2 + 3 + … + k + (k + 1) = \frac{k(k + 1)}{2} + (k + 1)$$`
                - `$$\textbf{a} + \textbf{b} = (a_1 + b_1, a_2 + b_2)$$`
                - `$$\begin{align} 1 + 2 + … + k + (k+1) &= \frac{k(k+1)}{2} + (k+1)\end{align}$$`
                - `$$\sin(\theta) = \frac{\text{opposite}}{\text{hypotenuse}}$$`

              Remember that the following are not available in MathJax:
                - `\begin{itemize}` and `\end{itemize}`
              SYSPSUFFIX
            end
          end

          new_data = { "mid" => SecureRandom.hex(4),
                       "role" => "system",
                       "text" => text,
                       "app_name" => session["parameters"]["app_name"],
                       "active" => true }
          # Initial prompt is added to messages but not shown as the first message
          # @channel.push({ "type" => "html", "content" => new_data }.to_json)
          session[:messages] << new_data

        when "SAMPLE"
          begin
            text = obj["content"]
            images = obj["images"]
            # Generate a unique message ID
            message_id = SecureRandom.hex(4)
            
            # Create message data
            new_data = {
              "mid" => message_id,
              "role" => obj["role"],
              "text" => text,
              "app_name" => session["parameters"]["app_name"],
              "active" => true
            }
            
            # Add images if present
            new_data["images"] = images if images
            
            # Format HTML content based on role
            if obj["role"] == "assistant"
              mathjax_enabled = session["parameters"]["mathjax"].to_s == "true"
              new_data["html"] = markdown_to_html(text, mathjax: mathjax_enabled)
            else
              # For user and system roles, preserve line breaks
              new_data["html"] = text
            end
            
            # First add to session
            session[:messages] << new_data
            
            # Force the system to send a properly formatted message that will be displayed
            if obj["role"] == "user"
              badge = "<span class='text-secondary'><i class='fas fa-face-smile'></i></span> <span class='fw-bold fs-6 user-color'>User</span>"
              html_content = "<p>" + text.gsub("<", "&lt;").gsub(">", "&gt;").gsub("\n", "<br>").gsub(/\s/, " ") + "</p>"
            elsif obj["role"] == "assistant"
              badge = "<span class='text-secondary'><i class='fas fa-robot'></i></span> <span class='fw-bold fs-6 assistant-color'>Assistant</span>"
              html_content = new_data["html"]
            else # system
              badge = "<span class='text-secondary'><i class='fas fa-bars'></i></span> <span class='fw-bold fs-6 system-color'>System</span>"
              html_content = new_data["html"]
            end
            
            # Send a dedicated message for immediate display
            @channel.push({ 
              "type" => "display_sample", 
              "content" => {
                "mid" => message_id,
                "role" => obj["role"],
                "html" => html_content,
                "badge" => badge
              }
            }.to_json)
            
            # Also send HTML message for session history
            @channel.push({ "type" => "html", "content" => new_data }.to_json)
            
            # Add a success response to confirm message was processed
            @channel.push({ "type" => "sample_success", "role" => obj["role"] }.to_json)
          rescue => e
            # Log the error
            puts "Error processing SAMPLE message: #{e.message}"
            puts e.backtrace
            
            # Inform the client
            @channel.push({ "type" => "error", "content" => "error_processing_sample" }.to_json)
          end
        when "AUDIO"
          handle_audio_message(ws, obj)
        when "UPDATE_LANGUAGE"
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
            
            if CONFIG["EXTRA_LOGGING"]
              puts "[DEBUG] UPDATE_LANGUAGE: Changed from #{old_language} to #{new_language}"
              puts "[DEBUG] Session runtime_settings after update: #{session[:runtime_settings].inspect}"
              
              # Log to file as well
              extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
              extra_log.puts("[#{Time.now}] UPDATE_LANGUAGE: #{old_language} -> #{new_language}")
              extra_log.puts("  Runtime settings: #{session[:runtime_settings].inspect}")
              extra_log.close
            end
            
            # Resend apps data with updated language descriptions
            apps_data = prepare_apps_data(new_language)
            @channel.push({ "type" => "apps", "content" => apps_data }.to_json) unless apps_data.empty?
            
            # Notify client of successful update
            language_name = if new_language == "auto"
                              "Automatic"
                            else
                              Monadic::Utils::LanguageConfig::LANGUAGES[new_language][:english]
                            end
            
            @channel.push({
              "type" => "language_updated",
              "language" => new_language,
              "language_name" => language_name,
              "text_direction" => Monadic::Utils::LanguageConfig.text_direction(new_language)
            }.to_json)
          end
        when "STOP_TTS"
          # Stop any running TTS thread and all prefetch threads
          if defined?(@tts_thread) && @tts_thread && @tts_thread.alive?
            # Kill all prefetch subthreads first
            begin
              tts_futures = @tts_thread[:tts_futures]
              if tts_futures && tts_futures.is_a?(Array)
                tts_futures.each do |future_thread|
                  future_thread.kill if future_thread && future_thread.alive?
                rescue => e
                  # Already dead or error during kill - safe to ignore
                end
              end
            rescue => e
              # Error accessing thread locals - continue with main thread cleanup
              puts "Error cleaning up TTS subthreads: #{e.message}" if CONFIG["EXTRA_LOGGING"]
            end

            # Kill main TTS thread
            @tts_thread.kill
            @tts_thread = nil
            puts "TTS thread and subthreads stopped by STOP_TTS message"
          end

          # Send confirmation
          @channel.push({
            "type" => "tts_stopped"
          }.to_json)
        when "PLAY_TTS"
          # Handle play TTS message
          # This is similar to auto_speech processing but for card playback

          # Stop any existing TTS thread first
          if defined?(@tts_thread) && @tts_thread && @tts_thread.alive?
            @tts_thread.kill
            @tts_thread = nil
          end

          thread&.join

          # Extract TTS parameters
          provider = obj["tts_provider"]
          if provider == "elevenlabs" || provider == "elevenlabs-flash" || provider == "elevenlabs-multilingual" || provider == "elevenlabs-v3"
            voice = obj["elevenlabs_tts_voice"]
          elsif provider == "gemini-flash" || provider == "gemini-pro"
            voice = obj["gemini_tts_voice"]
          else
            voice = obj["tts_voice"]
          end
          text = obj["text"]
          speed = obj["tts_speed"]
          response_format = "mp3"
          language = obj["conversation_language"] || "auto"

          # Use common TTS playback method
          start_tts_playback(
            text: text,
            provider: provider,
            voice: voice,
            speed: speed,
            response_format: response_format,
            language: language
          )
        else # fragment
          session[:parameters].merge! obj
          
          # Start background token counting for the user message immediately
          message_text = obj["message"].to_s
          if !message_text.empty?
            # Use o200k_base encoding for most LLMs
            token_count_thread = initialize_token_counting(message_text, "o200k_base")
            Thread.current[:token_count_thread] = token_count_thread
          end

          # Extract TTS parameters if auto_speech is enabled
          # Convert string "true" to boolean true for compatibility
          obj["auto_speech"] = true if obj["auto_speech"] == "true"

          # Get auto_tts_realtime_mode setting
          auto_tts_realtime_mode = obj["auto_tts_realtime_mode"]
          if auto_tts_realtime_mode.nil?
            auto_tts_realtime_mode = defined?(CONFIG) && CONFIG["AUTO_TTS_REALTIME_MODE"].to_s == "true"
          end

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
            model = "tts-1"
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

            app_name = obj["app_name"]
            app_obj = APPS[app_name]
            
            # Debug logging for troubleshooting
            if app_name && (app_name.include?("Perplexity") || app_name.include?("DeepSeek"))
              puts "[DEBUG WebSocket] Processing message for app: #{app_name}"
              puts "[DEBUG WebSocket] App object found: #{!app_obj.nil?}"
              puts "[DEBUG WebSocket] ChatPlusPerplexity exists: #{APPS.key?("ChatPlusPerplexity")}"
              puts "[DEBUG WebSocket] All Chat Plus apps: #{APPS.keys.select { |k| k.include?("ChatPlus") }}"
              puts "[DEBUG WebSocket] Total apps count: #{APPS.keys.length}"
            end
            
            unless app_obj
              error_msg = "App '#{app_name}' not found in APPS"
              puts "[ERROR] #{error_msg}"
              @channel.push({ "type" => "error", "content" => error_msg }.to_json)
              next
            end

            prev_texts_for_tts = []
            responses = app_obj.api_request("user", session) do |fragment|
              # DEBUG: Log all fragment arrivals
              if CONFIG["EXTRA_LOGGING"]
                File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
                  log.puts("[#{Time.now}] [DEBUG] Fragment arrived: type='#{fragment["type"]}', auto_speech=#{obj["auto_speech"]}, cutoff=#{cutoff}, monadic=#{obj["monadic"]}, auto_tts_realtime_mode=#{auto_tts_realtime_mode}")
                end
              end

              if fragment["type"] == "error"
                @channel.push({ "type" => "error", "content" => fragment }.to_json)
                break
              elsif fragment["type"] == "fragment"
                text = fragment["content"]
                buffer << text unless text.empty? || text == "DONE"

                ps = PragmaticSegmenter::Segmenter.new(text: buffer.join)
                segments = ps.segment

                if CONFIG["EXTRA_LOGGING"]
                  File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
                    log.puts("[#{Time.now}] [DEBUG] Fragment received: buffer_text='#{buffer.join[0..100]}...', segments=#{segments.size}")
                    segments.each_with_index do |seg, i|
                      log.puts("[#{Time.now}] [DEBUG]   segment[#{i}]: '#{seg[0..50]}...'")
                    end
                  end
                end

                # Wait for complete sentences: PragmaticSegmenter returns 2+ segments when a sentence is complete
                # Process all complete sentences (all except the last incomplete one)
                if !cutoff && segments.size >= 2
                  complete_sentences = segments[0...-1]

                  if auto_tts_realtime_mode
                    # REALTIME MODE: Use EventMachine async HTTP for non-blocking TTS processing
                    if CONFIG["EXTRA_LOGGING"]
                      File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
                        log.puts("[#{Time.now}] [DEBUG] REALTIME MODE ACTIVE: auto_speech=#{obj["auto_speech"]}, cutoff=#{cutoff}, monadic=#{obj["monadic"]}, segments=#{segments.size}")
                        log.puts("[#{Time.now}] [DEBUG] complete_sentences count: #{segments[0...-1].size}")
                      end
                    end

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

                        if CONFIG["EXTRA_LOGGING"]
                          File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
                            log.puts("[#{Time.now}] [BUFFER] ============================================")
                            log.puts("[#{Time.now}] [BUFFER] Sentence #{idx} received")
                            log.puts("[#{Time.now}] [BUFFER] Original text: '#{text}'")
                            log.puts("[#{Time.now}] [BUFFER] Cleaned text: '#{cleaned_text}'")
                            log.puts("[#{Time.now}] [BUFFER] Cleaned length: #{cleaned_text.length}")
                          end
                        end

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

                            if CONFIG["EXTRA_LOGGING"]
                              File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
                                log.puts("[#{Time.now}] [BUFFER] Decision: BUFFERING (≤#{REALTIME_TTS_MIN_LENGTH} chars)")
                                log.puts("[#{Time.now}] [BUFFER] Buffer size: #{@realtime_tts_short_buffer.size} sentence(s)")
                                log.puts("[#{Time.now}] [BUFFER] Total buffer length: #{total_buffer_length} chars")
                                log.puts("[#{Time.now}] [BUFFER] Buffer contents:")
                                @realtime_tts_short_buffer.each_with_index do |buf_text, buf_idx|
                                  log.puts("[#{Time.now}] [BUFFER]   [#{buf_idx}]: '#{buf_text}'")
                                end
                              end
                            end

                            # Check if total buffer length exceeds threshold
                            # This prevents long pauses while maintaining gap prevention
                            if total_buffer_length > REALTIME_TTS_MIN_LENGTH
                              # Flush buffer when accumulated length is sufficient
                              # Add space between sentences to prevent words from merging
                              combined_text = @realtime_tts_short_buffer.join(" ")
                              @realtime_tts_short_buffer.clear

                              if CONFIG["EXTRA_LOGGING"]
                                File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
                                  log.puts("[#{Time.now}] [BUFFER] *** FLUSHING BUFFER (total: #{total_buffer_length} > #{REALTIME_TTS_MIN_LENGTH}) ***")
                                  log.puts("[#{Time.now}] [BUFFER] Combined text to send to TTS: '#{combined_text}'")
                                  log.puts("[#{Time.now}] [BUFFER] Combined text length: #{combined_text.length}")
                                end
                              end

                              # Increment counters and create sequence ID
                              @realtime_tts_sequence_counter += 1
                              sequence_num = @realtime_tts_sequence_counter
                              sequence_id = "seq#{sequence_num}_#{Time.now.to_f}_#{SecureRandom.hex(2)}"

                              # Submit TTS request immediately
                              EventMachine.next_tick do
                                tts_api_request_em(
                                  combined_text,
                                  provider: provider,
                                  voice: voice,
                                  speed: speed,
                                  response_format: response_format,
                                  language: language,
                                  sequence_id: sequence_id
                                ) do |res_hash|
                                  if res_hash && res_hash["type"] != "error"
                                    if CONFIG["EXTRA_LOGGING"]
                                      File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
                                        log.puts("[#{Time.now}] [DEBUG] TTS async callback (flushed buffer): sequence_id=#{sequence_id}, type=#{res_hash["type"]}")
                                      end
                                    end
                                    @channel.push(res_hash.to_json)
                                  else
                                    if CONFIG["EXTRA_LOGGING"]
                                      File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
                                        log.puts("[#{Time.now}] [DEBUG] TTS failed for flushed buffer: #{res_hash&.[]("content")}")
                                      end
                                    end
                                  end
                                end
                              end
                            end
                          else
                            # This is a longer sentence - flush buffer and send combined text
                            if CONFIG["EXTRA_LOGGING"]
                              File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
                                log.puts("[#{Time.now}] [BUFFER] Decision: IMMEDIATE SEND (>#{REALTIME_TTS_MIN_LENGTH} chars)")
                                log.puts("[#{Time.now}] [BUFFER] Current buffer has #{@realtime_tts_short_buffer.size} sentence(s)")
                              end
                            end

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

                            if CONFIG["EXTRA_LOGGING"]
                              File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
                                log.puts("[#{Time.now}] [BUFFER] *** SENDING TO TTS (long sentence) ***")
                                log.puts("[#{Time.now}] [BUFFER] Sequence: #{sequence_num}, ID: #{sequence_id}")
                                log.puts("[#{Time.now}] [BUFFER] Combined text to send: '#{combined_text}'")
                                log.puts("[#{Time.now}] [BUFFER] Combined text length: #{combined_text.length}")
                              end
                            end

                            # Submit TTS request immediately
                            EventMachine.next_tick do
                              tts_api_request_em(
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
                                  if CONFIG["EXTRA_LOGGING"]
                                    File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
                                      log.puts("[#{Time.now}] [DEBUG] TTS async callback: sequence_id=#{sequence_id}, type=#{res_hash["type"]}")
                                    end
                                  end

                                  # Send audio to client
                                  @channel.push(res_hash.to_json)
                                else
                                  # TTS failed, just log it (fragment already sent)
                                  if CONFIG["EXTRA_LOGGING"]
                                    File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
                                      log.puts("[#{Time.now}] [DEBUG] TTS failed for segment: #{res_hash&.[]("content")}")
                                    end
                                  end
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
                    @channel.push(fragment.to_json)
                  else
                    # POST-COMPLETION MODE: Just send fragments, keep everything in buffer
                    @channel.push(fragment.to_json)
                  end
                else
                  # Just send the fragment without TTS processing
                  @channel.push(fragment.to_json)
                end
              else
                # Handle other fragment types
                @channel.push(fragment.to_json)
              end
              sleep 0.01
            end

            Thread.exit if !responses || responses.empty?

            # Process final segment for realtime mode
            # The last incomplete sentence in buffer needs to be processed after streaming completes
            if obj["auto_speech"] && !cutoff && !obj["monadic"] && auto_tts_realtime_mode
              # Get final text from buffer
              final_text = buffer.join.strip

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

                if CONFIG["EXTRA_LOGGING"]
                  File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
                    log.puts("[#{Time.now}] [DEBUG] REALTIME MODE: Flushing buffered short sentences into final segment")
                  end
                end
              end

              if final_text != ""
                if CONFIG["EXTRA_LOGGING"]
                  File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
                    log.puts("[#{Time.now}] [DEBUG] REALTIME MODE: Processing final segment: '#{final_text[0..50]}...' (length=#{final_text.length})")
                  end
                end

                # Generate unique sequence ID for final segment (use same format as streaming segments)
                # Counter should already be initialized by streaming loop above
                @realtime_tts_sequence_counter += 1
                sequence_num = @realtime_tts_sequence_counter
                sequence_id = "seq#{sequence_num}_#{Time.now.to_f}_#{SecureRandom.hex(2)}"

                # Call async TTS for final segment
                tts_api_request_em(
                  final_text,
                  provider: provider,
                  voice: voice,
                  speed: speed,
                  response_format: response_format,
                  language: language,
                  sequence_id: sequence_id
                ) do |res_hash|
                  if res_hash && res_hash["type"] != "error"
                    if CONFIG["EXTRA_LOGGING"]
                      File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
                        log.puts("[#{Time.now}] [DEBUG] TTS final segment callback: sequence_id=#{sequence_id}, type=#{res_hash["type"]}")
                      end
                    end
                    @channel.push(res_hash.to_json)
                  else
                    if CONFIG["EXTRA_LOGGING"]
                      File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
                        log.puts("[#{Time.now}] [DEBUG] TTS failed for final segment: #{res_hash&.[]("content")}")
                      end
                    end
                  end
                end
              end
            end

            # Post-completion TTS processing when realtime mode is FALSE
            # Convert string "true" to boolean true for compatibility
            obj["auto_speech"] = true if obj["auto_speech"] == "true"

            if obj["auto_speech"] && !cutoff && !obj["monadic"] && !auto_tts_realtime_mode
              # Stop any existing TTS thread first
              if defined?(@tts_thread) && @tts_thread && @tts_thread.alive?
                @tts_thread.kill
                @tts_thread = nil
              end

              # Get complete text from buffer
              text = buffer.join

              # Only process if there's actual text
              if text.strip != ""
                # Use common TTS playback method
                start_tts_playback(
                  text: text,
                  provider: provider,
                  voice: voice,
                  speed: speed,
                  response_format: response_format,
                  language: language
                )
              end
            end

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
                @channel.push({ "type" => "error", "content" => error_content }.to_json)
              else
                # Debug logging for response structure (only with EXTRA_LOGGING)
                if CONFIG["EXTRA_LOGGING"]
                  puts "WebSocket response structure:"
                  puts "Response class: #{response.class}"
                  puts "Response keys: #{response.keys.inspect}" if response.is_a?(Hash)
                  puts "Has choices?: #{response.key?("choices") if response.is_a?(Hash)}"
                  puts "Response: #{response.inspect[0..500]}..." # First 500 chars
                end
                
                # Check for content in standard format or responses API format
                raw_content = nil
                
                # Try standard format first
                raw_content = response.dig("choices", 0, "message", "content")
                
                # If not found, try responses API format
                if raw_content.nil? && response["output"]
                  if CONFIG["EXTRA_LOGGING"]
                    puts "Trying responses API format. Output items: #{response["output"].length}"
                  end
                  
                  # Look for message type in output array
                  response["output"].each do |item|
                    if CONFIG["EXTRA_LOGGING"]
                      puts "Output item type: #{item["type"]}, has content?: #{item.key?("content")}"
                    end
                    
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
                  
                  if CONFIG["EXTRA_LOGGING"]
                    puts "Extracted content length: #{raw_content&.length || 0}"
                  end
                end
                
                # If still no content found
                if raw_content.nil?
                  puts "ERROR: Content not found. Response structure: #{response.inspect[0..300]}..." if CONFIG["EXTRA_LOGGING"]
                  @channel.push({ "type" => "error", "content" => "content_not_found" }.to_json)
                  break
                end
                if raw_content
                  # Fix sandbox URL paths with a more precise regex that ensures we only replace complete paths
                  content = raw_content.gsub(%r{\bsandbox:/([^\s"'<>]+)}, '/\1')
                  # Fix mount paths in the same way
                  content = content.gsub(%r{^/mnt/([^\s"'<>]+)}, '/\1')
                else
                  content = ""
                  @channel.push({ "type" => "error", "content" => "empty_response" }.to_json)
                end

                response.dig("choices", 0, "message")["content"] = content

                if obj["auto_speech"] && obj["monadic"]
                  begin
                    parsed_content = JSON.parse(content)
                    message = parsed_content["message"]
                    
                    if message && !message.empty?
                      res_hash = tts_api_request(message,
                                                provider: provider,
                                                voice: voice,
                                                speed: speed,
                                                response_format: response_format)
                      @channel.push(res_hash.to_json) if res_hash
                    end
                  rescue JSON::ParserError => e
                    # Log the error but don't crash
                    puts "[TTS] Failed to parse monadic response for TTS: #{e.message}"
                  end
                end

                queue.push(response)
              end
            end
            
            # Send streaming complete message after all responses are processed
            @channel.push({ "type" => "streaming_complete" }.to_json)
          end
        end
      end

    ws.on :close do |event|
      # Remove connection with session ID from the list
      WebSocketHelper.remove_connection_with_session(ws, ws_session_id)

      if CONFIG["EXTRA_LOGGING"]
        puts "[WebSocket] Connection closed for session #{ws_session_id}"
      end

      # Clean up Thread.current
      Thread.current[:websocket_session_id] = nil
      Thread.current[:rack_session] = nil

      ws = nil
      @channel.unsubscribe(sid)
    end

    ws.rack_response
  end
  
  # Handle MCP configuration update
  def handle_mcp_config_update(ws, obj)
    # Update configuration
    CONFIG["MCP_SERVER_ENABLED"] = obj["enabled"] # Keep as boolean
    CONFIG["MCP_SERVER_PORT"] = obj["port"] if obj["port"]
    
    # Write updated config to file (optional - depends on persistence requirements)
    # This would require implementing a save_config method
    
    # Send updated MCP server status
    if defined?(Monadic::MCP::Server)
      mcp_status = Monadic::MCP::Server.status
      ws.send({ "type" => "mcp_status", "content" => mcp_status }.to_json)
    end
    
    ws.send({ "type" => "info", "content" => "MCP configuration updated" }.to_json)
  end
end
