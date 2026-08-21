# frozen_string_literal: true

require 'timeout'
require 'net/http'
require 'uri'
require 'async'
require 'async/queue'
require 'async/websocket/adapters/rack'
require 'twitter_cldr'
require_relative 'error_formatter'
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
require_relative 'websocket/audio_stream_handler'
require_relative 'websocket/pdf_handler'
require_relative 'websocket/library_handler'
require_relative 'websocket/streaming_handler'
require_relative 'websocket/html_handler'
require_relative 'websocket/misc_handlers'
require_relative 'websocket/privacy_handler'
require_relative 'websocket/verify_handler'
require_relative 'websocket/sts_stream_handler'

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
          handle_ws_pdf_titles(connection, obj, session)
        when "DELETE_PDF"
          handle_ws_delete_pdf(connection, obj, session)
        when "DELETE_ALL_PDFS"
          handle_ws_delete_all_pdfs(connection, obj, session)
        when "LIBRARY_LIST"
          handle_ws_library_list(connection, obj, session)
        when "LIBRARY_DELETE"
          handle_ws_library_delete(connection, obj, session)
        when "LIBRARY_STATS"
          handle_ws_library_stats(connection, obj, session)
        when "LIBRARY_SAVE"
          handle_ws_library_save(connection, obj, session)
        when "LIBRARY_SET_SCOPE"
          handle_ws_library_set_scope(connection, obj, session)
        when "LIBRARY_RENAME"
          handle_ws_library_rename(connection, obj, session)
        when "LIBRARY_GET_CONVERSATION"
          handle_ws_library_get_conversation(connection, obj, session)
        when "LIBRARY_RAG_TOGGLE"
          handle_ws_library_rag_toggle(connection, obj, session)
        when "LIBRARY_RAG_QUERY"
          handle_ws_library_rag_query(connection, obj, session)
        when "LIBRARY_SUGGEST_TITLE"
          handle_ws_library_suggest_title(connection, obj, session)
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
          # LOAD re-derives the UI from the canon; a live STS bridge across
          # that is incoherent (and its merge span may predate the reload).
          # Every legitimate LOAD sender has already ended the conversation
          # client-side, so this is a no-op there — it exists for the import
          # / stray-tab paths (review round 4, P1).
          teardown_sts_session(session)
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
        when "AUDIO_CHUNK"
          route_audio_event(connection, session, obj,
                            sts_handler: :handle_sts_audio_chunk,
                            fallback: :handle_audio_chunk)
        when "AUDIO_COMMIT"
          route_audio_event(connection, session, obj,
                            sts_handler: :handle_sts_audio_commit,
                            fallback: :handle_audio_commit)
        when "AUDIO_ABORT"
          route_audio_event(connection, session, obj,
                            sts_handler: :handle_sts_audio_abort,
                            fallback: :handle_audio_abort)
        when "STS_START"
          # Live Conversation session start (greet flag decides whether the
          # assistant opens the conversation). Same gates as the audio path.
          route_sts_control(connection, session, obj, handler: :handle_sts_start)
        when "STS_STOP"
          # Explicit stop: finalize the in-flight turn and tear the bridge
          # down. No capability gate — stopping must always work, and it is
          # a no-op when no bridge exists.
          handle_sts_stop(connection, obj)
        when "STS_INITIATE"
          # Legacy alias for STS_START with greet (kept honored).
          route_sts_control(connection, session, obj, handler: :handle_sts_initiate)
        when "UPDATE_LANGUAGE"
          handle_ws_update_language(connection, obj, session)
        when "STOP_TTS"
          handle_ws_stop_tts(connection, obj, session)
        when "PLAY_TTS"
          handle_ws_play_tts(connection, obj, session, thread)
        when "PRIVACY_REGISTRY"
          handle_ws_privacy_registry(connection, session)
        when "PRIVACY_EXPORT"
          handle_ws_privacy_export(connection, session, obj)
        when "PRIVACY_TOGGLE"
          handle_ws_privacy_toggle(connection, session, obj)
        when "VERIFY_CONFIDENCE"
          handle_ws_verify_confidence(connection, obj, session)
        else # fragment
          thread = handle_ws_streaming(connection, obj, session, queue)
        end
      end # end case
    end # end while

    rescue StandardError => e
      Monadic::Utils::ExtraLogger.log { "[WebSocket] Error in message loop: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}" }
    ensure
      # Tear down any live STS bridge so the upstream OpenAI socket does not
      # outlive the client connection (the STT bridge dies with its writer;
      # the STS bridge is long-lived by design, so it needs an explicit stop).
      teardown_sts_session(session) if session

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

  # The ONE way to deliver an error to the client. Provider error text carries
  # account identifiers (xAI names the team UUID, Google the project number,
  # OpenAI the organization), and an error shown in the chat is saved with the
  # conversation and travels with any export — so the identifiers are scrubbed
  # here, once, instead of at every call site. The untouched text still goes to
  # the EXTRA_LOGGING trace, which stays on the user's own machine.
  #
  # Building `{"type" => "error"}` inline elsewhere bypasses this and is pinned
  # against by spec/unit/utils/websocket/error_send_boundary_spec.rb.
  # content is usually a message string, but some callers send a structured
  # payload (an i18n key plus details), so scrubbing walks strings wherever
  # they sit rather than stringifying the whole thing.
  def send_error(content, session_id = Thread.current[:websocket_session_id], extra = {})
    scrubbed = scrub_error_content(content)
    if scrubbed != content
      Monadic::Utils::ExtraLogger.log { "[WebSocket] error text scrubbed before delivery; raw: #{content.inspect}" }
    end
    payload = { "type" => "error", "content" => scrubbed }.merge(extra)
    send_or_broadcast(payload.to_json, session_id)
  end

  def scrub_error_content(content)
    case content
    when String then Monadic::Utils::ErrorFormatter.scrub_identifiers(content)
    when Hash then content.transform_values { |v| scrub_error_content(v) }
    when Array then content.map { |v| scrub_error_content(v) }
    else content
    end
  end

  # The pre-session delivery path (no session id yet). Error payloads get the
  # same scrubbing as send_error — this is the second and last way an error
  # reaches the client, so both are covered without touching call sites.
  def send_to_client(connection, message_hash)
    if message_hash.is_a?(Hash) && message_hash["type"] == "error"
      message_hash = message_hash.merge("content" => scrub_error_content(message_hash["content"]))
    end
    connection.write(message_hash.to_json)
    connection.flush
  rescue StandardError => e
    Monadic::Utils::ExtraLogger.log { "[WebSocket] Error sending to client: #{e.message}" }
  end

  # --- STS (speech-to-speech) audio routing ---------------------------------

  # Route one inbound audio control message (AUDIO_CHUNK / AUDIO_COMMIT /
  # AUDIO_ABORT) to either the STS bridge or the legacy realtime-STT
  # handlers, based on route_audio_mode.
  private def route_audio_event(connection, session, obj, sts_handler:, fallback:)
    case route_audio_mode(session, obj)
    when :sts
      send(sts_handler, connection, obj)
    when :privacy_blocked
      notify_sts_privacy_blocked(connection, session)
    else
      send(fallback, connection, obj)
    end
  end

  # Route an STS control message (STS_START / STS_INITIATE). Same capability
  # + privacy gates as the audio path; silently ignored outside STS sessions
  # (a stray client should not crash anything).
  private def route_sts_control(connection, session, obj, handler:)
    unless sts_session_capable?(session, obj)
      Monadic::Utils::ExtraLogger.log do
        "[WebSocket] #{obj['message']} ignored (session is not STS-capable)"
      end
      return
    end

    if sts_privacy_active?(session)
      notify_sts_privacy_blocked(connection, session)
    else
      send(handler, connection, obj)
    end
  end

  # Decide where inbound voice audio goes for this session. Shared by all
  # three audio dispatch branches.
  #
  # Returns one of:
  #   :sts             — current model has the supports_speech_to_speech
  #                      capability; audio goes to the STS bridge
  #   :privacy_blocked — model is STS-capable but the Privacy Filter is on;
  #                      raw audio must not be sent to the provider
  #   :stt             — default realtime-STT transcription path
  # `obj` (the inbound audio message) may carry a `chat_model` routing hint.
  # Deciding from session parameters alone races the client's UPDATE_PARAMS
  # broadcast, which is dropped silently while the socket is not OPEN or a
  # suppression window is active — the hint makes the decision input
  # deterministic. The hint is still capability-checked against model_spec,
  # so a client cannot switch pipelines with an arbitrary value.
  private def route_audio_mode(session, obj = nil)
    return :stt unless sts_session_capable?(session, obj)

    sts_privacy_active?(session) ? :privacy_blocked : :sts
  end

  # Privacy Filter "currently enabled" check for STS routing. Mirrors the
  # two-gate activation in BaseVendorHelper#privacy_enabled_for?: the app
  # must declare `privacy do; enabled true; end` in MDSL AND the user must
  # have opted in via the session toggle (PRIVACY_TOGGLE sets
  # session[:_privacy_session_enabled] only after a container health probe,
  # so the key alone is backend-authoritative for the toggle half).
  private def sts_privacy_active?(session)
    return false unless session.respond_to?(:[])
    return false unless session[:_privacy_session_enabled] == true

    params = session[:parameters] || session["parameters"]
    params = {} unless params.respond_to?(:[])
    app_name = params["app_name"] || params[:app_name]
    app_settings = (defined?(APPS) && app_name && APPS[app_name]) ? APPS[app_name].settings : nil
    return false unless app_settings

    privacy = app_settings[:privacy] || app_settings["privacy"]
    return false unless privacy

    (privacy[:enabled] || privacy["enabled"]) == true
  end

  # Notify the user that STS is unavailable while the Privacy Filter is on.
  # Sent only once per session (tracked via :_sts_privacy_notice_sent) so a
  # stream of AUDIO_CHUNKs does not spam one error per chunk.
  private def notify_sts_privacy_blocked(connection, session)
    return if session[:_sts_privacy_notice_sent]

    session[:_sts_privacy_notice_sent] = true
    send_to_client(connection, {
      "type" => "error",
      "content" => "Speech-to-speech mode sends raw audio directly to the provider " \
                   "and is unavailable while the Privacy Filter is on. " \
                   "Disable the Privacy Filter or choose a model without " \
                   "speech-to-speech support to use voice input."
    })
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
