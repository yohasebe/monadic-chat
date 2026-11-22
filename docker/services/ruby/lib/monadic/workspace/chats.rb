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

      # Session keys that belong to the tab or the connection, not to a chat.
      # Every other key is something a chat left behind (a tool's last image
      # or notebook, a privacy registry, a plan, retry counters) and is
      # dropped when a new chat begins, so none of it reaches the next chat.
      # A key added later is dropped by default; one that must outlive the
      # chat is added here. The speech bridges are kept because their owners
      # tear them down (dropping the key would leave the socket open). The
      # session middleware's own keys are kept as well.
      #
      # Compared as strings: the session of a real request stores every key
      # as a string (session[:foo] is kept as "foo"), while a Hash given in
      # place of a session keeps symbols.
      KEPT_KEYS = %w[
        messages parameters runtime_settings
        websocket_session_id session_id version docker _ws_generation
        _sts _realtime_stt
        csrf tracking
      ].freeze

      # Told when a chat ends (its state is about to be dropped), when a
      # session's chat id is set, and when the user replaces the chat with
      # another, as on_change { |event, session| ... } with :ending, :started
      # or :replaced. Something that follows the chat (the check of what is
      # sent for it) keeps up this way, whoever ends or starts it. :ending
      # also comes when a connection drops the state a tab left, which the
      # tab may then resume; only :replaced means the chat is left for good
      # (Reset, another app, an import, another chat from the history).
      LISTENERS = []

      # How many times each chat was replaced. Work keeps the epoch its chat
      # was in when the work began (EgressGuard::Scope), so work of a chat
      # the user left is told apart from work after the same chat comes
      # back (a chat continued from the history). Kept for good: one integer
      # per chat replaced.
      EPOCHS = Hash.new(0)
      EPOCHS_LOCK = Mutex.new

      module_function

      def epoch(chat_id)
        EPOCHS_LOCK.synchronize { EPOCHS[chat_id] }
      end

      # The chat work is done for, { id:, epoch: }: the one the reply or the
      # thread began for (the scope it runs under, Privacy::EgressGuard),
      # or else the session's chat now. nil without a chat.
      def work_chat(session)
        scope = Fiber[Monadic::Utils::Privacy::EgressGuard::CHAT_KEY] if defined?(Monadic::Utils::Privacy::EgressGuard)
        return { id: scope.chat_id, epoch: scope.epoch } if scope&.chat_id && scope.epoch

        chat_id = session && session[SESSION_KEY]
        chat_id ? { id: chat_id, epoch: epoch(chat_id) } : nil
      end

      # Runs the block while chat_id is at epoch, under the lock that ends an
      # epoch: either the chat was left first and the block is not run
      # (nil), or the block comes first and leaving waits for it. The block
      # is a decision, or a write of the chat's own data in memory (its
      # context); nothing is sent or saved in it, and a lock it takes is
      # never held by what waits for this one.
      def admit_in_epoch(chat_id, epoch)
        EPOCHS_LOCK.synchronize { EPOCHS[chat_id] == epoch ? yield : nil }
      end

      def on_change(&block)
        LISTENERS << block unless LISTENERS.include?(block)
      end

      def notify(event, session)
        LISTENERS.each { |listener| listener.call(event, session) }
      end

      def current(session)
        id = session[SESSION_KEY]
        return id if Ids.valid?(:chat, id)

        start_new!(session)
      end

      def start_new!(session)
        session[SESSION_KEY] = Ids.generate(:chat)
        notify(:started, session)
        session[SESSION_KEY]
      end

      # A new chat (Reset, another app, an imported conversation): drop what
      # the previous chat left, then give the session a new chat id. The
      # messages and parameters are left to the caller, which knows whether
      # they are cleared, kept or replaced.
      def begin_new!(session)
        replacing!(session)
        clear_chat_state!(session)
        start_new!(session)
      end

      # The user leaves the session's chat for another: the chat's epoch ends.
      def replacing!(session)
        chat_id = session[SESSION_KEY]
        return unless chat_id

        EPOCHS_LOCK.synchronize { EPOCHS[chat_id] += 1 }
        notify(:replaced, session)
      end

      # Work begun for the chat before is of an earlier epoch from now on:
      # the chat is continued in a tab from the history, or no tab keeps it
      # any more. With from:, only while the chat is still at that epoch
      # (false when it was not).
      def renew_epoch!(chat_id, from: nil)
        EPOCHS_LOCK.synchronize do
          next false if from && EPOCHS[chat_id] != from

          EPOCHS[chat_id] += 1
          true
        end
      end

      # Drops every key that is not kept for the tab or the connection,
      # the chat id included.
      def clear_chat_state!(session)
        notify(:ending, session) if session[SESSION_KEY]
        # The chat id goes first: while it is still there, nothing of the
        # chat has been dropped (what checks a chat's words relies on this).
        session.delete(SESSION_KEY)
        session.delete(SESSION_KEY.to_s)
        session.keys.each do |key|
          session.delete(key) unless KEPT_KEYS.include?(key.to_s)
        end
      end

      # Objects built for one connection's session (they hold that session
      # inside): a reconnecting tab builds its own again when it needs them.
      RUNTIME_KEYS = %w[_privacy_pipeline _substitution_pipeline].freeze

      # The rest of the chat's session, beside its messages and parameters,
      # as the tab keeps it between connections: data only. Keyed by symbol,
      # as the code reads it: a real session gives its keys as strings, and
      # the saved copy is also read as a plain Hash while the tab is away.
      def chat_state(session)
        session.keys.each_with_object({}) do |key, state|
          name = key.to_s
          next if KEPT_KEYS.include?(name) || name == SESSION_KEY.to_s || RUNTIME_KEYS.include?(name)

          state[name.to_sym] = session[key]
        end
      end

      # Continue the chat a reconnecting tab was in. Anything that is not an
      # id this server issued starts a new chat instead.
      def resume!(session, saved_id)
        if Ids.valid?(:chat, saved_id)
          session[SESSION_KEY] = saved_id
          notify(:started, session)
          saved_id
        else
          start_new!(session)
        end
      end
    end
  end
end
