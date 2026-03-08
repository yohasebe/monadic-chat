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
require_relative 'websocket/streaming_handler'
require_relative 'websocket/html_handler'
require_relative 'websocket/misc_handlers'

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

    rescue StandardError => e
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

  # Send a JSON message to a specific session, or broadcast to all if no session ID.
  # This centralizes the common pattern of session-targeted vs global delivery.
  def send_or_broadcast(message, session_id = Thread.current[:websocket_session_id])
    if session_id
      WebSocketHelper.send_to_session(message, session_id)
    else
      WebSocketHelper.broadcast_to_all(message)
    end
  end

  def send_to_client(connection, message_hash)
    connection.write(message_hash.to_json)
    connection.flush
  rescue StandardError => e
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
