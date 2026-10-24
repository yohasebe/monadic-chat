# frozen_string_literal: true

# The conversation history as the page uses it, over the tab's own
# WebSocket: the list, a name for a chat, removing one, and continuing one in
# this tab. Only this server's chat ids are taken, and the replies carry the
# list's headings, never a conversation, except to the tab that resumes it.
module WebSocketHelper
  HISTORY_PAGE = 50

  private def handle_ws_history_list(connection, obj)
    return send_history_off(connection, 'history_list') unless Monadic::History.enabled?

    offset = [obj['offset'].to_i, 0].max
    query = obj['query'].to_s[0, 200]
    items = Monadic::History.list(query: query, offset: offset, limit: HISTORY_PAGE + 1,
                                  open_chat_ids: WebSocketHelper.live_chat_ids)
    # The query comes back so the page can tell the sidebar's list from the panel's.
    send_to_client(connection, { 'type' => 'history_list', 'enabled' => true, 'offset' => offset, 'query' => query,
                                 'items' => items.first(HISTORY_PAGE), 'has_more' => items.length > HISTORY_PAGE })
  rescue StandardError => e
    send_history_error(connection, 'history_list', e)
  end

  private def handle_ws_history_rename(connection, obj)
    return send_history_off(connection, 'history_renamed') unless Monadic::History.enabled?

    chat_id = history_chat_id(obj)
    ok = chat_id && Monadic::History::Store.default.rename(chat_id, obj['title'])
    send_to_client(connection, { 'type' => 'history_renamed', 'chat_id' => chat_id, 'success' => ok ? true : false })
  rescue StandardError => e
    send_history_error(connection, 'history_renamed', e)
  end

  # A chat open in a tab is not removed: the tab would go on with it. The
  # chat is reserved while it is removed, so no tab takes it meanwhile.
  private def handle_ws_history_delete(connection, obj)
    return send_history_off(connection, 'history_deleted') unless Monadic::History.enabled?

    chat_id = history_chat_id(obj)
    reply = { 'type' => 'history_deleted', 'chat_id' => chat_id }
    if chat_id.nil?
      reply['success'] = false
      reply['error'] = 'history_not_found'
    elsif !WebSocketHelper.reserve_chat(chat_id)
      reply['success'] = false
      reply['error'] = 'history_chat_open'
    else
      begin
        Monadic::History::Store.default.delete(chat_id)
      ensure
        WebSocketHelper.release_chat(chat_id)
      end
      reply['success'] = true
    end
    send_to_client(connection, reply)
  rescue StandardError => e
    send_history_error(connection, 'history_deleted', e)
  end

  # Whether HISTORY_RESUME will replace this tab's chat, as nil (it will)
  # or the reason it will not. It will for a kept chat of this server that
  # is not the chat the tab is in and that no tab has open or is taking;
  # when the chat here is Private and has words in it (it is not in the
  # history, so it is gone once replaced), only once the user has confirmed.
  # When it will, the chat is reserved for this tab until the resume ends
  # (handle_ws_history_resume releases it), so the caller can stop what runs
  # for the current chat without another tab taking the chat meanwhile.
  private def history_resume_refusal(obj, session)
    return 'history_off' unless Monadic::History.enabled?

    chat_id = history_chat_id(obj)
    return 'history_not_found' unless chat_id
    return 'history_chat_here' if chat_id == session[Monadic::Workspace::Chats::SESSION_KEY]
    return 'history_private_here' if obj['confirm'] != true && private_words_here?(session)
    return 'history_chat_open' unless WebSocketHelper.reserve_chat(chat_id)

    kept = false
    begin
      kept = Monadic::History::Store.default.resumable?(chat_id)
    ensure
      WebSocketHelper.release_chat(chat_id) unless kept
    end
    kept ? nil : 'history_not_found'
  end

  private def private_words_here?(session)
    Monadic::History::Policy.private?(session) && user_words_in_chat?(session)
  end

  # Continues a chat from the history in this tab, under its own chat id:
  # the tab takes it over (the history keeps only this tab's writes of it),
  # and the page is sent what it shows, as for an imported conversation.
  # `refusal` is what history_resume_refusal gave; nil means the chat is
  # reserved for this tab.
  private def handle_ws_history_resume(connection, obj, session, refusal)
    chat_id = history_chat_id(obj)
    reply = { 'type' => 'history_resumed', 'chat_id' => chat_id }
    return send_to_client(connection, reply.merge('success' => false, 'error' => refusal)) if refusal

    begin
      row = Monadic::History::Store.default.claim(chat_id, tab: Thread.current[:websocket_session_id],
                                                           generation: session[:_ws_generation])
      return send_to_client(connection, reply.merge('success' => false, 'error' => 'history_not_found')) unless row

      stop_speech_for_new_chat(connection, session, 'History')
      put_history_chat(session, chat_id, row['payload'])
      sync_session_state!
    ensure
      WebSocketHelper.release_chat(chat_id)
    end
    send_chat_to_page(connection, session, restored: true)
    send_to_client(connection, reply.merge('success' => true))
  rescue StandardError => e
    send_history_error(connection, 'history_resumed', e)
  end

  # The kept chat in place of the tab's current one. Only what the history
  # keeps comes back; the app builds the rest (its tools, pipelines) anew.
  private def put_history_chat(session, chat_id, payload)
    ui_language = session[:parameters] && session[:parameters]['ui_language']
    session[:messages] = []
    session[:parameters] = {}
    Monadic::Workspace::Chats.clear_chat_state!(session)
    Monadic::Workspace::Chats.resume!(session, chat_id)

    params = (payload['parameters'] || {}).merge('initiate_from_assistant' => false, 'auto_speech' => false)
    params['ui_language'] ||= ui_language if ui_language
    session[:parameters] = params
    session[:messages] = Array(payload['messages']).map do |m|
      m.merge('html' => m['text'], 'active' => true, 'app_name' => m['app_name'] || params['app_name'])
    end
    context = payload['session_context']
    session[:monadic_state] = { conversation_context: context } if context.is_a?(Hash)
  end

  private def history_chat_id(obj)
    id = obj['chat_id'].to_s
    Monadic::Workspace::Ids.valid?(:chat, id) ? id : nil
  end

  private def send_history_off(connection, type)
    send_to_client(connection, { 'type' => type, 'enabled' => false, 'success' => false, 'error' => 'history_off', 'items' => [] })
  end

  # The kind of failure only: the message could carry a conversation's words.
  private def send_history_error(connection, type, error)
    Monadic::Utils::ExtraLogger.log { "[History] #{type} failed: #{error.class}" }
    send_to_client(connection, { 'type' => type, 'success' => false, 'error' => 'history_failed' })
  end
end
