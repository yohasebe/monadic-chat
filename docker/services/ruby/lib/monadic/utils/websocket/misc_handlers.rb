# frozen_string_literal: true

# Miscellaneous WebSocket message handlers.
# Handles: CHECK_TOKEN, AI_USER_QUERY, UPDATE_PARAMS, SYSTEM_PROMPT,
# SAMPLE, UPDATE_LANGUAGE, and RESET messages.

module WebSocketHelper
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
            # The key itself never goes to the page, whole or in part.
            send_to_client(connection, { "type" => "token_verified",
                      "content" => res["content"],
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

    # Keys left unset because 1Password could not be read (locked when the
    # server started, for one): the page says which, by name only.
    unresolved = Monadic::Utils::SecretReferences.unresolved_at_load
    send_to_client(connection, { "type" => "secret_references_unresolved", "keys" => unresolved }) unless unresolved.empty?
  end

  # The suggestion is written in a thread of its own, returned to the read
  # loop: Reset and Cancel stop it as they stop a reply (run in the loop, it
  # held both back until it was done), and nothing in the loop waits for it.
  # Every notice carries the request id the page sent, errors included, so
  # the page can tell a suggestion it has given up from the one it awaits.
  # A request while another suggestion is being written is refused.
  private def handle_ws_ai_user_query(connection, obj, session, reply, suggestion = nil)
    # Get session ID for targeted broadcasting
    ws_session_id = Thread.current[:websocket_session_id]
    request_id = obj.dig("contents", "request_id")
    notice = ->(fields) { send_or_broadcast(fields.merge("request_id" => request_id).to_json, ws_session_id) }

    # Check if there are enough messages for AI User to work with
    if session[:messages].nil? || session[:messages].size < 2
      notice.call("type" => "ai_user_error", "content" => "ai_user_requires_conversation")
      return nil
    end
    if suggestion&.alive?
      notice.call("type" => "ai_user_error", "content" => "ai_user_busy")
      return nil
    end

    params = obj["contents"]["params"]
    rack_session = Thread.current[:rack_session]

    Thread.new do
      Thread.current[:websocket_session_id] = ws_session_id
      Thread.current[:rack_session] = rack_session
      # A reply still being written comes first (waited for here, not in the
      # read loop, so a Reset or Cancel meanwhile is still taken).
      reply&.join
      write_ai_user_suggestion(session, params, notice)
    end
  end

  private def write_ai_user_suggestion(session, params, notice)
    notice.call("type" => "ai_user_started")

    # The chat this suggestion is for: after a Reset or app switch it would
    # land in the next chat's input box, so nothing is sent.
    chat_at_start = session[Monadic::Workspace::Chats::SESSION_KEY]

    result = process_ai_user(session, params)
    if session[Monadic::Workspace::Chats::SESSION_KEY] != chat_at_start
      nil
    elsif result["type"] == "error"
      notice.call("type" => "ai_user_error", "content" => result["content"].to_s)
    else
      notice.call("type" => "ai_user", "content" => result["content"])
      notice.call("type" => "ai_user_finished", "content" => result["content"])
    end
  rescue StandardError => e
    notice.call("type" => "ai_user_error", "content" => "AI User error: #{e.message}")
  end

  # Whether UPDATE_PARAMS moves the tab to another app (a new chat).
  private def app_change?(obj, session)
    incoming = obj["params"]
    return false unless incoming.is_a?(Hash) && session[:parameters].is_a?(Hash)

    current_app = session[:parameters]["app_name"]
    new_app = incoming["app_name"]&.to_s
    !!(new_app && current_app && new_app != current_app)
  end

  # A conversation read from a file (POST /load staged it for this tab)
  # replaces the tab's chat. The reply and suggestion were stopped by the
  # caller; speech is stopped here, then the chat starts anew with the
  # imported one in it, and the page is sent what it shows.
  private def handle_ws_import_apply(connection, obj, session, imported)
    ws_session_id = Thread.current[:websocket_session_id]
    token = obj["token"].to_s
    unless imported
      send_to_client(connection, { "type" => "import_result", "token" => token, "success" => false,
                                   "error" => "The conversation to import was not found. Please import the file again." })
      return
    end

    stop_speech_for_new_chat(connection, session, "Import")

    # The page's language belongs to the tab, not to the file.
    ui_language = session[:parameters] && session[:parameters]["ui_language"]
    session[:messages].clear
    session[:parameters].clear
    Monadic::Workspace::Chats.begin_new!(session)
    imported.each { |key, value| session[key] = value }
    session[:parameters]["ui_language"] ||= ui_language if ui_language
    sync_session_state!

    send_chat_to_page(connection, session)
    send_to_client(connection, { "type" => "import_result", "token" => token, "success" => true })
    Monadic::Utils::ExtraLogger.log { "[Import] Tab #{ws_session_id} took #{session[:messages].size} messages" }
  rescue StandardError => e
    send_to_client(connection, { "type" => "import_result", "token" => token, "success" => false,
                                 "error" => "The import could not be finished: #{e.message}" })
    Monadic::Utils::ExtraLogger.log { "[Import] Failed: #{e.class}: #{e.message}" }
  end

  # Speech of the chat being replaced (Live Conversation, reading aloud,
  # dictation) stops before another chat is put in its place.
  private def stop_speech_for_new_chat(connection, session, reason)
    if session[:_sts]
      teardown_sts_session(session)
      send_to_client(connection, { "type" => "sts_session", "state" => "stopped" })
    end
    send_to_client(connection, { "type" => "cancel" }) if respond_to?(:stop_tts_threads, true) && stop_tts_threads(reason)
    handle_audio_abort(nil, nil) if session[:_realtime_stt] && respond_to?(:handle_audio_abort, true)
  end

  # What the page shows of the chat now in the session (an imported or a
  # resumed one), in the order it applies them; the pauses let it build the
  # app list before the parameters select from it. A resumed chat is shown
  # with its Privacy Filter state locked, as after a reload, so the page
  # does not turn the filter on for it as it does for a new chat.
  private def send_chat_to_page(connection, session, restored: false)
    apps_data = prepare_apps_data(session[:parameters]["ui_language"], session: session)
    app_name = session[:parameters]["app_name"]
    shown = session[:messages].filter { |m| m["type"] != "search" && m["app_name"] == app_name }
    send_to_client(connection, { "type" => "apps", "content" => apps_data, "version" => session[:version], "docker" => session[:docker], "from_import" => true }) unless apps_data.empty?
    sleep(0.2)
    send_to_client(connection, { "type" => "parameters", "content" => session[:parameters], "from_import" => true }) unless session[:parameters].empty?
    sleep(0.05)
    send_to_client(connection, { "type" => "past_messages", "content" => shown, "from_import" => true })

    state = session[:monadic_state]
    if state && state[:conversation_context]
      send_to_client(connection, { "type" => "context_update", "context" => state[:conversation_context],
                                   "schema" => state[:context_schema], "from_import" => true })
    end
    registry = state && state[:privacy] && state[:privacy][:registry]
    privacy = { "type" => "privacy_state", "enabled" => session[:_privacy_session_enabled] == true,
                "registry_count" => registry.is_a?(Hash) ? registry.size : 0, "error" => nil,
                "private" => Monadic::History::Policy.private?(session) }
    privacy["restored"] = true if restored
    send_to_client(connection, privacy)
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
      # Switching apps starts a new chat, even when nothing was sent yet
      # (the client sends RESET only when there are messages). What the
      # previous app's chat left in the session is dropped with it: the
      # Session Context, the privacy registry, pipelines memoized for that
      # app, the toggle (the frontend re-negotiates it via PRIVACY_TOGGLE),
      # and tool results such as the last image or notebook. The messages go
      # too (the page clears them when the app changes): the new chat must
      # not start with the previous one's words, Private or not.
      session[:messages] = []
      Monadic::Workspace::Chats.begin_new!(session)
      # Push a privacy_state event so the frontend indicator reflects the
      # cleared registry immediately, instead of staying at the previous
      # app's count until the user sends the first message.
      ws_session_id = Thread.current[:websocket_session_id]
      privacy_state_msg = {
        "type" => "privacy_state",
        "enabled" => false,
        "registry_count" => 0,
        "error" => nil,
        "private" => false
      }.to_json
      if ws_session_id
        WebSocketHelper.send_to_session(privacy_state_msg, ws_session_id)
      end
      Monadic::Utils::ExtraLogger.log { "[WebSocket] App changed from #{current_app} to #{new_app} - context + privacy reset" }
    end

    # On-demand container startup: when the user selects an app that needs
    # Python / Selenium / Privacy, make sure the target container is running
    # before they send their first message. (Qdrant + embeddings are base
    # services and start with the app.) Modern UI flows select apps entirely
    # via WebSocket (UPDATE_PARAMS), so the HTTP redirect route is never
    # hit. The helper is idempotent and runs in a background thread so the
    # parameter broadcast is not delayed by docker compose latency.
    if new_app && new_app != current_app
      Monadic::Utils::ContainerDependencies.ensure_services_async(new_app, reason: "UPDATE_PARAMS")
    end

    sanitized = {}
    incoming.each do |key, value|
      next if key.nil?
      normalized_key = key.to_s
      next if ["message", "images", "audio", "tts_request", "ws_session_id"].include?(normalized_key)
      sanitized[normalized_key] = value
    end

    sanitized["app_name"] = sanitized["app_name"].to_s if sanitized.key?("app_name")

    # STS bridge lifecycle: the bridge pins model/voice/instructions at
    # creation time, so a change in any of them (or leaving the STS model
    # entirely) must tear it down. Otherwise the old bridge keeps its
    # upstream socket and semaphore slot until the WebSocket closes
    # (STS_MAX_CONCURRENT tabs would exhaust the cap). The bridge is
    # rebuilt lazily on the next AUDIO_CHUNK with the new params.
    sts_bridge_stale =
      (new_app && current_app && new_app != current_app) ||
      (sanitized.key?("model") && session[:parameters]["model"] != sanitized["model"]) ||
      (sanitized.key?("tts_voice") && session[:parameters]["tts_voice"] != sanitized["tts_voice"])

    session[:parameters].merge!(sanitized)

    if sts_bridge_stale && session[:_sts]
      Monadic::Utils::ExtraLogger.log do
        "[WebSocket] Params changed (app/model/voice) - tearing down STS bridge " \
        "(rebuilt on next audio input)"
      end
      teardown_sts_session(session)
    end

    sync_session_state!

    # Get session ID for targeted broadcasting
    ws_session_id = Thread.current[:websocket_session_id]

    begin
      param_message = {
        "type" => "parameters",
        "content" => session[:parameters],
        "from_param_update" => true
      }.to_json
      send_or_broadcast(param_message, ws_session_id)
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
    # Note: Math rendering prompts are now handled by SystemPromptInjector

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

      # Words marked for the Privacy Filter are taken out and kept for the
      # chat, as for a sent message; nothing is added if that fails.
      if text.is_a?(String)
        if obj["role"] == "system" && marked_words_in_system_text?(text, session)
          send_error(SYSTEM_TEXT_MARKED, ws_session_id, { "not_accepted" => true })
          return
        end
        text = take_privacy_marks(text, session, ws_session_id)
        return if text.nil?
      end

      # Attachments go only with a user message, checked as for a sent
      # one; the answers to later messages of this chat may then use them.
      attachment_refs = nil
      if obj.key?("attachments") && !Array(obj["attachments"]).empty?
        unless obj["role"] == "user"
          send_error("Files can be attached only to a user message.", ws_session_id, { "not_accepted" => true })
          return
        end
        begin
          attachment_refs = Monadic::Workspace::Attachments.refs_for_message!(
            chat_id: session[Monadic::Workspace::Chats::SESSION_KEY], refs: obj["attachments"]
          )
        rescue Monadic::Workspace::Attachments::Unusable => e
          send_error(e.message, ws_session_id, { "not_accepted" => true })
          return
        end
      end

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
      # A user sample is recorded like a sent message: with a request of its
      # own and the snapshot of what it was sent with.
      if obj["role"] == "user"
        new_data.merge!(user_turn_fields(request_id: Monadic::Workspace::Ids.generate(:request),
                                         chat_id: session[Monadic::Workspace::Chats::SESSION_KEY],
                                         app_name: params["app_name"], attachment_refs: attachment_refs))
      end

      # First add to session
      session[:messages] << new_data
      sync_session_state!

      if obj["role"] == "user" && text.is_a?(String) && !text.empty?
        require_relative '../privacy/language_detector'
        Monadic::Utils::Privacy::LanguageDetector.detect_and_lock!(text, session)
      end

      # Send text content; the client handles rendering. The display_sample
      # message carries both text and role info.
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
          "badge" => badge,
          "attachments" => new_data["attachments"]
        }.compact
      }.to_json
      send_or_broadcast(display_message, ws_session_id)

      # Also send HTML message for session history
      html_message = { "type" => "html", "content" => new_data }.to_json
      send_or_broadcast(html_message, ws_session_id)

      # Add a success response to confirm message was processed
      success_message = { "type" => "sample_success", "role" => obj["role"] }.to_json
      send_or_broadcast(success_message, ws_session_id)
    rescue StandardError => e
      # Log the error
      puts "Error processing SAMPLE message: #{e.message}"
      puts e.backtrace

      # Inform the client
      send_error("error_processing_sample", ws_session_id)
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
        send_or_broadcast(apps_message, ws_session_id)
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
      send_or_broadcast(language_updated_message, ws_session_id)
    end
  end

  # Seconds for a stopped reply's own clean-up: stopping a command it runs
  # (Monadic::Shell::STOP_TIMEOUT plus the group's grace) fits within it.
  REPLY_STOP_WAIT = 15

  # Stops a reply that is still being written, waits briefly for its clean-up
  # (closing connections, stopping commands it started) and drops what it
  # queued. The page gets the same notice as for Cancel, which gives it its
  # controls back without touching the input box.
  private def stop_running_reply(thread, queue)
    queue&.clear
    return unless thread&.alive?

    thread.kill
    thread.join(REPLY_STOP_WAIT)
    queue&.clear
    send_or_broadcast({ "type" => "cancel" }.to_json, Thread.current[:websocket_session_id])
  end

  private def handle_ws_reset(session)
    # A live speech-to-speech bridge must not survive Reset: it would keep
    # the upstream socket (and billing) alive against a cleared canon, and
    # keep speaking into a conversation that no longer exists.
    if session[:_sts]
      teardown_sts_session(session)
      send_or_broadcast({ "type" => "sts_session", "state" => "stopped" }.to_json,
                        Thread.current[:websocket_session_id])
    end
    # Speech still being made for the old chat is stopped, not played into the
    # new one; the page gets the Cancel notice so its indicator does not stay on.
    if respond_to?(:stop_tts_threads, true) && stop_tts_threads("Reset")
      send_or_broadcast({ "type" => "cancel" }.to_json, Thread.current[:websocket_session_id])
    end
    # Dictation still being transcribed belongs to the old chat's input.
    handle_audio_abort(nil, nil) if session[:_realtime_stt] && respond_to?(:handle_audio_abort, true)
    session[:messages].clear
    session[:parameters].clear
    # Reset starts a new chat: what the previous chat left in the session
    # (tool results such as the last image, the Session Context, the privacy
    # registry and toggle, cached pipelines) is dropped, and files made from
    # now on go to a new folder while the previous chat's folder stays.
    Monadic::Workspace::Chats.begin_new!(session)
    sync_session_state!
    # The Privacy Filter is off for the new chat until the page turns it on
    # again; tell the page, so its indicator does not keep showing the old
    # chat's ON (the page turns it back on itself when its toggle is on).
    send_or_broadcast({ "type" => "privacy_state", "enabled" => false, "registry_count" => 0, "error" => nil,
                        "private" => false }.to_json,
                      Thread.current[:websocket_session_id])
  end
end
