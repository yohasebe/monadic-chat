# frozen_string_literal: true

require 'monadic/library'
require_relative '../privacy/outbound'
require_relative '../../library/conversation_record'
require_relative '../../library/desk_import'

# WebSocket handlers for the Library (Knowledge Base) panel.
#
# Messages handled:
#   - LIBRARY_LIST          → 'library_conversations' (full inventory)
#   - LIBRARY_DELETE        → 'library_deleted'
#   - LIBRARY_STATS         → 'library_stats' (the number of entries)
#   - LIBRARY_SAVE          → 'library_saved' (ingest current session)
#   - LIBRARY_RENAME        → 'library_renamed'
#   - LIBRARY_GET_CONVERSATION → 'library_conversation_data'
module WebSocketHelper
  private def library_store_for_ws
    Monadic::Library::Store.new
  end

  private def handle_ws_library_list(connection, _obj, _session)
    store = library_store_for_ws
    rows = Monadic::Library::Manager.list_conversations(store: store, limit: 500)
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

  # After the new version of a conversation is written, deletes the prior
  # version's points. The new version is kept whatever happens here: a
  # delete that failed may still have been applied, so taking the new
  # version out could leave nothing. Returns true when some prior points
  # may remain (the reply then carries a warning).
  private def prior_version_left?(store, prior_ids)
    store.delete_point_ids(prior_ids)
    false
  rescue StandardError => e
    Monadic::Utils::ExtraLogger.log { "[Library] prior version not fully removed: #{e.class}: #{e.message}" }
    true
  end

  # The chat as a document to keep (Library::ConversationRecord), for the
  # page to put on the work screen as a draft: kept in the Library only when
  # the user stores it from there. Not for a chat that hides words.
  private def handle_ws_library_conversation_draft(connection, _obj, session)
    reply = { 'type' => 'library_conversation_draft' }
    if session.respond_to?(:key?) && Monadic::Utils::Privacy::Words.marked?(session)
      return send_to_client(connection, reply.merge('error' => 'hides_words'))
    end

    params = session[:parameters] || {}
    record = Monadic::Library::ConversationRecord.of(session[:messages], app_name: params['app_name'], model: params['model'])
    return send_to_client(connection, reply.merge('error' => 'empty')) unless record

    send_to_client(connection, reply.merge('name' => record[:name], 'content' => record[:content]))
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

    import_id = Monadic::Library::DeskImport.start(board, obj['item_id'].to_s, obj['sha256'].to_s)
    send_to_client(connection, reply.merge('import_id' => import_id, 'status_url' => "/library/import/status/#{import_id}"))
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

  private def handle_ws_library_save(connection, obj, session)
    # A chat that hides words is not saved: the Knowledge Base would keep its
    # words, and a search from another chat would send them unhidden. The
    # page disables Save for it; this refuses a stale tab or another client
    # before anything is stored. The session of a real chat is a Rack session
    # object, not a Hash: read it by key.
    if session.respond_to?(:key?) && Monadic::Utils::Privacy::Words.marked?(session)
      Monadic::Utils::ExtraLogger.log { "[Library] LIBRARY_SAVE rejected: the chat hides words" }
      send_to_client(connection, {
        'type' => 'library_saved', 'res' => 'failure',
        'content' => 'A chat that hides words cannot be saved to the Knowledge Base. ' \
                     'Export the conversation to keep it.'
      })
      return
    end

    payload = obj['contents']
    payload = {} unless payload.is_a?(Hash)

    messages = payload['messages']
    parameters = payload['parameters']
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
    # Defense in depth #2: artifact apps (e.g. AutoForge, Drawio Grapher,
    # Image Generator) declare `library_save false` in their MDSL features
    # block because their output is not conversation-shaped. The frontend
    # hides the Save button (and the entire Library panel) for these apps,
    # but a stale tab or programmatic client could still hit this path.
    # Reject the save before any storage side-effect.
    candidate_app_name = parameters.is_a?(Hash) ? parameters['app_name'].to_s.strip : ''
    if !candidate_app_name.empty? && defined?(MonadicApp)
      app_obj = MonadicApp.app_settings(candidate_app_name)
      if app_obj.respond_to?(:settings) && app_obj.settings[:library_save] == false
        Monadic::Utils::ExtraLogger.log { "[Library] LIBRARY_SAVE rejected: app '#{candidate_app_name}' has library_save=false" }
        send_to_client(connection, {
          'type' => 'library_saved', 'res' => 'failure',
          'content' => "Knowledge Base save is not supported for #{candidate_app_name}. Switch to a conversational app to save."
        })
        return
      end
    end

    unless parameters.is_a?(Hash)
      send_to_client(connection, {
        'type' => 'library_saved', 'res' => 'failure',
        'content' => 'Missing parameters'
      })
      return
    end

    # Verify-button results are session-only annotations ABOUT an answer, not
    # knowledge — strip them so a persisted verdict never pollutes KB embeddings
    # or semantic search (defense in depth; the client also keeps them off the
    # save payload).
    messages = messages.map { |m| m.is_a?(Hash) ? m.reject { |k, _| k == 'verify' } : m }

    importer_input = { 'parameters' => parameters, 'messages' => messages }
    importer_input['monadic_state'] = monadic_state if monadic_state.is_a?(Hash)

    options = {}
    options[:title] = title.to_s unless title.to_s.empty?
    options[:license] = license.to_s unless license.to_s.empty?

    # When the UI is re-saving a conversation it keeps a hold of the
    # original conversation_id and sends it back on subsequent saves so
    # we update-in-place instead of duplicating the entry. Without this
    # the KB would accumulate every snapshot of an in-progress chat.
    existing_id = payload['conversation_id'].to_s.strip
    existing_id = nil if existing_id.empty?
    options[:conversation_id] = existing_id if existing_id

    store = library_store_for_ws

    # The new version is written first and the prior version's points are
    # deleted after it, by id, so a failed save leaves the entry as it was.
    # An unknown id has no points, so this is safe even when the UI is
    # racing against an external delete.
    prior_ids = existing_id ? store.point_ids(existing_id) : nil

    result = Monadic::Library::Manager.import_from_text(
      store: store, input: importer_input, options: options
    )
    leftover = prior_ids ? prior_version_left?(store, prior_ids) : false
    send_to_client(connection, {
      'type' => 'library_saved', 'res' => 'success',
      'content' => existing_id ? 'Updated conversation in Knowledge Base.' : 'Conversation saved to Knowledge Base.',
      'conversation_id' => result[:conversation_id],
      'updated' => !existing_id.nil?,
      'counts' => result[:counts].each_with_object({}) { |(k, v), h| h[k.to_s] = v }
    }.tap { |reply| reply['warning'] = 'prior_version_left' if leftover })
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

  # Best-effort: ask the user's currently active provider for a concise
  # title to seed the Save modal with. This runs the LLM out-of-band
  # from the main chat (a separate one-shot send_query) and the result
  # only seeds the title field — the user can always overwrite it
  # before clicking Save. Failure cases (no API key / unknown provider /
  # LLM error) are reported with res=failure so the UI can clear its
  # spinner without surfacing a confusing error to the user.
  private def handle_ws_library_suggest_title(connection, obj, session)
    payload = obj['contents']
    payload = {} unless payload.is_a?(Hash)
    messages = payload['messages']
    unless messages.is_a?(Array) && !messages.empty?
      send_to_client(connection, { 'type' => 'library_title_suggested', 'res' => 'failure' })
      return
    end

    params = (session && (session[:parameters] || session['parameters'])) || {}
    app_name = (params['app_name'] || params[:app_name]).to_s
    # A chat with a word table hides its words in the suggestion request, so
    # the title does not bring them back unhidden.
    words = nil
    begin
      require_relative '../privacy/words'
      words = Monadic::Utils::Privacy::Words.table(session) if session
      Monadic::Utils::Privacy::Outbound.chat_session!(session) unless words
    rescue Monadic::Utils::Privacy::Outbound::Refused => e
      send_to_client(connection, { 'type' => 'library_title_suggested', 'res' => 'failure',
                                   'content' => "No title was suggested: #{e.message}." })
      return
    end
    title = Monadic::Library::TitleSuggester.suggest(
      messages: messages,
      app_name: app_name,
      session: session,
      words: words
    )

    send_to_client(connection, {
      'type' => 'library_title_suggested',
      'res' => title ? 'success' : 'failure',
      'title' => title
    })
  rescue StandardError => e
    Monadic::Utils::ExtraLogger.log { "[Library] LIBRARY_SUGGEST_TITLE failed: #{e.class}: #{e.message}" }
    send_to_client(connection, { 'type' => 'library_title_suggested', 'res' => 'failure' })
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
      'content' => { 'conversations_total' => 0 },
      'error' => e.message
    })
  end

  private def symbol_keys_to_strings(hash)
    hash.each_with_object({}) { |(k, v), out| out[k.to_s] = v }
  end
end
