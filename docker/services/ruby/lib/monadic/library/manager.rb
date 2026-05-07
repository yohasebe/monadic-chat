# frozen_string_literal: true

require 'json'
require_relative 'store'
require_relative 'hierarchical'
require_relative 'retriever'
require_relative 'importers'

module Monadic
  module Library
    # High-level Knowledge Base operations consumed by the Knowledge Base
    # app's tools. These methods sit on top of Store / Hierarchical /
    # Retriever / Importers and expose conversation-level concepts.
    #
    # Scoping model (2026-05): every conversation carries a `scope_app`
    # payload field whose value is either an app class name (e.g.
    # "ChatOpenAI", "JupyterNotebookGrok") or the literal string
    # "Global". library_search filters by the requesting app's class
    # name plus "Global"; the KB UI surfaces below pass `app_name: nil`
    # so they see the full inventory regardless of scope.
    module Manager
      module_function

      # ─── List / inspect ────────────────────────────────────────────────

      # Enumerate conversations registered in the summaries collection,
      # most recently created first. Pass app_name to restrict to entries
      # this app would see (its own + Global); pass nil for the full
      # inventory used by the KB UI.
      def list_conversations(store:, app_name: nil, limit: 100)
        rows = []
        cursor = nil
        loop do
          page = store.scroll(
            collection: VectorStore::Schema::LIBRARY_SUMMARIES,
            filter: store.scope_filter(app_name),
            limit: 256, offset: cursor
          )
          page[:points].each { |p|
            payload = p['payload'] || {}
            rows << summary_row(payload)
          }
          break if page[:next].nil? || rows.size >= limit
          cursor = page[:next]
        end
        rows.sort_by { |r| r[:created_at].to_s }.reverse.first(limit)
      end

      # Fetch the full payload of a conversation's summary point. Returns
      # nil when no matching conversation is registered.
      def get_conversation_details(store:, conversation_id:, app_name: nil)
        page = store.scroll(
          collection: VectorStore::Schema::LIBRARY_SUMMARIES,
          filter: store.combine_filters(
            store.scope_filter(app_name),
            store.conversation_filter(conversation_id)
          ),
          limit: 1
        )
        return nil if page[:points].empty?
        summary_row(page[:points].first['payload'] || {})
      end

      # Fetch verbatim messages + metadata for the Conversation Viewer.
      def get_conversation_messages(store:, conversation_id:, app_name: nil)
        page = store.scroll(
          collection: VectorStore::Schema::LIBRARY_SUMMARIES,
          filter: store.combine_filters(
            store.scope_filter(app_name),
            store.conversation_filter(conversation_id)
          ),
          limit: 1
        )
        return nil if page[:points].empty?
        payload = page[:points].first['payload'] || {}
        {
          conversation_id: payload['conversation_id'],
          title: payload['title'],
          source: payload['source'],
          language: payload['language'],
          scope_app: payload['scope_app'],
          turns_count: payload['turns_count'],
          messages_count: payload['messages_count'],
          created_at: payload['created_at'],
          messages: payload['messages'],
          participants: payload['participants'],
          skipped_reason: payload['messages_skipped_reason']
        }
      end

      # Aggregate counts. Returns total + a per-scope breakdown (one
      # count per distinct scope_app value, including "Global"). Useful
      # for the KB stats line and for letting the Browse modal render an
      # accurate filter dropdown.
      def library_stats(store:)
        total = store.conversation_count
        by_scope = Hash.new(0)
        cursor = nil
        loop do
          page = store.scroll(
            collection: VectorStore::Schema::LIBRARY_SUMMARIES,
            filter: nil,
            limit: 256, offset: cursor
          )
          page[:points].each do |p|
            scope = (p['payload'] || {})['scope_app'].to_s
            scope = Store::SCOPE_GLOBAL if scope.empty?
            by_scope[scope] += 1
          end
          break if page[:next].nil?
          cursor = page[:next]
        end
        {
          conversations_total: total,
          conversations_by_scope: by_scope
        }
      end

      # ─── Mutate ────────────────────────────────────────────────────────

      # Change a conversation's scope_app across every Library
      # collection. Implemented as scroll + upsert because Qdrant has no
      # native partial-payload-update.
      def update_scope_app(store:, conversation_id:, scope_app:)
        normalized = scope_app.to_s.strip
        if normalized.empty?
          raise ArgumentError, "scope_app must be a non-empty string (an app class name or 'Global')"
        end

        VectorStore::Schema::LIBRARY_COLLECTIONS.each do |collection|
          rewrite_payload_field(store, collection, conversation_id, 'scope_app', normalized)
        end
        true
      end

      MAX_TITLE_LENGTH = 200

      def update_title(store:, conversation_id:, title:)
        normalized = title.to_s.strip
        if normalized.empty?
          raise ArgumentError, 'title must not be blank'
        end
        if normalized.length > MAX_TITLE_LENGTH
          raise ArgumentError, "title must be #{MAX_TITLE_LENGTH} characters or fewer"
        end

        rewrite_payload_field(store, VectorStore::Schema::LIBRARY_SUMMARIES,
                              conversation_id, 'title', normalized,
                              limit: 1)
        true
      end

      def delete_conversation(store:, conversation_id:)
        store.delete_conversation(conversation_id)
      end

      # ─── Import + ingest ───────────────────────────────────────────────

      def import_from_text(store:, input:, options: {}, scope_app: Store::SCOPE_GLOBAL)
        parsed = parse_input(input)
        importer = Importers.detect(parsed)
        raise ArgumentError, 'Could not detect a known conversation format' unless importer

        conversation = importer.import(parsed, options)
        counts = Hierarchical.ingest(conversation, store: store, scope_app: scope_app)
        {
          conversation_id: conversation['conversation_id'],
          importer: importer.name.split('::').last,
          counts: counts
        }
      end

      def import_conversation(store:, conversation:, scope_app: Store::SCOPE_GLOBAL)
        counts = Hierarchical.ingest(conversation, store: store, scope_app: scope_app)
        {
          conversation_id: conversation['conversation_id'],
          counts: counts
        }
      end

      # ─── Internals ─────────────────────────────────────────────────────

      def summary_row(payload)
        {
          conversation_id: payload['conversation_id'],
          content_type: payload['content_type'] || 'conversation',
          title: payload['title'],
          source: payload['source'],
          language: payload['language'],
          license: payload['license'],
          scope_app: payload['scope_app'],
          messages_count: payload['messages_count'],
          turns_count: payload['turns_count'],
          duration_seconds: payload['duration_seconds'],
          topics: payload['topics'],
          created_at: payload['created_at']
        }.compact
      end

      # Rewrite a single payload field across every point matching the
      # given conversation_id in `collection`. Used by update_scope_app
      # (every collection) and update_title (summaries only). Setting
      # `limit:` caps how many points to scroll per page; for summaries
      # there is exactly one point so 1 is enough.
      def rewrite_payload_field(store, collection, conversation_id, key, value, limit: 256)
        cursor = nil
        loop do
          page = store.scroll(
            collection: collection,
            filter: store.conversation_filter(conversation_id),
            limit: limit, offset: cursor,
            with_vectors: true
          )
          break if page[:points].empty?
          patched = page[:points].map { |p|
            payload = (p['payload'] || {}).merge(key => value)
            { id: p['id'], vector: p['vector'], payload: payload }
          }
          store.upsert_points(collection: collection, points: patched)
          break if page[:next].nil?
          cursor = page[:next]
        end
      end

      def parse_input(input)
        return input unless input.is_a?(String)
        return input if input.strip.empty?
        begin
          JSON.parse(input)
        rescue JSON::ParserError
          input
        end
      end
    end
  end
end
