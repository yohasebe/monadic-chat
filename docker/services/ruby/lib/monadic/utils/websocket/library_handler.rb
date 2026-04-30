# frozen_string_literal: true

require 'monadic/library'

# WebSocket handlers for the Library (Knowledge Base) panel.
#
# Messages handled:
#   - LIBRARY_LIST   → 'library_conversations' (full inventory snapshot)
#   - LIBRARY_DELETE → 'library_deleted' (removal confirmation)
#   - LIBRARY_STATS  → 'library_stats' (counts only)
#
# All operations run with `scope: :kb` so the Knowledge Base UI sees both
# `personal` and `shareable` items. External RAG access from other apps
# is gated separately via library_search (scope: :external).
module WebSocketHelper
  private def library_store_for_ws
    Monadic::Library::Store.new
  end

  private def handle_ws_library_list(connection, _obj, _session)
    store = library_store_for_ws
    rows = Monadic::Library::Manager.list_conversations(store: store, scope: :kb, limit: 500)
    send_to_client(connection, {
      'type' => 'library_conversations',
      'content' => rows.map { |r| symbol_keys_to_strings(r) }
    })
  rescue StandardError => e
    Monadic::Utils::ExtraLogger.log { "[Library] LIBRARY_LIST failed: #{e.class}: #{e.message}" }
    send_to_client(connection, {
      'type' => 'library_conversations', 'content' => [], 'error' => e.message
    })
  end

  private def handle_ws_library_delete(connection, obj, _session)
    conv_id = obj['contents'].to_s
    if conv_id.empty?
      send_to_client(connection, {
        'type' => 'library_deleted', 'res' => 'failure',
        'content' => 'Missing conversation_id'
      })
      return
    end

    store = library_store_for_ws
    Monadic::Library::Manager.delete_conversation(store: store, conversation_id: conv_id)
    send_to_client(connection, {
      'type' => 'library_deleted', 'res' => 'success',
      'content' => "#{conv_id} deleted",
      'conversation_id' => conv_id
    })
  rescue StandardError => e
    Monadic::Utils::ExtraLogger.log { "[Library] LIBRARY_DELETE failed: #{e.class}: #{e.message}" }
    send_to_client(connection, {
      'type' => 'library_deleted', 'res' => 'failure',
      'content' => e.message,
      'conversation_id' => obj['contents']
    })
  end

  private def handle_ws_library_stats(connection, _obj, _session)
    store = library_store_for_ws
    stats = Monadic::Library::Manager.library_stats(store: store)
    send_to_client(connection, {
      'type' => 'library_stats',
      'content' => symbol_keys_to_strings(stats)
    })
  rescue StandardError => e
    Monadic::Utils::ExtraLogger.log { "[Library] LIBRARY_STATS failed: #{e.class}: #{e.message}" }
    send_to_client(connection, {
      'type' => 'library_stats',
      'content' => { 'conversations_total' => 0, 'conversations_personal' => 0, 'conversations_shareable' => 0 },
      'error' => e.message
    })
  end

  private def symbol_keys_to_strings(hash)
    hash.each_with_object({}) { |(k, v), out| out[k.to_s] = v }
  end
end
