# frozen_string_literal: true

require 'base64'
require 'json'
require 'time'
require_relative '../privacy/export_cipher'

# WebSocket handlers for the Privacy Filter UI (Blocks C.3 + D.2).
# Provides registry inspection (modal viewer) and the unified export dialog.
#
# Export uses two orthogonal axes:
#   - encrypt:  true (AES-256-GCM + Argon2id) | false (plain JSON)
#   - content:  "restored" (default)          | "masked" (placeholders only)
#
# `encrypt` is always available, regardless of whether the Privacy Filter
# is active in this session — encryption protects files at rest, while the
# privacy filter protects data in transit to LLM providers. The two
# concerns are independent.
#
# Registry stays in memory only (RD-1); exports are user-driven via UI.

module WebSocketHelper
  PRIVACY_PLACEHOLDER_RE = /\A<<([A-Z_]+)_(\d+)>>\z/
  PRIVACY_EXPORT_MODES = %w[encrypted masked_only restored].freeze
  PRIVACY_EXPORT_CONTENT = %w[restored masked].freeze

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

  # Handle "PRIVACY_EXPORT" requests. Two orthogonal axes:
  #   - encrypt: bool (AES-256-GCM + Argon2id with passphrase, or plain JSON)
  #   - content: "restored" (default) | "masked" (placeholders only, no registry)
  #
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

    pipeline = session[:_privacy_pipeline]
    state = pipeline.respond_to?(:registry_state) ? pipeline.registry_state : nil
    registry = (state.is_a?(Hash) ? state[:registry] : {}) || {}
    messages = privacy_clean_messages(session[:messages] || [])

    # When the user requests "masked", apply the registry placeholders to the
    # message text and drop the registry from the export so the file never
    # contains real PII. If there is no registry (privacy filter was off),
    # "masked" is equivalent to "restored" — there are no placeholders to
    # apply, so the original text passes through unchanged.
    if content_kind == "masked" && !registry.empty?
      messages = privacy_remask_messages(messages, registry)
      registry_to_export = {}
    else
      registry_to_export = registry
    end

    header = privacy_export_header(session, messages, registry_to_export)
    legacy_mode = privacy_export_legacy_mode(encrypt, content_kind)

    # Include parameters + monadic_state alongside messages so the export
    # round-trips a full session (matches the historical local export shape).
    # Strip initiate_from_assistant to prevent automatic assistant turn on
    # import (parity with the legacy frontend export path).
    parameters = session[:parameters].is_a?(Hash) ? session[:parameters].dup : {}
    parameters.delete("initiate_from_assistant")
    parameters.delete(:initiate_from_assistant)
    monadic_state = privacy_export_monadic_state(session)

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
        "registry" => registry_to_export,
        "parameters" => parameters
      }
      payload["monadic_state"] = monadic_state if monadic_state
      envelope = Monadic::Utils::Privacy::ExportCipher.encrypt(
        header: header, plaintext: payload, passphrase: passphrase
      )
      content = JSON.generate(envelope)
    else
      payload = { "parameters" => parameters, "messages" => messages }
      payload["registry"] = registry_to_export unless registry_to_export.empty?
      payload["monadic_state"] = monadic_state if monadic_state
      content = JSON.pretty_generate(payload)
    end

    filename = privacy_export_filename(session, encrypt, content_kind)

    send_to_client(connection, {
      "type" => "privacy_export_data",
      "mode" => legacy_mode,
      "encrypt" => encrypt,
      "content" => content_kind,
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

  # Serialize session monadic_state for the export payload. Mirrors the
  # /monadic_state HTTP endpoint shape (used by the legacy local export) so
  # exports remain round-trippable through the existing import path. Returns
  # nil when there is no monadic_state to include.
  private def privacy_export_monadic_state(session)
    state = session[:monadic_state]
    return nil unless state.is_a?(Hash)
    serializable = state.each_with_object({}) do |(app_key, app_data), result|
      next if app_key == :privacy || app_key == "privacy"  # RD-1: never persist
      result[app_key.to_s] = app_data
    end
    serializable.empty? ? nil : serializable
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

  # File extension scheme matches the legacy 3-mode names so older importers
  # keep recognising the files. New combinations reuse the closest legacy
  # extension (encrypted_masked → .mcp-privacy.json since it is encrypted).
  PRIVACY_EXPORT_EXTENSION = {
    "encrypted"        => ".mcp-privacy.json",
    "encrypted_masked" => ".mcp-privacy.json",
    "masked_only"      => ".masked.json",
    "restored"         => ".plain.json"
  }.freeze

  private def privacy_export_filename(session, encrypt, content_kind)
    app_name = session.dig(:parameters, "app_name").to_s
    safe_app = app_name.gsub(/[^a-zA-Z0-9_-]/, "_")
    safe_app = "monadic" if safe_app.empty?
    ts = Time.now.strftime("%Y%m%d-%H%M%S")
    legacy = privacy_export_legacy_mode(encrypt, content_kind)
    ext = PRIVACY_EXPORT_EXTENSION[legacy] || ".plain.json"
    "#{safe_app}-#{ts}#{ext}"
  end
end
