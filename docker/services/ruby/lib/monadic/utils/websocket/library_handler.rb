# frozen_string_literal: true

require 'monadic/library'

# WebSocket handlers for the Library (Knowledge Base) panel.
#
# Messages handled:
#   - LIBRARY_LIST   → 'library_conversations' (full inventory snapshot)
#   - LIBRARY_DELETE → 'library_deleted' (removal confirmation)
#   - LIBRARY_STATS  → 'library_stats' (counts only)
#   - LIBRARY_SAVE   → 'library_saved' (ingest current session into Library)
#   - LIBRARY_TOGGLE_VISIBILITY → 'library_visibility_updated'
#   - LIBRARY_GET_CONVERSATION  → 'library_conversation_data' (verbatim
#                                  messages for the Viewer modal)
#   - LIBRARY_RAG_TOGGLE → 'library_rag_state' (per-session RAG opt-in flag)
#   - LIBRARY_RAG_QUERY  → 'library_rag_state' (UI sync on connect)
#
# All read/write operations on the inventory run with `scope: :kb` so the
# Knowledge Base UI sees both `personal` and `shareable` items. External
# RAG access from other apps via library_search uses `scope: :external`,
# which only returns `shareable` conversations. The per-session toggle
# stored in session[:parameters]['library_rag_enabled'] is consulted by
# the library_search tool itself.
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

  RAG_TOGGLE_KEY = 'library_rag_enabled'

  private def handle_ws_library_rag_toggle(connection, obj, session)
    enabled = obj['contents']
    enabled = enabled.is_a?(Hash) ? !!(enabled['enabled']) : !!enabled

    session[:parameters] ||= {}
    session[:parameters][RAG_TOGGLE_KEY] = enabled

    send_to_client(connection, {
      'type' => 'library_rag_state', 'enabled' => enabled
    })
  end

  private def handle_ws_library_rag_query(connection, _obj, session)
    params = session[:parameters] || {}
    enabled = !!params[RAG_TOGGLE_KEY]
    send_to_client(connection, {
      'type' => 'library_rag_state', 'enabled' => enabled
    })
  end

  private def handle_ws_library_get_conversation(connection, obj, _session)
    conv_id = obj['contents'].is_a?(Hash) ? obj['contents']['conversation_id'].to_s : obj['contents'].to_s
    if conv_id.empty?
      send_to_client(connection, {
        'type' => 'library_conversation_data', 'res' => 'failure',
        'content' => 'Missing conversation_id'
      })
      return
    end

    store = library_store_for_ws
    record = Monadic::Library::Manager.get_conversation_messages(
      store: store, conversation_id: conv_id, scope: :kb
    )
    if record.nil?
      send_to_client(connection, {
        'type' => 'library_conversation_data', 'res' => 'failure',
        'content' => 'Conversation not found',
        'conversation_id' => conv_id
      })
      return
    end

    send_to_client(connection, {
      'type' => 'library_conversation_data', 'res' => 'success',
      'conversation_id' => conv_id,
      'conversation' => symbol_keys_to_strings(record)
    })
  rescue StandardError => e
    Monadic::Utils::ExtraLogger.log { "[Library] LIBRARY_GET_CONVERSATION failed: #{e.class}: #{e.message}" }
    send_to_client(connection, {
      'type' => 'library_conversation_data', 'res' => 'failure',
      'content' => e.message,
      'conversation_id' => obj.is_a?(Hash) ? obj['contents'] : nil
    })
  end

  private def handle_ws_library_toggle_visibility(connection, obj, _session)
    payload = obj['contents']
    payload = {} unless payload.is_a?(Hash)
    conv_id = payload['conversation_id'].to_s
    visibility = payload['visibility'].to_s

    if conv_id.empty?
      send_to_client(connection, {
        'type' => 'library_visibility_updated', 'res' => 'failure',
        'content' => 'Missing conversation_id'
      })
      return
    end
    unless Monadic::Library::Store::VALID_VISIBILITIES.include?(visibility)
      send_to_client(connection, {
        'type' => 'library_visibility_updated', 'res' => 'failure',
        'content' => "visibility must be one of #{Monadic::Library::Store::VALID_VISIBILITIES.inspect}",
        'conversation_id' => conv_id
      })
      return
    end

    store = library_store_for_ws
    Monadic::Library::Manager.update_visibility(
      store: store, conversation_id: conv_id, visibility: visibility
    )
    send_to_client(connection, {
      'type' => 'library_visibility_updated', 'res' => 'success',
      'conversation_id' => conv_id, 'visibility' => visibility
    })
  rescue ArgumentError => e
    send_to_client(connection, {
      'type' => 'library_visibility_updated', 'res' => 'failure',
      'content' => e.message, 'conversation_id' => obj.dig('contents', 'conversation_id')
    })
  rescue StandardError => e
    Monadic::Utils::ExtraLogger.log { "[Library] LIBRARY_TOGGLE_VISIBILITY failed: #{e.class}: #{e.message}" }
    send_to_client(connection, {
      'type' => 'library_visibility_updated', 'res' => 'failure',
      'content' => e.message, 'conversation_id' => obj.dig('contents', 'conversation_id')
    })
  end

  private def handle_ws_library_save(connection, obj, _session)
    payload = obj['contents']
    payload = {} unless payload.is_a?(Hash)

    messages = payload['messages']
    parameters = payload['parameters']
    visibility = (payload['visibility'] || 'personal').to_s
    title = payload['title']
    license = payload['license']
    monadic_state = payload['monadic_state']

    unless messages.is_a?(Array) && !messages.empty?
      send_to_client(connection, {
        'type' => 'library_saved', 'res' => 'failure',
        'content' => 'No messages to save'
      })
      return
    end
    unless parameters.is_a?(Hash)
      send_to_client(connection, {
        'type' => 'library_saved', 'res' => 'failure',
        'content' => 'Missing parameters'
      })
      return
    end
    unless Monadic::Library::Store::VALID_VISIBILITIES.include?(visibility)
      send_to_client(connection, {
        'type' => 'library_saved', 'res' => 'failure',
        'content' => "visibility must be one of #{Monadic::Library::Store::VALID_VISIBILITIES.inspect}"
      })
      return
    end

    importer_input = { 'parameters' => parameters, 'messages' => messages }
    importer_input['monadic_state'] = monadic_state if monadic_state.is_a?(Hash)

    options = {}
    options[:title] = title.to_s unless title.to_s.empty?
    options[:license] = license.to_s unless license.to_s.empty?

    store = library_store_for_ws
    result = Monadic::Library::Manager.import_from_text(
      store: store, input: importer_input, options: options, visibility: visibility
    )
    send_to_client(connection, {
      'type' => 'library_saved', 'res' => 'success',
      'content' => "Conversation saved to Knowledge Base.",
      'conversation_id' => result[:conversation_id],
      'visibility' => visibility,
      'counts' => result[:counts].each_with_object({}) { |(k, v), h| h[k.to_s] = v }
    })
  rescue ArgumentError => e
    Monadic::Utils::ExtraLogger.log { "[Library] LIBRARY_SAVE bad input: #{e.class}: #{e.message}" }
    send_to_client(connection, {
      'type' => 'library_saved', 'res' => 'failure', 'content' => e.message
    })
  rescue StandardError => e
    Monadic::Utils::ExtraLogger.log { "[Library] LIBRARY_SAVE failed: #{e.class}: #{e.message}" }
    send_to_client(connection, {
      'type' => 'library_saved', 'res' => 'failure', 'content' => e.message
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
