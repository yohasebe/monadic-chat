# frozen_string_literal: false

require_relative "../utils/privacy/marks"

# Session state management routes
# Export/import conversation state and session data

# Largest saved conversation /load accepts, checked before the body is read (config.ru).
SESSION_LOAD_MAX_BYTES = 500_000_000

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
  result["progressive_tools"] = body["progressive_tools"] if body["progressive_tools"].is_a?(Hash)
  result
end

# The chat of the tab a request comes from (tab_id): as its open connection
# holds it, or, while the tab reconnects, as the tab last saved it. A tab
# with neither has no chat (an empty one). The request's own session is
# shared by every tab and is not a chat; it is read only by a request that
# names no tab (older pages).
def tab_chat_session(tab_id)
  return session if tab_id.nil? || tab_id.to_s.empty?

  live = WebSocketHelper.live_session(tab_id)
  return live if live

  saved = WebSocketHelper.fetch_session_state(tab_id.to_s)
  return {} unless saved

  (saved[:chat_state] || {}).merge(messages: saved[:messages], parameters: saved[:parameters])
end

# The marked words of an imported file, checked: a list of { text, type }
# with a known type, as the Privacy container takes them. Raises
# ArgumentError on anything else (the import then stops, rather than go on
# without the words).
def privacy_import_terms(raw)
  return [] if raw.nil?
  raise ArgumentError, "the marked words in the file are not a list" unless raw.is_a?(Array)
  raise ArgumentError, "the file has too many marked words" if raw.size > 200

  require_relative "../utils/privacy/marks"
  known = Monadic::Utils::Privacy::Marks::TYPE_ALIASES.keys
  raw.map do |term|
    text = term.is_a?(Hash) ? term["text"].to_s : ""
    type = term.is_a?(Hash) ? (term["type"] || "PERSON").to_s : ""
    raise ArgumentError, "a marked word in the file is not readable" if text.empty? || text.length > 200 || !known.include?(type)

    { text: text, type: type }
  end.reverse.uniq { |t| t[:text] }.reverse # a word given twice keeps its last type
end

# Get monadic_state for export (Session State mechanism)
get "/monadic_state" do
  content_type :json

  response_data = { success: true, monadic_state: nil }
  session = tab_chat_session(params[:tab_id])

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

    response_data[:monadic_state] = serializable_state

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
  end

  # Include dynamic-skill unlock state so an exported session restores the
  # skills the model had acquired (reproducibility). Independent of
  # monadic_state — a thin app may have unlocked skills without any state.
  progressive_tools = Monadic::Utils::ProgressiveToolManager.export_unlocked(session)
  response_data[:progressive_tools] = progressive_tools if progressive_tools

  response_data.to_json
end

