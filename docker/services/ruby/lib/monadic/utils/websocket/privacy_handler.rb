# frozen_string_literal: true

# WebSocket handlers for the Privacy Filter UI (Block C.3).
# Currently provides registry inspection so the frontend can render the
# correspondence-table modal. Registry stays in memory only (RD-1).

module WebSocketHelper
  PRIVACY_PLACEHOLDER_RE = /\A<<([A-Z_]+)_(\d+)>>\z/

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
end
