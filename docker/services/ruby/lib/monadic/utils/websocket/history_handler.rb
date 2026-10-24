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
    items = Monadic::History.list(query: obj['query'].to_s[0, 200], offset: offset, limit: HISTORY_PAGE + 1,
                                  open_chat_ids: WebSocketHelper.live_chat_ids)
    send_to_client(connection, { 'type' => 'history_list', 'enabled' => true, 'offset' => offset,
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

  # A chat open in a tab is not removed: the tab would go on with it.
  private def handle_ws_history_delete(connection, obj)
    return send_history_off(connection, 'history_deleted') unless Monadic::History.enabled?

    chat_id = history_chat_id(obj)
    reply = { 'type' => 'history_deleted', 'chat_id' => chat_id }
    if chat_id.nil?
      reply.merge!('success' => false, 'error' => 'history_not_found')
    elsif WebSocketHelper.live_chat_ids.include?(chat_id)
      reply.merge!('success' => false, 'error' => 'history_chat_open')
    else
      Monadic::History::Store.default.delete(chat_id)
      reply['success'] = true
    end
    send_to_client(connection, reply)
  rescue StandardError => e
    send_history_error(connection, 'history_deleted', e)
  end

  # Whether HISTORY_RESUME will replace this tab's chat (the caller stops
  # what runs for the current one only then): an id of this server, not the
  # chat the tab is in, and not one open in another tab.
  private def history_resumable?(obj, session)
    return false unless Monadic::History.enabled?

    chat_id = history_chat_id(obj)
    chat_id && chat_id != session[Monadic::Workspace::Chats::SESSION_KEY] &&
      !WebSocketHelper.live_chat_ids.include?(chat_id)
  end

  # Continues a chat from the history in this tab, under its own chat id:
  # the tab takes it over (the history keeps only this tab's writes of it),
  # and the page is sent what it shows, as for an imported conversation.
  private def handle_ws_history_resume(connection, obj, session, resumable)
    chat_id = history_chat_id(obj)
    reply = { 'type' => 'history_resumed', 'chat_id' => chat_id }
    unless resumable
      error = if !Monadic::History.enabled? then 'history_off'
              elsif chat_id && chat_id == session[Monadic::Workspace::Chats::SESSION_KEY] then 'history_chat_here'
              elsif chat_id && WebSocketHelper.live_chat_ids.include?(chat_id) then 'history_chat_open'
              else 'history_not_found'
              end
      return send_to_client(connection, reply.merge('success' => false, 'error' => error))
    end

    row = Monadic::History::Store.default.claim(chat_id, tab: Thread.current[:websocket_session_id],
                                                         generation: session[:_ws_generation])
    return send_to_client(connection, reply.merge('success' => false, 'error' => 'history_not_found')) unless row

    stop_speech_for_new_chat(connection, session, 'History')
    put_history_chat(session, chat_id, row['payload'])
    sync_session_state!
    send_chat_to_page(connection, session)
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
    send_to_client(connection, { 'type' => type, 'enabled' => false, 'success' => false, 'error' => 'history_off' })
  end

  # The kind of failure only: the message could carry a conversation's words.
  private def send_history_error(connection, type, error)
    Monadic::Utils::ExtraLogger.log { "[History] #{type} failed: #{error.class}" }
    send_to_client(connection, { 'type' => type, 'success' => false, 'error' => 'history_failed' })
  end
end
