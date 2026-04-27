# frozen_string_literal: false

# Session state management routes
# Export/import conversation state and session data

# Convert a Privacy Filter export (encrypted/masked_only/restored) into the
# standard { parameters, messages } shape that the rest of /load expects.
#
# The header is intentionally compact (only app_name + counts), so we look
# up the app's actual settings via APPS[app_name] to populate model/
# initial_prompt/etc. This keeps export files small while preserving the
# UI invariants that the chat header expects after import.
PRIVACY_SYNTH_APP_KEYS = %w[
  model models temperature max_tokens initial_prompt display_name icon
  group provider reasoning_effort tools description
].freeze

def privacy_synthesize_session(header, body, mode)
  header ||= {}
  app_name = header["app_name"] || "Chat"
  messages = body["messages"] || []

  # Prefer parameters embedded in the body (newer rich exports preserve the
  # full session state). Fall back to rebuilding from APPS when the body has
  # no parameters (legacy 3-mode privacy exports).
  body_params = body["parameters"]
  parameters = if body_params.is_a?(Hash) && !body_params.empty?
                 body_params.dup
               else
                 base = { "app_name" => app_name }
                 if defined?(APPS) && APPS[app_name]
                   app_settings = APPS[app_name].settings
                   PRIVACY_SYNTH_APP_KEYS.each do |key|
                     value = app_settings[key] || app_settings[key.to_sym]
                     base[key] = value unless value.nil?
                   end
                 end
                 base["monadic"] = false unless base.key?("monadic")
                 base
               end
  parameters["app_name"] ||= app_name
  parameters["imported_from"] = "privacy_export"
  parameters["imported_mode"] = mode

  result = {
    "parameters" => parameters,
    "messages" => messages
  }
  result["monadic_state"] = body["monadic_state"] if body["monadic_state"].is_a?(Hash)
  result
end

# Get monadic_state for export (Session State mechanism)
get "/monadic_state" do
  content_type :json
  if session[:monadic_state]
    # Convert symbol keys to strings for JSON serialization
    serializable_state = session[:monadic_state].each_with_object({}) do |(app_key, app_data), result|
      # Skip special keys that don't follow the standard structure
      next if [:conversation_context, :context_schema, "conversation_context", "context_schema"].include?(app_key)

      if app_data.is_a?(Hash)
        result[app_key.to_s] = app_data.each_with_object({}) do |(state_key, state_entry), app_result|
          next unless state_entry.is_a?(Hash) && state_entry.key?(:data)
          app_result[state_key.to_s] = {
            "data" => state_entry[:data],
            "version" => state_entry[:version],
            "updated_at" => state_entry[:updated_at]
          }
        end
      end
    end

    response_data = { success: true, monadic_state: serializable_state }

    # Include conversation_context (Session Context) if present
    conversation_context = session[:monadic_state][:conversation_context] || session[:monadic_state]["conversation_context"]
    if conversation_context
      response_data[:session_context] = conversation_context
    end

    # Include context_schema if present
    context_schema = session[:monadic_state][:context_schema] || session[:monadic_state]["context_schema"]
    if context_schema
      response_data[:context_schema] = context_schema
    end

    response_data.to_json
  else
    { success: true, monadic_state: nil }.to_json
  end
end

