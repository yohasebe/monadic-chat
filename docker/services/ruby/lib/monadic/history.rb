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

    # Writes the chat in `session` to the history. Nothing of a Private chat
    # reaches the history, which is not even opened for it: the chat is
    # Private before it begins (so no row of it was ever kept), and this
    # process remembers its id (in memory), which keeps out a later copy of
    # it that lacks the mark. A chat with no user words left has its row
    # removed. Returns the revision written, or nil.
    #
    # Called only for a session the tab's state accepted (not one from a
    # connection that a newer one replaced); the connection's generation is
    # checked again by the store, in the same transaction as the write.
    def record(session, tab: nil, store: Store.default)
      return nil unless enabled?

      chat_id = session[Monadic::Workspace::Chats::SESSION_KEY] || session[Monadic::Workspace::Chats::SESSION_KEY.to_s]
      return nil unless chat_id

      generation = session[:_ws_generation] || session['_ws_generation']
      return nil if Policy.private?(session) || Policy.known_private?(chat_id)

      payload = Serializer.payload(session)
      unless payload
        store.clear(chat_id, tab: tab, generation: generation)
        return nil
      end

      params = payload['parameters'] || {}
      schema = Serializer.context_schema(session)
      store.save(chat_id, payload, tab: tab, generation: generation,
                                   app_name: params['app_name'], model: params['model'],
                                   headings: Serializer.headings(payload), search_text: Serializer.search_text(payload),
                                   context: -> { context_now(chat_id, schema) },
                                   word_table: -> { word_table_now(chat_id) })
    end

    # Writes the chat's Session Context as it is now into the chat's saved
    # conversation, when there is one: the context changes apart from the
    # messages (an extraction ends after the reply was saved).
    # session: the chat's (for its context schema), or nil. held: what gives
    # the context to save (nil when there is none), when it is not the one
    # the chat holds now.
    def keep_context(chat_id, session: nil, held: nil, store: Store.default)
      return nil unless enabled? && chat_id && !Policy.known_private?(chat_id)

      schema = Serializer.context_schema(session || {})
      store.update_context(chat_id, -> { context_now(chat_id, schema, held) })
    rescue StandardError => e
      Monadic::Utils::ExtraLogger.log { "[History] context not saved: #{e.class}" } if defined?(Monadic::Utils::ExtraLogger)
      nil
    end

    # The chat's Session Context as it is saved, read once from what the
    # chat holds now (Monadic::Workspace::ChatContext), or :absent when the
    # chat holds none any more. Every save of the history takes the context
    # from here, inside its transaction, so the save made last has the
    # latest context whatever the order the saves were begun in.
    def context_now(chat_id, schema, held = nil)
      context = held ? held.call : Monadic::Workspace::ChatContext.read({ Monadic::Workspace::Chats::SESSION_KEY => chat_id })
      context.nil? ? :absent : Serializer.saved_context(context, schema)
    end

    # The chat's word table as it is saved, read inside the transaction of
    # the save as the context is, or :absent when no table is held for it.
    def word_table_now(chat_id)
      table = Monadic::Utils::Privacy::Words.saved(chat_id)
      table ? Serializer.saved_words(table) : :absent
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