# Upload a Session JSON file to load past messages. Always returns JSON
# (see JSON routes in docs_dev/developer/anti_pattern_lints.md).
post "/load" do
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
        privacy_terms_source = json_data
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
          privacy_terms_source = decrypted
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

        # The conversation is built here and taken over by the tab it was
        # sent from, on its own WebSocket (IMPORT_APPLY): that connection
        # runs the tab's chat, so it stops what is running, starts a new
        # chat and puts this one in. This request's session is not the chat.
        tab_id = params[:tab_id].to_s
        return error_json("Import error: open Monadic Chat in this tab first") if tab_id.empty?

        imported = {}
        require_relative "../utils/privacy/marks"
        marked_in_messages = []
        parse_marks = !(privacy_terms_source.is_a?(Hash) && privacy_terms_source["marks_parsed"] == true)
        # Force initiate_from_assistant and auto_speech to false to prevent unwanted auto-behaviors on import
        # (deletion is not enough because app defaults will override missing keys)
        imported_params = json_data["parameters"].dup
        imported_params["initiate_from_assistant"] = false
        imported_params["auto_speech"] = false
        imported[:parameters] = imported_params

        Monadic::Utils::ExtraLogger.log { "[Import] Set parameters: initiate_from_assistant=#{imported_params['initiate_from_assistant']}, auto_speech=#{imported_params['auto_speech']}" }

        # Restore dynamic-skill unlock state so the imported session resumes
        # with the skills the model had acquired (reproducibility). Volatile
        # and absent from older exports, so this is a no-op for those.
        if json_data["progressive_tools"].is_a?(Hash)
          Monadic::Utils::ProgressiveToolManager.import_unlocked(imported, json_data["progressive_tools"])
        end

        # Check if the first message is a system message
        if json_data["messages"].first && json_data["messages"].first["role"] == "system"
          imported[:parameters]["initial_prompt"] = json_data["messages"].first["text"]
        end

        # Restore monadic_state if present in import data (for Session State mechanism)
        if json_data["monadic_state"]
          # Convert string keys to symbols for consistency
          # Only namespaces shaped like {key => {data, version, updated_at}}
          # are app state. A file written before the export separated the
          # Context Panel's structures out can carry those here instead, and
          # reading ["data"] from an Integer or Array raised, which failed the
          # whole import. Skip what does not fit and let session_context below
          # restore the panel.
          imported[:monadic_state] = json_data["monadic_state"].transform_keys(&:to_s).each_with_object({}) do |(app_key, app_data), result|
            next unless app_data.is_a?(Hash)

            entries = app_data.transform_keys(&:to_s).each_with_object({}) do |(state_key, state_entry), app_result|
              next unless state_entry.is_a?(Hash) && state_entry.key?("data")

              app_result[state_key] = {
                data: state_entry["data"],
                version: state_entry["version"].to_i,
                updated_at: state_entry["updated_at"]
              }
            end
            result[app_key] = entries unless entries.empty?
          end

          Monadic::Utils::ExtraLogger.log { "[Import] Restored monadic_state for apps: #{imported[:monadic_state].keys.join(', ')}" }
        end

        # Files written before the export separated them carry the panel under
        # monadic_state instead. Read it from there when the dedicated field is
        # absent, so an older export still restores its context.
        legacy_state = json_data["monadic_state"]
        if !json_data["session_context"] && legacy_state.is_a?(Hash)
          legacy_context = legacy_state["conversation_context"]
          json_data["session_context"] = legacy_context if legacy_context.is_a?(Hash)
          legacy_schema = legacy_state["context_schema"]
          json_data["context_schema"] ||= legacy_schema if legacy_schema
        end

        # Restore session_context if present in import data (for Session Context feature)
        if json_data["session_context"]
          imported[:monadic_state] ||= {}
          imported[:monadic_state][:conversation_context] = json_data["session_context"]

          # Also store context_schema if present
          if json_data["context_schema"]
            imported[:monadic_state][:context_schema] = json_data["context_schema"]
          end

          Monadic::Utils::ExtraLogger.log { "[Import] Restored session_context with #{json_data['session_context'].keys.join(', ')}" }
        end

        # Process messages.
        # A live speech-to-speech bridge must not survive the canon being
        # replaced: it keeps the upstream socket billing, and its Stop-time
        # merge span would point into the OLD canon and fold the imported
        # history (same invariant as RESET's teardown).
        app_name = json_data["parameters"]["app_name"]
        imported[:messages] = json_data["messages"].uniq.map do |msg|
          # Skip invalid messages
          next unless msg["role"] && msg["text"]

          text = msg["text"]
          # Words a person marked in what they wrote (⟦…⟧) are read as when
          # typed: taken out and kept for the chat, so they are masked from
          # the start of the imported chat. (A model's reply is not read for
          # marks.)
          # A file this version wrote has its marks taken out already (its
          # brackets are the user's own text), so it is not read again.
          if parse_marks && msg["role"] == "user" && Monadic::Utils::Privacy::Marks.any?(text)
            text, found = Monadic::Utils::Privacy::Marks.extract(text)
            marked_in_messages.concat(found)
          end

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
          # Preserve a confidence-via-agreement verdict so an imported
          # conversation restores it on render (KB save strips it separately).
          message_obj["verify"] = msg["verify"] if msg["verify"].is_a?(Hash)
          message_obj["app_name"] = app_name if app_name
          if json_data["parameters"].key?("monadic")
            message_obj["monadic"] = json_data["parameters"]["monadic"]
          end
          # Preserve token count if present in import (for accurate stats without recomputation)
          message_obj["tokens"] = msg["tokens"].to_i if msg.key?("tokens")

          # Add optional fields if present
          message_obj["thinking"] = msg["thinking"] if msg["thinking"]
          message_obj["images"] = msg["images"] if msg["images"]
          # Preserve display metadata (badge sources): interrupted markers
          # and tools_used from speech-to-speech turns (import dropped them,
          # silently losing the badges on round-trip).
          message_obj["interrupted"] = true if msg["interrupted"]
          message_obj["tools_used"] = msg["tools_used"] if msg["tools_used"].is_a?(Array)
          message_obj
        end.compact # Remove nil values from invalid messages

        # Privacy registry restoration (Block D.4): seeded into the chat when
        # the tab takes the import, so the next message reuses the imported
        # placeholders. RD-1 (memory-only) preserved.
        # The words the user had marked come back with a restored file, so the
        # imported chat goes on masking them (a masked file holds none).
        terms_to_restore = begin
          privacy_import_terms(privacy_terms_source.is_a?(Hash) ? privacy_terms_source["terms"] : nil)
        rescue ArgumentError => e
          return error_json("Import error: #{e.message}")
        end
        terms_to_restore = (terms_to_restore + marked_in_messages).reverse.uniq { |t| t[:text] }.reverse
        return error_json("Import error: the file has too many marked words") if terms_to_restore.size > 200
        has_registry = privacy_registry_to_restore.is_a?(Hash) && !privacy_registry_to_restore.empty?
        if has_registry || terms_to_restore.any?
          registry = has_registry ? privacy_registry_to_restore : {}
          imported[:monadic_state] ||= {}
          imported[:monadic_state][:privacy] = {
            registry: registry,
            audit: [{ ts: Time.now.to_i, op: :import, count: registry.size }],
            terms: terms_to_restore
          }
          # Importing a registry implies the user wanted privacy on for this
          # conversation; mirror that in the backend SSOT toggle so vendor
          # helpers honor it without requiring the user to re-toggle.
          imported[:_privacy_session_enabled] = true
        end

        Monadic::Utils::ExtraLogger.log { "JSON import: #{imported[:messages].size} messages read for app '#{json_data['parameters']['app_name']}'" }
        token = WebSocketHelper.stage_import(tab_id, imported)

        { success: true, app_name: json_data['parameters']['app_name'], import_token: token }.to_json
      rescue Monadic::Utils::Privacy::Marks::Invalid => e
        error_json("Import error: words marked with \u27E6 \u27E7 in the file could not be read: #{e.message}")
      rescue JSON::ParserError => e
        error_json("Invalid JSON format")
      rescue => e
        error_json("Import error: #{e.message}")
      end
    else
      error_json("No file selected")
    end
end