# Upload a Session JSON file to load past messages
post "/load" do
  # For AJAX requests, respond with JSON
  if request.xhr?
    content_type :json

    if params[:file]
      begin
        file = params[:file][:tempfile]
        content = file.read
        json_data = JSON.parse(content)

        # Privacy Filter export detection (Block D.4).
        # Three forms produced by Block D.2/D.3:
        #   - encrypted: { schema_version, header, envelope: { kdf, cipher }, integrity }
        #   - masked_only: { header, messages } — no parameters, placeholders intact
        #   - restored: { header, messages, registry } — plain JSON
        # We unwrap each into the standard { parameters, messages } shape so the
        # rest of /load processes them like any other import.
        privacy_registry_to_restore = nil
        if json_data.is_a?(Hash) && json_data["envelope"].is_a?(Hash) &&
           json_data["envelope"].dig("cipher", "algorithm") == "AES-256-GCM"
          passphrase = (params[:passphrase] || "").to_s
          if passphrase.empty?
            return { needs_passphrase: true, header: json_data["header"] }.to_json
          end
          require_relative "../utils/privacy/export_cipher"
          begin
            plaintext = Monadic::Utils::Privacy::ExportCipher.decrypt(
              envelope: json_data, passphrase: passphrase
            )
          rescue Monadic::Utils::Privacy::ExportCipher::DecryptionError
            return { needs_passphrase: true, error: "wrong_passphrase" }.to_json
          rescue Monadic::Utils::Privacy::ExportCipher::IntegrityError => e
            return error_json("Privacy file integrity check failed: #{e.message}")
          end
          decrypted = JSON.parse(plaintext)
          json_data = privacy_synthesize_session(json_data["header"], decrypted, "encrypted")
          privacy_registry_to_restore = decrypted["registry"] if decrypted["registry"].is_a?(Hash)
        elsif json_data.is_a?(Hash) && json_data["header"].is_a?(Hash) &&
              json_data["messages"].is_a?(Array) && !json_data.key?("parameters")
          # Legacy 3-mode privacy export (masked_only or restored plain).
          mode = json_data["registry"].is_a?(Hash) ? "restored" : "masked_only"
          privacy_registry_to_restore = json_data["registry"] if mode == "restored"
          json_data = privacy_synthesize_session(json_data["header"], json_data, mode)
        elsif json_data.is_a?(Hash) && json_data["registry"].is_a?(Hash) &&
              json_data["parameters"].is_a?(Hash)
          # Newer plain export carries `registry` alongside parameters/messages.
          # Capture the registry so the privacy pipeline can be re-seeded after
          # import; the rest of /load handles parameters/messages normally.
          privacy_registry_to_restore = json_data["registry"]
        end

        # Validate required fields
        unless json_data["parameters"] && json_data["messages"]
          return error_json("Invalid format: missing parameters or messages")
        end

        # Set session data
        session[:status] = "loaded"
        # Force initiate_from_assistant and auto_speech to false to prevent unwanted auto-behaviors on import
        # (deletion is not enough because app defaults will override missing keys)
        imported_params = json_data["parameters"].dup
        imported_params["initiate_from_assistant"] = false
        imported_params["auto_speech"] = false
        session[:parameters] = imported_params

        Monadic::Utils::ExtraLogger.log { "[Import] Set parameters: initiate_from_assistant=#{imported_params['initiate_from_assistant']}, auto_speech=#{imported_params['auto_speech']}" }

        # Check if the first message is a system message
        if json_data["messages"].first && json_data["messages"].first["role"] == "system"
          session[:parameters]["initial_prompt"] = json_data["messages"].first["text"]
        end

        # Restore monadic_state if present in import data (for Session State mechanism)
        if json_data["monadic_state"]
          # Convert string keys to symbols for consistency
          session[:monadic_state] = json_data["monadic_state"].transform_keys(&:to_s).each_with_object({}) do |(app_key, app_data), result|
            result[app_key] = app_data.transform_keys(&:to_s).each_with_object({}) do |(state_key, state_entry), app_result|
              app_result[state_key] = {
                data: state_entry["data"],
                version: state_entry["version"].to_i,
                updated_at: state_entry["updated_at"]
              }
            end
          end

          Monadic::Utils::ExtraLogger.log { "[Import] Restored monadic_state for apps: #{session[:monadic_state].keys.join(', ')}" }
        end

        # Restore session_context if present in import data (for Session Context feature)
        if json_data["session_context"]
          session[:monadic_state] ||= {}
          session[:monadic_state][:conversation_context] = json_data["session_context"]

          # Also store context_schema if present
          if json_data["context_schema"]
            session[:monadic_state][:context_schema] = json_data["context_schema"]
          end

          Monadic::Utils::ExtraLogger.log { "[Import] Restored session_context with #{json_data['session_context'].keys.join(', ')}" }
        end

        # Process messages
        app_name = json_data["parameters"]["app_name"]
        session[:messages] = json_data["messages"].uniq.map do |msg|
          # Skip invalid messages
          next unless msg["role"] && msg["text"]

          text = msg["text"]

          # Create message object with required fields
          mid = msg["mid"] || SecureRandom.hex(4)
          message_obj = {
            "role" => msg["role"],
            "text" => text,
            "html" => text,
            "lang" => detect_language(text),
            "mid" => mid,
            "active" => true
          }
          message_obj["app_name"] = app_name if app_name
          if json_data["parameters"].key?("monadic")
            message_obj["monadic"] = json_data["parameters"]["monadic"]
          end
          # Preserve token count if present in import (for accurate stats without recomputation)
          message_obj["tokens"] = msg["tokens"].to_i if msg.key?("tokens")

          # Add optional fields if present
          message_obj["thinking"] = msg["thinking"] if msg["thinking"]
          message_obj["images"] = msg["images"] if msg["images"]
          message_obj
        end.compact # Remove nil values from invalid messages

        if session[:websocket_session_id]
          WebSocketHelper.update_session_state(
            session[:websocket_session_id],
            messages: session[:messages],
            parameters: session[:parameters]
          )
        end

        # Privacy registry restoration (Block D.4). Pre-seed the in-memory
        # registry so the next message reuses imported placeholders. RD-1
        # (memory-only) preserved: this only re-populates session memory.
        if privacy_registry_to_restore.is_a?(Hash) && !privacy_registry_to_restore.empty?
          session[:monadic_state] ||= {}
          session[:monadic_state][:privacy] = {
            registry: privacy_registry_to_restore,
            audit: [{ ts: Time.now.to_i, op: :import, count: privacy_registry_to_restore.size }]
          }
          # Drop any previously-instantiated pipeline so the next vendor call
          # rebuilds it from session state (re-reads the imported registry).
          session.delete(:_privacy_pipeline)
          # Push fresh privacy_state to the client so the indicator updates.
          ws_for_state = params[:tab_id] || session[:websocket_session_id]
          if ws_for_state
            WebSocketHelper.send_to_session({
              "type" => "privacy_state",
              "enabled" => true,
              "registry_count" => privacy_registry_to_restore.size,
              "error" => nil
            }.to_json, ws_for_state)
          end
          Monadic::Utils::ExtraLogger.log { "[Privacy] Restored registry with #{privacy_registry_to_restore.size} entries from import" }
        end

        # Debug logging after import (only when EXTRA_LOGGING is enabled)
        Monadic::Utils::ExtraLogger.log { "JSON import: #{session[:messages].size} messages loaded for app '#{json_data['parameters']['app_name']}'" }

        # Push imported data to client via WebSocket (eliminates need for reload)
        begin
          # Prepare apps data
          apps_data = prepare_apps_data

          # Filter messages by app_name and exclude search messages
          current_app_name = session[:parameters]["app_name"]
          filtered_messages = session[:messages].filter { |m| m["type"] != "search" && m["app_name"] == current_app_name }

          # Get the WebSocket session ID for targeted sending (prevents cross-tab contamination)
          # Try to get tab_id from params first (sent by form-handlers.js)
          ws_session_id = params[:tab_id] || session[:websocket_session_id]

          if ws_session_id
            # Send to specific tab/session only (prevents other tabs from receiving import data)
            # Mark messages as from_import to ensure parameters waits for apps processing
            WebSocketHelper.send_to_session({ "type" => "apps", "content" => apps_data, "version" => session[:version], "docker" => session[:docker], "from_import" => true }.to_json, ws_session_id) unless apps_data.empty?
            sleep(0.2) # Increased delay to ensure apps message is fully processed before parameters
            WebSocketHelper.send_to_session({ "type" => "parameters", "content" => session[:parameters], "from_import" => true }.to_json, ws_session_id) unless session[:parameters].empty?
            sleep(0.05)
            WebSocketHelper.send_to_session({ "type" => "past_messages", "content" => filtered_messages, "from_import" => true }.to_json, ws_session_id)

            # Send session_context if present (for Session Context feature)
            if session[:monadic_state] && session[:monadic_state][:conversation_context]
              context_schema = session[:monadic_state][:context_schema] || nil
              WebSocketHelper.send_to_session({
                "type" => "context_update",
                "context" => session[:monadic_state][:conversation_context],
                "schema" => context_schema,
                "from_import" => true
              }.to_json, ws_session_id)
            end
          else
            # Fallback to broadcast if no session ID (shouldn't happen in normal operation)
            WebSocketHelper.broadcast_to_all({ "type" => "apps", "content" => apps_data, "version" => session[:version], "docker" => session[:docker], "from_import" => true }.to_json) unless apps_data.empty?
            sleep(0.2)
            WebSocketHelper.broadcast_to_all({ "type" => "parameters", "content" => session[:parameters], "from_import" => true }.to_json) unless session[:parameters].empty?
            sleep(0.05)
            WebSocketHelper.broadcast_to_all({ "type" => "past_messages", "content" => filtered_messages, "from_import" => true }.to_json)

            # Send session_context if present (for Session Context feature)
            if session[:monadic_state] && session[:monadic_state][:conversation_context]
              context_schema = session[:monadic_state][:context_schema] || nil
              WebSocketHelper.broadcast_to_all({
                "type" => "context_update",
                "context" => session[:monadic_state][:conversation_context],
                "schema" => context_schema,
                "from_import" => true
              }.to_json)
            end
          end

          Monadic::Utils::ExtraLogger.log { "JSON import: Pushed #{filtered_messages.size} messages via WebSocket (with from_import flag)" }
        rescue => e
          # Log error but don't fail the import - client can still reload manually if needed
          Monadic::Utils::ExtraLogger.log { "Failed to push import data via WebSocket: #{e.message}" }
        end

        { success: true, app_name: json_data['parameters']['app_name'] }.to_json
      rescue JSON::ParserError => e
        error_json("Invalid JSON format")
      rescue => e
        error_json("Import error: #{e.message}")
      end
    else
      error_json("No file selected")
    end
  else
    # For regular form submissions, maintain original behavior
    if params[:file]
      begin
        file = params[:file][:tempfile]
        content = file.read
        json_data = JSON.parse(content)
        session[:status] = "loaded"
        session[:parameters] = json_data["parameters"]

        # Check if the first message is a system message
        if json_data["messages"].first && json_data["messages"].first["role"] == "system"
          session[:parameters]["initial_prompt"] = json_data["messages"].first["text"]
        end

        # Restore monadic_state if present in import data (for Session State mechanism)
        if json_data["monadic_state"]
          session[:monadic_state] = json_data["monadic_state"].transform_keys(&:to_s).each_with_object({}) do |(app_key, app_data), result|
            result[app_key] = app_data.transform_keys(&:to_s).each_with_object({}) do |(state_key, state_entry), app_result|
              app_result[state_key] = {
                data: state_entry["data"],
                version: state_entry["version"].to_i,
                updated_at: state_entry["updated_at"]
              }
            end
          end
        end

        session[:messages] = json_data["messages"].uniq.map do |msg|
          text = msg["text"]
          message_obj = { "role" => msg["role"], "text" => text, "html" => text, "lang" => detect_language(text), "mid" => msg["mid"], "active" => true }
          message_obj["app_name"] = json_data["parameters"]["app_name"] if json_data["parameters"]["app_name"]
          if json_data["parameters"].key?("monadic")
            message_obj["monadic"] = json_data["parameters"]["monadic"]
          end
          message_obj["tokens"] = msg["tokens"].to_i if msg.key?("tokens")
          message_obj["thinking"] = msg["thinking"] if msg["thinking"]
          message_obj["images"] = msg["images"] if msg["images"]
          message_obj
        end

        if session[:websocket_session_id]
          WebSocketHelper.update_session_state(
            session[:websocket_session_id],
            messages: session[:messages],
            parameters: session[:parameters]
          )
        end
      rescue JSON::ParserError
        handle_error("Error: Invalid JSON file. Please upload a valid JSON file.")
      end
    else
      handle_error("Error: No file selected. Please choose a JSON file to upload.")
    end
    redirect "/"
  end
end
