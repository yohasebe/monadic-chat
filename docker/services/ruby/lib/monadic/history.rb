# frozen_string_literal: true

require_relative 'history/policy'
require_relative 'history/serializer'
require_relative 'history/store'

module Monadic
  # The conversation history, kept in the state folder. MONADIC_HISTORY=false
  # in the shell that starts the server turns it off (the config env file
  # does not).
  module History
    module_function

    def enabled?
      ENV['MONADIC_HISTORY'] != 'false'
    end

    # Writes the chat in `session` to the history. A Private chat is never
    # written, and the history file is not even made for it: the chat is
    # Private before it begins, and this process remembers its id (in
    # memory), which keeps out a later copy of it that lacks the mark. If a
    # row of it is there anyway, it is removed. A chat with no user words
    # left has its row removed. Returns the revision written, or nil.
    #
    # Called only for a session the tab's state accepted (not one from a
    # connection that a newer one replaced); the connection's generation is
    # checked again by the store, in the same transaction as the write.
    def record(session, tab: nil, store: Store.default)
      return nil unless enabled?

      chat_id = session[Monadic::Workspace::Chats::SESSION_KEY] || session[Monadic::Workspace::Chats::SESSION_KEY.to_s]
      return nil unless chat_id

      generation = session[:_ws_generation] || session['_ws_generation']
      if Policy.private?(session) || Policy.known_private?(chat_id)
        store.clear(chat_id, tab: tab, generation: generation)
        return nil
      end

      payload = Serializer.payload(session)
      unless payload
        store.clear(chat_id, tab: tab, generation: generation)
        return nil
      end

      params = payload['parameters'] || {}
      store.save(chat_id, payload, tab: tab, generation: generation,
                                   app_name: params['app_name'], model: params['model'],
                                   headings: Serializer.headings(payload), search_text: Serializer.search_text(payload))
    end

    # The list as the page shows it, with whether each chat is open in a tab
    # now. Nothing of the conversations themselves.
    def list(query: nil, offset: 0, limit: 50, open_chat_ids: [], store: Store.default)
      open = open_chat_ids.to_a
      store.list(limit: limit, offset: offset, query: query).map do |row|
        row.merge('open' => open.include?(row['chat_id']))
      end
    end
  end
end
