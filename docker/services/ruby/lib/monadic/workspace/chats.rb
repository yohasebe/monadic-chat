# frozen_string_literal: true

require_relative 'ids'

module Monadic
  module Workspace
    # The chat a session is in. A chat is one run of conversation: Reset and
    # switching apps start a new one, while reloading the page or
    # reconnecting the same tab continues it. The id is issued here, on the
    # server, and is not the WebSocket tab id (a tab outlives many chats).
    #
    # Named "chat" because the Library already uses conversation_id for
    # saved knowledge-base entries, which are a different thing.
    module Chats
      SESSION_KEY = :chat_id

      module_function

      def current(session)
        id = session[SESSION_KEY]
        return id if Ids.valid?(:chat, id)

        start_new!(session)
      end

      def start_new!(session)
        session[SESSION_KEY] = Ids.generate(:chat)
      end

      # Continue the chat a reconnecting tab was in. Anything that is not an
      # id this server issued starts a new chat instead.
      def resume!(session, saved_id)
        if Ids.valid?(:chat, saved_id)
          session[SESSION_KEY] = saved_id
        else
          start_new!(session)
        end
      end
    end
  end
end
