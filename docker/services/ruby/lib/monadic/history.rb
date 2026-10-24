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

    # Writes the chat in `session` to the history, or, for a Private chat,
    # removes anything of it that was written before it became Private.
    # Returns the revision written, or nil.
    def record(session, store: Store.default)
      return nil unless enabled?

      chat_id = session[Monadic::Workspace::Chats::SESSION_KEY] || session[Monadic::Workspace::Chats::SESSION_KEY.to_s]
      return nil unless chat_id

      if Policy.private?(session)
        store.delete(chat_id) if store.get(chat_id)
        return nil
      end

      payload = Serializer.payload(session)
      return nil unless payload

      params = payload['parameters'] || {}
      store.save(chat_id, payload, app_name: params['app_name'], model: params['model'],
                                   headings: Serializer.headings(payload))
    end
  end
end
