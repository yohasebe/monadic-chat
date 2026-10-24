# frozen_string_literal: true

require_relative 'history/policy'
require_relative 'history/serializer'
require_relative 'history/store'

module Monadic
  # The conversation history, kept in the state folder. Off until it can be
  # seen and removed in the app: MONADIC_HISTORY=true in the shell that
  # starts the server turns it on (the config env file does not).
  module History
    module_function

    def enabled?
      ENV['MONADIC_HISTORY'] == 'true'
    end

    # Writes the chat in `session` to the history. A Private chat is never
    # written: what was kept of it before it became Private is removed and a
    # tombstone keeps any later copy of it out. A chat with no user words
    # left has its row removed. Returns the revision written, or nil.
    #
    # Called only for a session the tab's state accepted (not one from a
    # connection that a newer one replaced); the connection's generation is
    # checked again by the store, in the same transaction as the write.
    def record(session, store: Store.default)
      return nil unless enabled?

      chat_id = session[Monadic::Workspace::Chats::SESSION_KEY] || session[Monadic::Workspace::Chats::SESSION_KEY.to_s]
      return nil unless chat_id

      if Policy.private?(session)
        store.delete(chat_id)
        return nil
      end

      payload = Serializer.payload(session)
      unless payload
        store.clear(chat_id)
        return nil
      end

      params = payload['parameters'] || {}
      store.save(chat_id, payload, generation: session[:_ws_generation] || session['_ws_generation'],
                                   app_name: params['app_name'], model: params['model'],
                                   headings: Serializer.headings(payload))
    end
  end
end
