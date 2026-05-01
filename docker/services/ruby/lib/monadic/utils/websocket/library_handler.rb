# frozen_string_literal: true

require 'monadic/library'

# WebSocket handlers for the Library (Knowledge Base) panel.
#
# Messages handled:
#   - LIBRARY_LIST          → 'library_conversations' (full inventory)
#   - LIBRARY_DELETE        → 'library_deleted'
#   - LIBRARY_STATS         → 'library_stats' (totals + per-scope counts)
#   - LIBRARY_SAVE          → 'library_saved' (ingest current session)
#   - LIBRARY_SET_SCOPE     → 'library_scope_updated' (flip an entry
#                              between an app scope and "Global")
#   - LIBRARY_RENAME        → 'library_renamed'
#   - LIBRARY_GET_CONVERSATION → 'library_conversation_data'
#   - LIBRARY_RAG_TOGGLE    → 'library_rag_state'
#   - LIBRARY_RAG_QUERY     → 'library_rag_state' (UI sync on connect)
#
# Inventory reads (LIBRARY_LIST, GET_CONVERSATION, STATS) pass
# `app_name: nil` so the KB UI sees the entire library regardless of
# scope — scoping is a retrieval-time concern enforced by
# library_search, not a UI visibility gate.
module WebSocketHelper
  private def library_store_for_ws
    Monadic::Library::Store.new
  end

  private def handle_ws_library_list(connection, _obj, _session)
    store = library_store_for_ws
    rows = Monadic::Library::Manager.list_conversations(store: store, app_name: nil, limit: 500)
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
      store: store, conversation_id: conv_id, app_name: nil
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

  private def handle_ws_library_rename(connection, obj, _session)
    payload = obj['contents']
    payload = {} unless payload.is_a?(Hash)
    conv_id = payload['conversation_id'].to_s
    title = payload['title'].to_s

    if conv_id.empty?
      send_to_client(connection, {
        'type' => 'library_renamed', 'res' => 'failure',
        'content' => 'Missing conversation_id'
      })
      return
    end

    store = library_store_for_ws
    Monadic::Library::Manager.update_title(
      store: store, conversation_id: conv_id, title: title
    )
    send_to_client(connection, {
      'type' => 'library_renamed', 'res' => 'success',
      'conversation_id' => conv_id, 'title' => title.strip
    })
  rescue ArgumentError => e
    send_to_client(connection, {
      'type' => 'library_renamed', 'res' => 'failure',
      'content' => e.message,
      'conversation_id' => obj.dig('contents', 'conversation_id')
    })
  rescue StandardError => e
    Monadic::Utils::ExtraLogger.log { "[Library] LIBRARY_RENAME failed: #{e.class}: #{e.message}" }
    send_to_client(connection, {
      'type' => 'library_renamed', 'res' => 'failure',
      'content' => e.message,
      'conversation_id' => obj.dig('contents', 'conversation_id')
    })
  end

  # Flip an entry between an app-specific scope and "Global". The UI
  # sends the desired `scope_app` literal (e.g. "ChatOpenAI" or
  # "Global") in the payload.
  private def handle_ws_library_set_scope(connection, obj, _session)
    payload = obj['contents']
    payload = {} unless payload.is_a?(Hash)
    conv_id = payload['conversation_id'].to_s
    scope_app = payload['scope_app'].to_s.strip

    if conv_id.empty?
      send_to_client(connection, {
        'type' => 'library_scope_updated', 'res' => 'failure',
        'content' => 'Missing conversation_id'
      })
      return
    end
    if scope_app.empty?
      send_to_client(connection, {
        'type' => 'library_scope_updated', 'res' => 'failure',
        'content' => "scope_app must not be empty",
        'conversation_id' => conv_id
      })
      return
    end

    store = library_store_for_ws
    Monadic::Library::Manager.update_scope_app(
      store: store, conversation_id: conv_id, scope_app: scope_app
    )
    send_to_client(connection, {
      'type' => 'library_scope_updated', 'res' => 'success',
      'conversation_id' => conv_id, 'scope_app' => scope_app
    })
  rescue ArgumentError => e
    send_to_client(connection, {
      'type' => 'library_scope_updated', 'res' => 'failure',
      'content' => e.message, 'conversation_id' => obj.dig('contents', 'conversation_id')
    })
  rescue StandardError => e
    Monadic::Utils::ExtraLogger.log { "[Library] LIBRARY_SET_SCOPE failed: #{e.class}: #{e.message}" }
    send_to_client(connection, {
      'type' => 'library_scope_updated', 'res' => 'failure',
      'content' => e.message, 'conversation_id' => obj.dig('contents', 'conversation_id')
    })
  end

  private def handle_ws_library_save(connection, obj, _session)
    payload = obj['contents']
    payload = {} unless payload.is_a?(Hash)

    messages = payload['messages']
    parameters = payload['parameters']
    title = payload['title']
    license = payload['license']
    monadic_state = payload['monadic_state']
    # The UI sends the requested scope_app literally — either the
    # currently active app's class name (default for "save my session
    # privately to this app") or "Global" (default for shareable
    # knowledge artifacts). Fall back to the literal app_name from the
    # save parameters so the UI does not have to compute the value.
    scope_app = payload['scope_app'].to_s.strip
    if scope_app.empty? && parameters.is_a?(Hash)
      scope_app = parameters['app_name'].to_s.strip
    end
    scope_app = Monadic::Library::Store::SCOPE_GLOBAL if scope_app.empty?

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

    importer_input = { 'parameters' => parameters, 'messages' => messages }
    importer_input['monadic_state'] = monadic_state if monadic_state.is_a?(Hash)

    options = {}
    options[:title] = title.to_s unless title.to_s.empty?
    options[:license] = license.to_s unless license.to_s.empty?

    store = library_store_for_ws
    result = Monadic::Library::Manager.import_from_text(
      store: store, input: importer_input, options: options, scope_app: scope_app
    )
    send_to_client(connection, {
      'type' => 'library_saved', 'res' => 'success',
      'content' => "Conversation saved to Knowledge Base.",
      'conversation_id' => result[:conversation_id],
      'scope_app' => scope_app,
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
      'content' => { 'conversations_total' => 0, 'conversations_by_scope' => {} },
      'error' => e.message
    })
  end

  private def symbol_keys_to_strings(hash)
    hash.each_with_object({}) { |(k, v), out| out[k.to_s] = v }
  end
end
