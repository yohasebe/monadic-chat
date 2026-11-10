# frozen_string_literal: true

require 'json'
require_relative 'chats'

module Monadic
  module Workspace
    # The context a chat keeps, as its context panel shows it: the turn
    # count ("_turn_count") and, for each field, the items with their text,
    # the turn they came from and whether they were re-extracted after an
    # edit ({ "text", "turn", "edited" }).
    #
    # Kept by chat id, not in the session: a session is copied for a thread
    # and for the tab between connections, while work that ends late (an
    # extraction, a tool) writes to the chat it was done for, never to the
    # chat a session is in by then. Every change goes through update, which
    # writes only while that chat is at the epoch the work began in, and
    # numbers the change, so the page can tell an older context from a
    # newer one of the same chat. Each change is written to the chat's
    # saved conversation too (Monadic::History.keep_context).
    #
    # A chat's context is kept here while the chat is open in a tab or a
    # tab keeps it to come back to (WebSocketHelper's saved state), and
    # until the chat is left for good; the history keeps what was saved.
    module ChatContext
      TURN_KEY = '_turn_count'
      STORE = {}
      # Contexts of chats no tab keeps any more, being saved (retire).
      RETIRING = {}
      # Taken before Chats' epoch lock, never after it.
      LOCK = Mutex.new

      # A change made: the context after it, its version, and the chat and
      # epoch it was made in.
      Change = Struct.new(:context, :version, :chat_id, :epoch) do
        def token
          ChatContext.token(chat_id, epoch)
        end
      end

      module_function

      # What the page matches a context against: the chat and its epoch.
      def token(chat_id, epoch)
        "#{chat_id}.#{epoch}"
      end

      # The chat work is done for, { id:, epoch: }: the one the reply or the
      # thread began for (the scope it runs under, Privacy::EgressGuard),
      # or else the session's chat now. nil without a chat.
      def work_chat(session)
        scope = Fiber[Monadic::Utils::Privacy::EgressGuard::CHAT_KEY] if defined?(Monadic::Utils::Privacy::EgressGuard)
        return { id: scope.chat_id, epoch: scope.epoch } if scope&.chat_id && scope.epoch

        chat_id = session && session[Chats::SESSION_KEY]
        chat_id ? { id: chat_id, epoch: Chats.epoch(chat_id) } : nil
      end

      # The chat's context (a copy), or nil when it has none.
      def read(session)
        chat_id = session && session[Chats::SESSION_KEY]
        return nil unless chat_id

        LOCK.synchronize { copy(STORE[chat_id]&.dig(:context)) }
      end

      # The chat's context and version now, as a Change (an empty context
      # for a chat that has none), for the page entering the chat.
      def current(session)
        chat_id = session && session[Chats::SESSION_KEY]
        return nil unless chat_id

        epoch = Chats.epoch(chat_id)
        entry = LOCK.synchronize { STORE[chat_id] && { context: copy(STORE[chat_id][:context]), version: STORE[chat_id][:version] } }
        Change.new(entry&.dig(:context) || {}, entry&.dig(:version) || 0, chat_id, epoch)
      end

      # Changes the context of the chat the work is done for (chat: as
      # work_chat gives it). The block is given the context now (a copy, or
      # nil) and returns the new one; it computes only (it is run under the
      # locks that keep the chat from being left meanwhile). nil when the
      # chat was left or the block returned no Hash.
      def update(session, chat: work_chat(session))
        return nil unless chat

        change = LOCK.synchronize do
          Chats.admit_in_epoch(chat[:id], chat[:epoch]) do
            entry = STORE[chat[:id]] || { context: nil, version: 0 }
            changed = yield(copy(entry[:context]))
            next nil unless changed.is_a?(Hash)

            # The context it had stays until the new one is made in full.
            kept = copy(changed)
            STORE[chat[:id]] = { context: kept, version: entry[:version] + 1 }
            Change.new(copy(kept), entry[:version] + 1, chat[:id], chat[:epoch])
          end
        end
        keep_in_history(chat[:id], session) if change
        change
      end

      # The chat's saved conversation is given its context now (held: what
      # gives the context to save, when it is not the one the chat holds).
      # Nothing is saved where the history is not loaded.
      def keep_in_history(chat_id, session, held: nil)
        return unless chat_id && defined?(Monadic::History) && Monadic::History.respond_to?(:keep_context)

        Monadic::History.keep_context(chat_id, session: session, held: held)
      end

      # Puts a context in place for the chat the session has just begun from
      # a file. A context of an older shape is read as the panel's.
      def restore!(session, context)
        chat_id = session[Chats::SESSION_KEY]
        return unless chat_id

        normalized = normalize(context)
        LOCK.synchronize do
          STORE.delete(chat_id)
          next unless normalized

          STORE[chat_id] = { context: normalized, version: 0 }
        end
      end

      # The chat continues in the session from the history, its work begun
      # before ended (Chats.renew_epoch!): what it holds here, or is being
      # saved as no tab kept it (retire), is its latest context. Only a chat
      # that holds neither takes the saved one, which the block reads then:
      # a context being saved has been saved by that time (none is let go of
      # after the chat's epoch was renewed).
      def continue!(session)
        chat_id = session[Chats::SESSION_KEY]
        return unless chat_id

        held = LOCK.synchronize do
          (STORE[chat_id] || RETIRING.delete(chat_id)).tap { |entry| STORE[chat_id] = entry if entry }
        end
        return if held

        normalized = normalize(yield)
        LOCK.synchronize { STORE[chat_id] ||= { context: normalized, version: 0 } } if normalized
      end

      # No tab kept the chat when it was at epoch: unless it has been
      # continued since (its epoch moved on), work begun for it changes
      # nothing from now on, and its context goes once saved. A tab that
      # continues it while it is being saved takes the context, and the
      # save is then not made (what the tab does next is saved instead).
      def retire(chat_id, epoch)
        entry = LOCK.synchronize do
          next nil unless Chats.renew_epoch!(chat_id, from: epoch)

          STORE.delete(chat_id).tap { |held| RETIRING[chat_id] = held if held }
        end
        return unless entry

        held = -> { LOCK.synchronize { RETIRING[chat_id].equal?(entry) ? entry[:context] : nil } }
        keep_in_history(chat_id, nil, held: held)
      ensure
        LOCK.synchronize { RETIRING.delete(chat_id) if entry && RETIRING[chat_id].equal?(entry) }
      end

      # A chat left for good, or no longer kept by any tab, keeps no context
      # here (the history keeps what was saved, and puts it back when the
      # chat is continued).
      def forget(chat_id)
        LOCK.synchronize { STORE.delete(chat_id) }
      end

      # A context as the panel keeps it: fields of items, each with a text.
      # A field of plain strings (the shape tools kept before) is read as
      # items of the first turn. nil for anything that is not a context.
      def normalize(context)
        return nil unless context.is_a?(Hash)

        turns = context[TURN_KEY] || context[TURN_KEY.to_sym]
        out = { TURN_KEY => turns.is_a?(Integer) ? turns : 0 }
        context.each do |key, items|
          next if key.to_s == TURN_KEY || !items.is_a?(Array)

          out[key.to_s] = items.filter_map { |item| item(item) }
        end
        out
      end

      def item(raw, turn = 1)
        raw = { 'text' => raw } if raw.is_a?(String)
        return nil unless raw.is_a?(Hash)

        text = raw['text'] || raw[:text]
        return nil unless text.is_a?(String) && !text.strip.empty?

        out = { 'text' => text, 'turn' => (raw['turn'] || raw[:turn] || turn).to_i }
        edited = raw.key?('edited') ? raw['edited'] : raw[:edited]
        out['edited'] = true if edited == true
        out
      end

      # The texts of each field, as a tool reads the context.
      def texts(context, fields)
        fields.to_h { |field| [field, Array(context&.dig(field)).filter_map { |i| i.is_a?(Hash) ? i['text'] : nil }] }
      end

      # The context with texts added to field at turn: a text the field
      # holds already from that turn is not added again.
      def add_texts(context, field, texts, turn)
        out = normalize(context) || { TURN_KEY => 0 }
        out[TURN_KEY] = [out[TURN_KEY], turn].max
        items = out[field.to_s] ||= []
        texts.each do |text|
          items << { 'text' => text, 'turn' => turn } unless items.any? { |i| i['text'] == text && i['turn'] == turn }
        end
        out
      end

      # The context with field holding only texts, at turn.
      def set_texts(context, field, texts, turn)
        out = normalize(context) || { TURN_KEY => 0 }
        out[TURN_KEY] = [out[TURN_KEY], turn].max
        out[field.to_s] = texts.map { |text| { 'text' => text, 'turn' => turn } }
        out
      end

      # The context without the items of field whose text is one of texts.
      def remove_texts(context, field, texts)
        out = normalize(context) || { TURN_KEY => 0 }
        out[field.to_s] = Array(out[field.to_s]).reject { |i| texts.include?(i['text']) }
        out
      end

      # What the page is sent for a change: the context, its version and
      # the chat it is of. Sent to the tab only while the tab is in that
      # chat; the page matches the token as well (a message already on its
      # way when the tab left the chat).
      def message(change, schema: nil, extra: {})
        { 'type' => 'context_update', 'context' => change.context, 'schema' => schema,
          'version' => change.version, 'chat' => change.token, 'timestamp' => Time.now.to_f }.merge(extra)
      end

      def send_change(tab, change, schema: nil, extra: {})
        return false unless tab && change && defined?(WebSocketHelper) && WebSocketHelper.respond_to?(:send_to_live_connection)

        WebSocketHelper.send_to_live_connection(tab, message(change, schema: schema, extra: extra).to_json,
                                                chat_id: change.chat_id)
      end

      def copy(value)
        value.nil? ? nil : JSON.parse(JSON.generate(value))
      end
    end
  end
end

# A chat left for good: its last context is saved first (no work for it
# changes it any more once its epoch has ended).
Monadic::Workspace::Chats.on_change do |event, session|
  next unless event == :replaced

  chat_id = session[Monadic::Workspace::Chats::SESSION_KEY]
  Monadic::Workspace::ChatContext.keep_in_history(chat_id, session)
  Monadic::Workspace::ChatContext.forget(chat_id)
end
