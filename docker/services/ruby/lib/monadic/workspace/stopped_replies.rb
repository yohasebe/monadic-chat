# frozen_string_literal: true

module Monadic
  module Workspace
    # Requests whose reply was stopped (Cancel, Reset, another app, a
    # closed connection) before it was recorded. A stop is recorded here
    # the moment it takes, apart from any connection's copy of the chat, so
    # that whatever next builds a request for the chat (a new connection of
    # the tab included) marks the user's message ("reply_stopped") and the
    # model is told of it. Marks are not taken back out: applying them again
    # changes nothing. This is a hand-over kept in memory: records go when
    # a chat holds more than PER_CHAT, or past CHATS chats (the chat whose
    # last stop was noted longest ago first), and at a restart.
    module StoppedReplies
      PER_CHAT = 50
      CHATS = 200
      MARK = 'reply_stopped'
      NOTE = '[The reply to this message was stopped before completion. Do not resume this request ' \
             'or repeat its tools unless the user asks again. Earlier tool actions may already have taken effect.]'

      @chats = {}
      @lock = Mutex.new

      class << self
        def record(chat_id, request_id)
          return unless chat_id && request_id

          @lock.synchronize do
            ids = @chats.delete(chat_id) || []
            ids << request_id unless ids.include?(request_id)
            ids.shift while ids.size > PER_CHAT
            @chats[chat_id] = ids
            @chats.shift while @chats.size > CHATS
          end
        end

        def recorded?(chat_id, request_id)
          @lock.synchronize { @chats[chat_id]&.include?(request_id) || false }
        end

        # Marks the user's messages of session's chat whose reply was
        # stopped. True when one was newly marked: a compacted history made
        # before (Grok) may hold it unmarked, so it is dropped.
        def apply!(session)
          chat_id = session[Chats::SESSION_KEY]
          ids = @lock.synchronize { @chats[chat_id]&.dup } if chat_id
          return false if ids.nil? || ids.empty?

          marked = false
          Array(session[:messages]).each do |msg|
            next unless msg.is_a?(Hash) && msg['role'] == 'user' && ids.include?(msg['request_id'])
            next if msg[MARK] == true

            msg[MARK] = true
            marked = true
          end
          session.delete(:grok_compaction) if marked
          marked
        end

        # The line the model reads after a message whose reply was stopped,
        # or nil.
        def note_for(msg)
          NOTE if msg.is_a?(Hash) && msg['role'] == 'user' && msg[MARK] == true
        end

        # The text the model reads for msg: its own, then the line.
        def with_note(msg, text)
          note = note_for(msg)
          return text unless note

          [text.to_s, note].reject(&:empty?).join("\n\n")
        end

        def reset!
          @lock.synchronize { @chats.clear }
        end
      end
    end
  end
end
