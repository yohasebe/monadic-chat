# frozen_string_literal: true

require 'base64'
require 'json'
require 'time'
require_relative '../privacy/export_cipher'

# WebSocket handlers for exporting a conversation.
#
# Export uses two orthogonal axes:
#   - encrypt:  true (AES-256-GCM + Argon2id) | false (plain JSON)
#   - content:  "restored" (default)          | "masked" (placeholders only)
#
# `encrypt` is always available: it protects the file at rest, while a
# chat's word table hides words in what is sent. The two are independent.

require_relative '../privacy/outbound'
require_relative '../../workbench/record'
require_relative '../../workbench/shown'
require_relative '../../workbench/look/record'

module WebSocketHelper
  PRIVACY_EXPORT_MODES = %w[encrypted masked_only restored].freeze
  PRIVACY_EXPORT_CONTENT = %w[restored masked].freeze

  PAGE_OUT_OF_DATE = 'This page is out of date. Reload the page to go on.'

  # What only a page loaded before this version sends. It is answered here,
  # as a command the page must not repeat, so that it is never taken for a
  # message to the model. The page's switch goes back to off with the reply.
  private def handle_ws_page_out_of_date(connection)
    send_to_client(connection, { "type" => "privacy_toggle_ack", "enabled" => false, "error" => nil })
    send_to_client(connection, { "type" => "error", "content" => PAGE_OUT_OF_DATE })
  end

  private def privacy_container_coming_up?
    deps = Monadic::Utils::ContainerDependencies
    deps.starting?(:privacy) || deps.container_running?(:privacy)
  rescue StandardError
    false
  end

  # The legacy `mode` parameter ("encrypted"|"masked_only"|"restored") is
  # accepted for backward compatibility and translated to the new axes.
  # Sends "privacy_export_data" with base64-encoded JSON content for the
  # download trigger on the client.
  private def handle_ws_privacy_export(connection, session, obj)
    encrypt, content_kind = privacy_export_params(obj)
    unless PRIVACY_EXPORT_CONTENT.include?(content_kind)
      send_to_client(connection, {
        "type" => "privacy_export_error",
        "error" => "invalid_content",
        "valid_content" => PRIVACY_EXPORT_CONTENT
      })
      return
    end

    word_table = Monadic::Utils::Privacy::Words.table(session)
    messages = privacy_clean_messages(session[:messages] || [])

    parameters = privacy_export_parameters(session)

    # A masked file is masked by the chat's active words and holds no table;
    # only a restored file carries the table, so a shared one cannot be
    # turned back.
    remask = word_table ? Monadic::Utils::Privacy::Words.masking(word_table) : {}
    table_to_export = word_table && content_kind == "restored" ? word_table.to_h : nil
    if content_kind == "masked" && !remask.empty?
      messages = privacy_remask_messages(messages, remask)
      parameters = privacy_remask_parameters(parameters, remask)
    end

    legacy_mode = privacy_export_legacy_mode(encrypt, content_kind)

    # Include parameters + monadic_state alongside messages so the export
    # round-trips a full session (matches the historical local export shape).
    # `parameters` was assembled and remasked above, alongside the messages.
    monadic_state = privacy_export_monadic_state(session)
    session_context = privacy_export_session_context(session)
    masked_file = content_kind == "masked" && !remask.empty?
    # Dynamic-skill unlock state, so an imported session restores the skills the
    # model had acquired (reproducibility). This is the ACTIVE export path
    # (the frontend $id("save") handler delegates here), so progressive_tools
    # must be attached to the payload here — not only in the legacy frontend
    # export branch.
    progressive_tools = Monadic::Utils::ProgressiveToolManager.export_unlocked(session)

    # A masked file holds none of the originals anywhere, not only in the
    # message text: everything that goes into it (the app state, the Session
    # Context, what is nested in the messages) is masked, and the file is not
    # written when one is still there.
    if masked_file
      outbound = Monadic::Utils::Privacy::Outbound
      messages = privacy_mask_messages_everywhere(messages, remask)
      parameters = privacy_mask_everywhere(parameters, remask)
      monadic_state = privacy_mask_everywhere(monadic_state, remask)
      session_context = privacy_mask_everywhere(session_context, remask)
      progressive_tools = privacy_mask_everywhere(progressive_tools, remask)
    end

    # The header (plain text even in an encrypted file) and the file name
    # name the app as the exported parameters do: masked in a masked file.
    app_name = parameters.is_a?(Hash) ? parameters["app_name"].to_s : ""
    header = privacy_export_header(app_name, messages)
    filename = privacy_export_filename(app_name, encrypt, content_kind)

    if masked_file
      contents = { "messages" => messages, "parameters" => parameters, "monadic_state" => monadic_state,
                   "session_context" => session_context, "progressive_tools" => progressive_tools,
                   "header" => header, "filename" => filename }
      left = remask.values.map(&:to_s).reject(&:empty?)
      leaked = privacy_file_strings(contents).any? { |text| outbound.holds_word?(text, left) }
      raise ArgumentError, "a masked value is still in the file" if leaked
    end

    if encrypt
      passphrase = obj["passphrase"].to_s
      if passphrase.empty?
        send_to_client(connection, {
          "type" => "privacy_export_error",
          "error" => "passphrase_required"
        })
        return
      end
      payload = {
        "messages" => messages,
        "parameters" => parameters
      }
      payload["word_table"] = table_to_export if table_to_export
      payload["marks_parsed"] = true
      payload["monadic_state"] = monadic_state if monadic_state
      payload.merge!(session_context)
      payload["progressive_tools"] = progressive_tools if progressive_tools
      envelope = Monadic::Utils::Privacy::ExportCipher.encrypt(
        header: header, plaintext: payload, passphrase: passphrase
      )
      content = JSON.generate(envelope)
    else
      payload = { "parameters" => parameters, "messages" => messages }
      payload["word_table"] = table_to_export if table_to_export
      payload["marks_parsed"] = true
      payload["monadic_state"] = monadic_state if monadic_state
      payload.merge!(session_context)
      payload["progressive_tools"] = progressive_tools if progressive_tools
      content = JSON.pretty_generate(payload)
    end

    send_to_client(connection, {
      "type" => "privacy_export_data",
      "mode" => legacy_mode,
      "encrypt" => encrypt,
      "content" => content_kind,
      "filename" => filename,
      "content_base64" => Base64.strict_encode64(content),
      "mime" => "application/json"
    })
  rescue Monadic::Utils::Privacy::ExportCipher::IntegrityError, Monadic::Utils::Privacy::ExportCipher::DecryptionError, ArgumentError,
         Monadic::Utils::Privacy::Outbound::Refused => e
    send_to_client(connection, {
      "type" => "privacy_export_error",
      "error" => "export_failed",
      "detail" => e.message
    })
  end

  # Translate request params (new 2-axis form, or legacy 3-mode form) into
  # the canonical (encrypt, content) tuple. Returns [encrypt:Bool, content:String].
  private def privacy_export_params(obj)
    if obj.key?("encrypt") || obj.key?("content")
      encrypt = obj["encrypt"] == true
      content_kind = (obj["content"] || "restored").to_s
      [encrypt, content_kind]
    else
      legacy = (obj["mode"] || "restored").to_s
      case legacy
      when "encrypted"   then [true,  "restored"]
      when "masked_only" then [false, "masked"]
      else                    [false, "restored"]
      end
    end
  end

  # Map the new (encrypt, content) tuple back to the legacy `mode` string so
  # downstream code (filename hints, telemetry, future migrations) keeps the
  # familiar vocabulary.
  private def privacy_export_legacy_mode(encrypt, content_kind)
    if encrypt
      content_kind == "masked" ? "encrypted_masked" : "encrypted"
    else
      content_kind == "masked" ? "masked_only" : "restored"
    end
  end

  # Parameters carried by a shared export. `parameters` holds free text the
  # user wrote (initial_prompt) and text the run produced (tool_results,
  # tool_calls_message), so a shared copy needs the same treatment as the
  # message bodies: an allow list, then the same remasking.
  #
  # initiate_from_assistant is excluded on purpose — importing it would start
  # an assistant turn by itself (parity with the legacy frontend export).
  PRIVACY_EXPORT_PARAMETER_KEYS = %w[
    app_name display_name model models provider
    temperature max_tokens reasoning_effort
    initial_prompt tools ui_language stt_model tts_voice
  ].freeze

  # Parameter values that are free text and must be remasked, not just copied.
  PRIVACY_REMASK_PARAMETER_KEYS = %w[initial_prompt].freeze

  private def privacy_export_parameters(session)
    source = session[:parameters].is_a?(Hash) ? session[:parameters] : {}
    source.each_with_object({}) do |(k, v), acc|
      acc[k.to_s] = v if PRIVACY_EXPORT_PARAMETER_KEYS.include?(k.to_s)
    end
  end

  # Apply the registry to the free-text parameters, mirroring the message
  # bodies so a masked export is masked everywhere it carries prose.
  private def privacy_remask_parameters(parameters, registry)
    return parameters if registry.empty? || !parameters.is_a?(Hash)

    sorted = registry.sort_by { |_, v| -v.to_s.length }
    parameters.each_with_object(parameters.dup) do |(k, v), acc|
      next unless PRIVACY_REMASK_PARAMETER_KEYS.include?(k.to_s) && v.is_a?(String)

      acc[k] = privacy_replace_union(v, sorted)
    end
  end

  # Keys a shared export may carry. An allow list rather than a deny list: a
  # message picks up display metadata as features are added (privacy entity
  # tracking, vocabulary resolution), and a deny list ships each new one until
  # someone remembers to exclude it. Two of the keys already present are
  # unshareable — `privacy_known_entities` is the placeholder-to-original
  # table the masking exists to withhold, and `vocabulary_map` resolves to
  # paths on the exporting machine.
  #
  # Adding a key here means asserting it is safe to hand to someone else.
  # Derived from both sides of the round trip: the keys the streaming handler
  # writes into session[:messages], and the keys the import route reads back
  # (session_routes.rb). Dropping one the importer reads would break the round
  # trip; listing one that is never written is dead weight.
  PRIVACY_EXPORT_MESSAGE_KEYS = %w[
    mid role text app_name type lang html active
    thinking tokens images image
    interrupted tools_used verify artifacts workbench_looks workbench_shown
  ].freeze

  # Reduce messages to the shared-export schema. Anything not named above is
  # dropped, including the privacy-internal `_privacy*` fields this used to
  # name explicitly.
  private def privacy_clean_messages(messages)
    messages.map do |m|
      next m unless m.is_a?(Hash)

      kept = m.select { |k, _| PRIVACY_EXPORT_MESSAGE_KEYS.include?(k.to_s) }
      # A user message whose reply was stopped: true only.
      kept['reply_stopped'] = true if m['role'] == 'user' && m['reply_stopped'] == true
      # What the reply made (the workbench's record), in its checked form only.
      artifacts = Monadic::Workbench::Record.clean(kept.delete('artifacts') || kept.delete(:artifacts))
      kept = kept.merge('artifacts' => artifacts) if artifacts
      looks = Monadic::Workbench::Look::Record.clean(kept.delete('workbench_looks') || kept.delete(:workbench_looks))
      kept = kept.merge('workbench_looks' => looks) if looks
      shown = Monadic::Workbench::Shown.clean(kept.delete('workbench_shown') || kept.delete(:workbench_shown))
      shown ? kept.merge('workbench_shown' => shown) : kept
    end
  end

  # Free-text fields a message can carry. Masking only `text` left the
  # detected values in the others: reasoning quotes the conversation, and the
  # rendered HTML is built from the restored body.
  PRIVACY_REMASK_MESSAGE_FIELDS = %w[text thinking html].freeze

  # The originals in text replaced by their placeholders, overlapping
  # occurrences as one (Outbound.replace_union), so no part of an original
  # is left because a longer one was replaced first.
  private def privacy_replace_union(text, registry_pairs)
    Monadic::Utils::Privacy::Outbound.replace_union(text, registry_pairs.map { |placeholder, original| [original.to_s, placeholder.to_s] })
  end

  # Every string in a value masked the same way (the app state, the Session
  # Context and anything nested in the messages of a masked file).
  private def privacy_mask_everywhere(value, registry, depth = 0)
    outbound = Monadic::Utils::Privacy::Outbound
    case value
    when String
      # A string that is JSON is masked value by value and written again, so
      # an escaped original ("A\"B") is masked too and the JSON stays valid.
      inner = outbound.json_value(value)
      unless inner.nil?
        raise ArgumentError, "a value is nested as JSON too deeply to be masked" if depth >= outbound::JSON_DEPTH

        return JSON.generate(privacy_mask_everywhere(inner, registry, depth + 1))
      end
      privacy_replace_union(value, registry)
    when Array then value.map { |v| privacy_mask_everywhere(v, registry, depth) }
    when Hash then value.transform_values { |v| privacy_mask_everywhere(v, registry, depth) }
    else value
    end
  end

  # Fields of a message that are its protocol, not what anyone said: kept
  # as they are in a masked file (a role spelled like a marked word stays a
  # role). Only at the message's own level; inside a message's content or
  # the app state every string is masked.
  PRIVACY_MESSAGE_PROTOCOL_KEYS = %w[mid role type app_name lang active].freeze

  private def privacy_mask_messages_everywhere(messages, registry)
    messages.map do |m|
      next privacy_mask_everywhere(m, registry) unless m.is_a?(Hash)

      m.each_with_object({}) do |(k, v), out|
        out[k] = PRIVACY_MESSAGE_PROTOCOL_KEYS.include?(k.to_s) ? v : privacy_mask_everywhere(v, registry)
      end
    end
  end

  # The strings a masked file says (message protocol fields aside), for the
  # last check that no original is left.
  private def privacy_file_strings(contents)
    strings = []
    collect = lambda do |value|
      case value
      when String
        strings << value
        inner = Monadic::Utils::Privacy::Outbound.json_value(value)
        collect.call(inner) unless inner.nil?
      when Array then value.each { |v| collect.call(v) }
      when Hash then value.each { |k, v| strings << k.to_s; collect.call(v) }
      end
    end
    contents.each do |key, value|
      if key == "messages" && value.is_a?(Array)
        value.each do |m|
          next collect.call(m) unless m.is_a?(Hash)

          m.each { |k, v| collect.call(v) unless PRIVACY_MESSAGE_PROTOCOL_KEYS.include?(k.to_s) }
        end
      else
        collect.call(value)
      end
    end
    strings
  end

  # Substitute original values back to placeholders for masked_only export.
  # Sort registry by value length descending to avoid partial-match issues
  # ("Smith" inside "John Smith" must be replaced last).
  private def privacy_remask_messages(messages, registry)
    return messages if registry.empty?
    sorted = registry.sort_by { |_, v| -v.to_s.length }
    messages.map do |m|
      next m unless m.is_a?(Hash)

      remasked = PRIVACY_REMASK_MESSAGE_FIELDS.each_with_object({}) do |field, acc|
        value = m[field]
        next unless value.is_a?(String)

        acc[field] = privacy_replace_union(value, sorted)
      end

      remasked.empty? ? m : m.merge(remasked)
    end
  end

  # Serialize session monadic_state for the export payload. Mirrors the
  # /monadic_state HTTP endpoint shape (used by the legacy local export) so
  # exports remain round-trippable through the existing import path. Returns
  # nil when there is no monadic_state to include.
  # Keys that sit alongside the app namespaces in session[:monadic_state] but
  # hold something else. `conversation_context` and `context_schema` are the
  # Context Panel's own structures; `privacy` is the registry, which RD-1 says
  # is never persisted.
  #
  # The import route reads each app namespace as {key => {data, version,
  # updated_at}} and applies ["data"] to every value, so emitting the panel's
  # plain hash here made the import raise. It has its own field on the wire —
  # `session_context` — which the import route already restores; this exports
  # into that field rather than leaving the mechanism unwired.
  PRIVACY_STATE_RESERVED_KEYS = %w[privacy conversation_context context_schema].freeze

  private def privacy_export_monadic_state(session)
    state = session[:monadic_state]
    return nil unless state.is_a?(Hash)
    serializable = state.each_with_object({}) do |(app_key, app_data), result|
      next if PRIVACY_STATE_RESERVED_KEYS.include?(app_key.to_s)
      next unless app_data.is_a?(Hash)

      # Only namespaces whose entries carry the state envelope round-trip.
      entries = app_data.select do |_key, entry|
        entry.is_a?(Hash) && (entry.key?(:data) || entry.key?("data"))
      end
      next if entries.empty?

      result[app_key.to_s] = entries
    end
    serializable.empty? ? nil : serializable
  end

  # The Context Panel's structures, exported under the field names the import
  # route reads (`session_context` / `context_schema`).
  private def privacy_export_session_context(session)
    state = session[:monadic_state]
    state = {} unless state.is_a?(Hash)

    context = Monadic::Workspace::ChatContext.read(session)
    schema = state[:context_schema] || state["context_schema"]

    {}.tap do |out|
      out["session_context"] = context if context.is_a?(Hash) && !context.empty?
      out["context_schema"] = schema if schema
    end
  end

  # Build a non-secret header for the envelope. Stays in plaintext so users
  # can identify exports without decrypting (header_sha256 protects against
  # tampering).
  private def privacy_export_header(app_name, messages)
    app_name = "unknown" if app_name.to_s.empty?
    {
      "schema_version" => Monadic::Utils::Privacy::ExportCipher::SCHEMA_VERSION,
      "created_at" => Time.now.utc.iso8601,
      "app_name" => app_name,
      "monadic_version" => (defined?(Monadic::VERSION) ? Monadic::VERSION : "unknown"),
      "message_count" => messages.length
    }
  end

  # File extension scheme matches the legacy 3-mode names so older importers
  # keep recognising the files. New combinations reuse the closest legacy
  # extension (encrypted_masked → .mcp-privacy.json since it is encrypted).
  PRIVACY_EXPORT_EXTENSION = {
    "encrypted"        => ".mcp-privacy.json",
    "encrypted_masked" => ".mcp-privacy.json",
    "masked_only"      => ".masked.json",
    "restored"         => ".plain.json"
  }.freeze

  private def privacy_export_filename(app_name, encrypt, content_kind)
    safe_app = app_name.gsub(/[^a-zA-Z0-9_-]/, "_")
    safe_app = "monadic" if safe_app.empty?
    ts = Time.now.strftime("%Y%m%d-%H%M%S")
    legacy = privacy_export_legacy_mode(encrypt, content_kind)
    ext = PRIVACY_EXPORT_EXTENSION[legacy] || ".plain.json"
    # Plain + restored is the only combination that actually deposits raw
    # PII on disk (encrypted-restored is sealed; masked never had it).
    # Tag the filename so the file is recognisable in mixed downloads
    # before anyone opens it — saves a step in the "did I just attach the
    # wrong export?" UX.
    suffix = (!encrypt && content_kind == "restored") ? "-PRIVATE" : ""
    "#{safe_app}-#{ts}#{suffix}#{ext}"
  end

  # Whether a system message the user writes holds a word this chat hides.
  # System messages are sent as written, so the last check before a request
  # leaves would refuse every later request of the chat; such text is
  # refused when it is written instead.
  def hidden_word_in_system_text?(text, session)
    outbound = Monadic::Utils::Privacy::Outbound
    outbound.holds_word?(text.to_s, outbound.terms_of(session))
  rescue Monadic::Utils::Privacy::Outbound::Refused
    true
  end

  SYSTEM_TEXT_MARKED = 'A system message is sent as written, so it cannot hold a word this chat hides. ' \
                       'Nothing was changed.'
end
