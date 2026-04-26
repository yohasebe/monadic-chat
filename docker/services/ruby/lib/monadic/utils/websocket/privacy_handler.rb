# frozen_string_literal: true

require 'base64'
require 'json'
require 'time'
require_relative '../privacy/export_cipher'

# WebSocket handlers for the Privacy Filter UI (Blocks C.3 + D.2).
# Provides registry inspection (modal viewer) and 3-mode export.
# Registry stays in memory only (RD-1); exports are user-driven via UI.

module WebSocketHelper
  PRIVACY_PLACEHOLDER_RE = /\A<<([A-Z_]+)_(\d+)>>\z/
  PRIVACY_EXPORT_MODES = %w[encrypted masked_only restored].freeze

  # Respond to "PRIVACY_REGISTRY" requests with the current placeholder map.
  # The payload is intentionally compact (one row per placeholder) and never
  # cached or persisted client-side.
  private def handle_ws_privacy_registry(connection, session)
    pipeline = session[:_privacy_pipeline]
    payload = {
      "type" => "privacy_registry",
      "enabled" => !!pipeline,
      "entries" => privacy_registry_entries(pipeline)
    }
    send_to_client(connection, payload)
  end

  private def privacy_registry_entries(pipeline)
    return [] unless pipeline

    state = pipeline.respond_to?(:registry_state) ? pipeline.registry_state : nil
    registry = state.is_a?(Hash) ? state[:registry] : nil
    return [] unless registry.is_a?(Hash)

    registry.map do |placeholder, original|
      type = if (m = placeholder.match(PRIVACY_PLACEHOLDER_RE))
               m[1]
             else
               "UNKNOWN"
             end
      { "placeholder" => placeholder, "original" => original, "type" => type }
    end
  end

  # Handle "PRIVACY_EXPORT" requests. Three modes:
  #   - encrypted   : AES-256-GCM + Argon2id, payload = restored messages + registry
  #   - masked_only : placeholders only (registry stripped), no encryption
  #   - restored    : restored messages + registry, plain JSON (warning UI in C.3)
  # Sends "privacy_export_data" with base64-encoded JSON content for
  # download trigger on the client.
  private def handle_ws_privacy_export(connection, session, obj)
    mode = (obj["mode"] || "encrypted").to_s
    unless PRIVACY_EXPORT_MODES.include?(mode)
      send_to_client(connection, {
        "type" => "privacy_export_error",
        "error" => "invalid_mode",
        "valid_modes" => PRIVACY_EXPORT_MODES
      })
      return
    end

    pipeline = session[:_privacy_pipeline]
    state = pipeline.respond_to?(:registry_state) ? pipeline.registry_state : nil
    registry = (state.is_a?(Hash) ? state[:registry] : {}) || {}
    messages = privacy_clean_messages(session[:messages] || [])
    header = privacy_export_header(session, messages, registry)

    case mode
    when "encrypted"
      passphrase = obj["passphrase"].to_s
      if passphrase.empty?
        send_to_client(connection, {
          "type" => "privacy_export_error",
          "error" => "passphrase_required"
        })
        return
      end
      payload = { "messages" => messages, "registry" => registry }
      envelope = Monadic::Utils::Privacy::ExportCipher.encrypt(
        header: header, plaintext: payload, passphrase: passphrase
      )
      content = JSON.generate(envelope)
      filename = privacy_export_filename(session, mode)
    when "masked_only"
      masked_messages = privacy_remask_messages(messages, registry)
      payload = { "header" => header, "messages" => masked_messages }
      content = JSON.pretty_generate(payload)
      filename = privacy_export_filename(session, mode)
    when "restored"
      payload = { "header" => header, "messages" => messages, "registry" => registry }
      content = JSON.pretty_generate(payload)
      filename = privacy_export_filename(session, mode)
    end

    send_to_client(connection, {
      "type" => "privacy_export_data",
      "mode" => mode,
      "filename" => filename,
      "content_base64" => Base64.strict_encode64(content),
      "mime" => "application/json"
    })
  rescue Monadic::Utils::Privacy::ExportCipher::IntegrityError, Monadic::Utils::Privacy::ExportCipher::DecryptionError, ArgumentError => e
    send_to_client(connection, {
      "type" => "privacy_export_error",
      "error" => "export_failed",
      "detail" => e.message
    })
  end

  # Strip privacy-internal fields from messages so the export only contains
  # the user-visible conversation. We deliberately keep mid/role/text/app_name.
  private def privacy_clean_messages(messages)
    messages.map do |m|
      next m unless m.is_a?(Hash)
      m.reject { |k, _| k.to_s.start_with?("_privacy") }
    end
  end

  # Substitute original values back to placeholders for masked_only export.
  # Sort registry by value length descending to avoid partial-match issues
  # ("Smith" inside "John Smith" must be replaced last).
  private def privacy_remask_messages(messages, registry)
    return messages if registry.empty?
    sorted = registry.sort_by { |_, v| -v.to_s.length }
    messages.map do |m|
      next m unless m.is_a?(Hash) && m["text"].is_a?(String)
      text = m["text"].dup
      sorted.each do |placeholder, original|
        text.gsub!(original.to_s, placeholder.to_s)
      end
      m.merge("text" => text)
    end
  end

  # Build a non-secret header for the envelope. Stays in plaintext so users
  # can identify exports without decrypting (header_sha256 protects against
  # tampering).
  private def privacy_export_header(session, messages, registry)
    app_name = session.dig(:parameters, "app_name") || "unknown"
    {
      "schema_version" => Monadic::Utils::Privacy::ExportCipher::SCHEMA_VERSION,
      "created_at" => Time.now.utc.iso8601,
      "app_name" => app_name,
      "monadic_version" => (defined?(Monadic::VERSION) ? Monadic::VERSION : "unknown"),
      "message_count" => messages.length,
      "registry_count" => registry.size
    }
  end

  PRIVACY_EXPORT_EXTENSION = {
    "encrypted" => ".mcp-privacy.json",
    "masked_only" => ".masked.json",
    "restored" => ".plain.json"
  }.freeze

  private def privacy_export_filename(session, mode)
    app_name = session.dig(:parameters, "app_name").to_s
    safe_app = app_name.gsub(/[^a-zA-Z0-9_-]/, "_")
    safe_app = "monadic" if safe_app.empty?
    ts = Time.now.strftime("%Y%m%d-%H%M%S")
    "#{safe_app}-#{ts}#{PRIVACY_EXPORT_EXTENSION[mode]}"
  end
end
