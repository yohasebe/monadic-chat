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
      send_or_broadcast(error_msg, ws_session_id)
      return
    end

    thread&.join

    # Get parameters
    params = obj["contents"]["params"]

    # UI feedback
    wait_msg = { "type" => "wait", "content" => "generating_ai_user_response" }.to_json
    send_or_broadcast(wait_msg, ws_session_id)

    started_msg = { "type" => "ai_user_started" }.to_json
    send_or_broadcast(started_msg, ws_session_id)

    # Process the request
    begin
      # Get AI user response
      result = process_ai_user(session, params)

      # Handle result
      if result["type"] == "error"
        error_result = { "type" => "error", "content" => result["content"] }.to_json
        send_or_broadcast(error_result, ws_session_id)
      else
        # Send response to client
        ai_user_msg = { "type" => "ai_user", "content" => result["content"] }.to_json
        send_or_broadcast(ai_user_msg, ws_session_id)

        finished_msg = { "type" => "ai_user_finished", "content" => result["content"] }.to_json
        send_or_broadcast(finished_msg, ws_session_id)
      end
    rescue StandardError => e
      # Error handling
      rescue_error = { "type" => "error", "content" => { "key" => "ai_user_error", "details" => e.message } }.to_json
      send_or_broadcast(rescue_error, ws_session_id)
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

    # On-demand container startup: when the user selects an app that needs
    # Python / Selenium / PGVector, make sure the target container is running
    # before they send their first message. This is the WebSocket-path
    # equivalent of the HTTP redirect at monadic.rb#/:endpoint, which modern
    # UI flows never hit because app selection is WebSocket-only. The helper
    # is idempotent (checks running state before starting) so we can fire it
    # on every app change cheaply. Runs in a background thread so the
    # parameter broadcast is not delayed by docker compose startup latency.
    if new_app && defined?(APPS) && APPS[new_app] && new_app != current_app
      target_settings = APPS[new_app].settings
      Thread.new do
        Monadic::Utils::ContainerDependencies.ensure_services_for_app(target_settings)
      rescue StandardError => e
        Monadic::Utils::ExtraLogger.log { "[ContainerDeps] on app change: #{e.message}" }
      end
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
      error_message = { "type" => "error", "content" => "error_processing_sample" }.to_json
      send_or_broadcast(error_message, ws_session_id)
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
end
