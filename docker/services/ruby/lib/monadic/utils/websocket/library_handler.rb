# frozen_string_literal: true

require 'monadic/library'
require_relative '../privacy/outbound'
require_relative '../../library/conversation_draft'
require_relative '../../library/desk_import'
require_relative '../../history/store'

# WebSocket handlers for the Library tab.
#
# Messages handled:
#   - LIBRARY_LIST          → 'library_conversations' (every entry, and their number)
#   - LIBRARY_CONVERSATION_DRAFT → 'library_conversation_draft' (the chat's record put on its work screen)
#   - LIBRARY_FROM_WORKBENCH → 'library_from_workbench' (a document of the work screen kept)
#   - LIBRARY_DELETE        → 'library_deleted'
#   - LIBRARY_RENAME        → 'library_renamed'
#   - LIBRARY_GET_CONVERSATION → 'library_conversation_data'
module WebSocketHelper
  private def library_store_for_ws
    Monadic::Library::Store.new
  end

  private def handle_ws_library_list(connection, _obj, _session)
    store = library_store_for_ws
    rows = Monadic::Library::Manager.list_conversations(store: store, limit: nil)
    resumable = {}
    content = rows.map { |r| symbol_keys_to_strings(with_source_chat(r, resumable)) }
    send_to_client(connection, {
      'type' => 'library_conversations',
      'content' => content,
      'total' => rows.size
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
      store: store, conversation_id: conv_id
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

  # The chat put on its work screen as a record to keep
  # (Library::ConversationDraft): kept in the Library only when the user
  # stores it from there.
  private def handle_ws_library_conversation_draft(connection, _obj, session)
    reply = { 'type' => 'library_conversation_draft' }
    if session.respond_to?(:key?) && Monadic::Utils::Privacy::Words.marked?(session)
      return send_to_client(connection, reply.merge('error' => 'hides_words'))
    end

    tab, generation = workbench_connection(session).values_at(:tab, :generation)
    item_id = Monadic::Library::ConversationDraft.put(session, tab: tab, generation: generation, live: WORKBENCH_LIVE)
    Monadic::Workbench::Channel.changed(session[Monadic::Workspace::Chats::SESSION_KEY])
    send_to_client(connection, reply.merge('item_id' => item_id))
  rescue Monadic::Library::ConversationDraft::Refused => e
    send_to_client(connection, reply.merge('error' => e.message))
  rescue StandardError => e
    Monadic::Utils::ExtraLogger.log { "[Library] No conversation record put: #{e.class}" }
    send_to_client(connection, reply.merge('error' => 'failed'))
  end

  # A document of the work screen kept in the Library (Library::DeskImport),
  # as the version the tab shows; the page follows the import by its id
  # (/library/import/status/:id). Not from a chat that hides words.
  private def handle_ws_library_from_workbench(connection, obj, session)
    reply = { 'type' => 'library_from_workbench', 'item_id' => obj['item_id'].to_s }
    if session.respond_to?(:key?) && Monadic::Utils::Privacy::Words.marked?(session)
      return send_to_client(connection, reply.merge('error' => 'hides_words'))
    end

    tab, generation = workbench_connection(session).values_at(:tab, :generation)
    chat_id = session[Monadic::Workspace::Chats::SESSION_KEY]
    board = chat_id && WORKBENCH_LIVE.call(tab) == generation && Monadic::Workbench::Board.existing(chat_id)
    return send_to_client(connection, reply.merge('error' => 'not_allowed')) unless board

    choice = obj['choice']
    choice = nil unless choice == 'new' || (choice.is_a?(Hash) && choice['update'].is_a?(String))
    title = obj['title'].is_a?(String) ? obj['title'] : nil
    import_id = Monadic::Library::DeskImport.start(board, obj['item_id'].to_s, obj['sha256'].to_s,
                                                   app_name: (session[:parameters] || {})['app_name'],
                                                   title: title, choice: choice)
    send_to_client(connection, reply.merge('import_id' => import_id, 'status_url' => "/library/import/status/#{import_id}"))
  rescue Monadic::Library::DeskImport::Choose => e
    records = e.records.map { |r| { 'id' => r[:conversation_id], 'title' => r[:title], 'created_at' => r[:created_at] } }
    send_to_client(connection, reply.merge('error' => 'choose', 'records' => records))
  rescue Monadic::Library::DeskImport::Refused => e
    send_to_client(connection, reply.merge('error' => e.message))
  rescue Monadic::Workbench::Artifact::Changed
    send_to_client(connection, reply.merge('error' => 'changed'))
  rescue Monadic::Workbench::Artifact::Missing, Monadic::Workbench::Artifact::NotAllowed
    send_to_client(connection, reply.merge('error' => 'missing'))
  rescue StandardError => e
    Monadic::Utils::ExtraLogger.log { "[Library] Not stored from the work screen: #{e.class}" }
    send_to_client(connection, reply.merge('error' => 'failed'))
  end

  # A record of a chat says whether that chat can be continued from the
  # history (source_chat_resumable); the chat's id is not given otherwise.
  # known: the answers for this list, by chat.
  private def with_source_chat(row, known)
    chat_id = row.delete(:source_chat_id)
    return row unless chat_id

    resumable = known.fetch(chat_id) do
      known[chat_id] = begin
        Monadic::History::Store.default.resumable?(chat_id)
      rescue StandardError
        false
      end
    end
    resumable ? row.merge(source_chat_id: chat_id, source_chat_resumable: true) : row
  end

  private def symbol_keys_to_strings(hash)
    hash.each_with_object({}) { |(k, v), out| out[k.to_s] = v }
  end
end
