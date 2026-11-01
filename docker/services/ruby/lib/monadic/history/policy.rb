# frozen_string_literal: true

module Monadic
  module History
    # Whether a chat may be kept in the history. A Private chat is never
    # written: not its text, title, context or anything else of it.
    #
    # The decision is the server's and stays for the chat. It does not follow
    # the Privacy Filter's health: a filter that is down or switched off does
    # not make a chat that used it a normal one. Asking for the Privacy
    # Filter marks the chat Private at once (whether or not the filter is
    # up), and a chat with any other trace of it (words were marked, a
    # registry or a pipeline was built) is Private too.
    #
    # The ids of Private chats are also known to this process (in memory
    # only), so work started for a Private chat (a reply, a tool, a thread
    # it started) is known as such even after the tab moved to a new chat.
    module Policy
      SESSION_KEY = :_history_policy
      PRIVATE = 'private'
      # Set once the chat has a message (Start Session adds the system
      # prompt) and kept for the rest of the chat, also when its messages
      # are removed: what it held before (the Session Context, tool
      # results) may still be in the session.
      BEGUN_KEY = :_chat_begun
      KNOWN_LIMIT = 10_000

      @known = {}
      @known_lock = Mutex.new

      module_function

      def private?(session)
        return true if stored(session) == PRIVATE
        return false unless privacy_traces?(session)

        # Kept for the rest of the chat; a new chat drops it (it is not one of
        # the keys Workspace::Chats keeps across chats).
        mark_private!(session)
        true
      end

      def mark_private!(session)
        session[SESSION_KEY] = PRIVATE
        remember(session[Monadic::Workspace::Chats::SESSION_KEY] || session[Monadic::Workspace::Chats::SESSION_KEY.to_s])
      end

      # The chat is a normal one again: only for a chat that has not begun
      # (nothing of it was written while it was Private).
      def clear!(session)
        session.delete(SESSION_KEY)
        session.delete(SESSION_KEY.to_s)
        id = session[Monadic::Workspace::Chats::SESSION_KEY] || session[Monadic::Workspace::Chats::SESSION_KEY.to_s]
        @known_lock.synchronize { @known.delete(id) } if id
      end

      def known_private?(chat_id)
        return false unless chat_id

        @known_lock.synchronize { @known.key?(chat_id) }
      end

      # Whether what runs now is for a Private chat: the chat the work was
      # started in (as EgressGuard keeps it for the threads and fibers it
      # starts), or the tab's session. Errs to Private when either is, and
      # when it cannot tell.
      def current_work_private?
        # No chats in this process (a script, the app starting): not a chat's work.
        return false unless defined?(Monadic::Workspace::Chats::SESSION_KEY)

        key = defined?(Monadic::Utils::Privacy::EgressGuard::CHAT_KEY) ? Monadic::Utils::Privacy::EgressGuard::CHAT_KEY : nil
        scope = key && Fiber[key]
        sessions = [scope&.session, Thread.current[:rack_session]].compact
        ids = [scope&.chat_id] + sessions.map { |s| s[Monadic::Workspace::Chats::SESSION_KEY] }
        sessions.any? { |s| stored(s) == PRIVATE } || ids.compact.any? { |id| known_private?(id) }
      rescue StandardError
        true
      end

      def remember(chat_id)
        return unless chat_id

        @known_lock.synchronize do
          @known[chat_id] = true
          @known.shift while @known.size > KNOWN_LIMIT
        end
      end

      def note_begun!(session)
        session[BEGUN_KEY] = true unless Array(session[:messages] || session['messages']).empty?
      end

      def begun?(session)
        session[BEGUN_KEY] == true || session[BEGUN_KEY.to_s] == true ||
          !Array(session[:messages] || session['messages']).empty?
      end

      def stored(session)
        session[SESSION_KEY] || session[SESSION_KEY.to_s]
      end

      def privacy_traces?(session)
        return true if session[:_privacy_session_enabled] == true || session['_privacy_session_enabled'] == true
        return true if session[:_privacy_pipeline] || session['_privacy_pipeline']

        state = session[:monadic_state] || session['monadic_state']
        privacy = state.is_a?(Hash) ? (state[:privacy] || state['privacy']) : nil
        return false unless privacy.is_a?(Hash)

        %i[terms registry].any? do |key|
          value = privacy[key] || privacy[key.to_s]
          value.respond_to?(:empty?) && !value.empty?
        end
      end
    end
  end
end
