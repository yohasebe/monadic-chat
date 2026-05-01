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
    module Manager
      module_function

      # ─── List / inspect ────────────────────────────────────────────────

      # Enumerate conversations registered in the summaries collection,
      # most recently created first. Returns an Array of Hash:
      #   { conversation_id, title, source, language, license, visibility,
      #     messages_count, turns_count, duration_seconds, created_at }
      def list_conversations(store:, scope: :kb, limit: 100)
        rows = []
        cursor = nil
        loop do
          page = store.scroll(
            collection: VectorStore::Schema::LIBRARY_SUMMARIES,
            filter: store.visibility_filter(scope),
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
      def get_conversation_details(store:, conversation_id:, scope: :kb)
        page = store.scroll(
          collection: VectorStore::Schema::LIBRARY_SUMMARIES,
          filter: store.combine_filters(
            store.visibility_filter(scope),
            store.conversation_filter(conversation_id)
          ),
          limit: 1
        )
        return nil if page[:points].empty?
        summary_row(page[:points].first['payload'] || {})
      end

      # Fetch verbatim messages + metadata for the Conversation Viewer
      # modal. Returns:
      #   { conversation_id, title, messages: [...], participants: [...],
      #     metadata: {...}, skipped_reason: nil | "exceeded X bytes" }
      # or nil when the conversation is not registered.
      def get_conversation_messages(store:, conversation_id:, scope: :kb)
        page = store.scroll(
          collection: VectorStore::Schema::LIBRARY_SUMMARIES,
          filter: store.combine_filters(
            store.visibility_filter(scope),
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
          visibility: payload['visibility'],
          turns_count: payload['turns_count'],
          messages_count: payload['messages_count'],
          created_at: payload['created_at'],
          messages: payload['messages'],
          participants: payload['participants'],
          skipped_reason: payload['messages_skipped_reason']
        }
      end

      # Aggregate counts per visibility — useful for the KB UI / status
      # tools.
      def library_stats(store:)
        bootstrap_summary_count = store.conversation_count(scope: :kb)
        shareable_count = store.conversation_count(scope: :external)
        {
          conversations_total: bootstrap_summary_count,
          conversations_shareable: shareable_count,
          conversations_personal: bootstrap_summary_count - shareable_count
        }
      end

      # ─── Mutate ────────────────────────────────────────────────────────

      # Change a conversation's visibility across all four collections by
      # re-writing the visibility field in each existing point's payload.
      # Implemented as scroll + upsert for simplicity; Qdrant has no
      # native partial-payload-update, but upsert with the same id+vector
      # acts as patch when payload is the only diff.
      def update_visibility(store:, conversation_id:, visibility:)
        unless Store::VALID_VISIBILITIES.include?(visibility.to_s)
          raise ArgumentError,
            "visibility must be one of #{Store::VALID_VISIBILITIES.inspect}, got #{visibility.inspect}"
        end

        VectorStore::Schema::LIBRARY_COLLECTIONS.each do |collection|
          rewrite_visibility(store, collection, conversation_id, visibility.to_s)
        end
        true
      end

      # Rewrite the title field on the summary point for a conversation.
      # Title is stored only on summaries (turn / trajectory points carry
      # the conversation_id, not the title) so a single collection rewrite
      # is enough.
      MAX_TITLE_LENGTH = 200

      def update_title(store:, conversation_id:, title:)
        normalized = title.to_s.strip
        if normalized.empty?
          raise ArgumentError, 'title must not be blank'
        end
        if normalized.length > MAX_TITLE_LENGTH
          raise ArgumentError, "title must be #{MAX_TITLE_LENGTH} characters or fewer"
        end

        rewrite_title(store, VectorStore::Schema::LIBRARY_SUMMARIES, conversation_id, normalized)
        true
      end

      # Best-effort delete that simply forwards to Store. Kept here so
      # KB tools have a single import surface.
      def delete_conversation(store:, conversation_id:)
        store.delete_conversation(conversation_id)
      end

      # ─── Import + ingest ───────────────────────────────────────────────

      # Take raw text or a parsed Ruby Hash/Array, dispatch to a
      # registered importer, and ingest the resulting conversation via
      # Hierarchical.ingest. Returns the dispatched importer + ingest
      # counts so callers can build a confirmation message.
      #
      # @param input [String, Hash, Array]
      # @param options [Hash] forwarded to importer (title, license, etc.)
      # @return [Hash] { conversation_id:, importer:, counts: {...} }
      def import_from_text(store:, input:, options: {}, visibility: Store::VISIBILITY_PERSONAL)
        parsed = parse_input(input)
        importer = Importers.detect(parsed)
        raise ArgumentError, 'Could not detect a known conversation format' unless importer

        conversation = importer.import(parsed, options)
        counts = Hierarchical.ingest(conversation, store: store, visibility: visibility)
        {
          conversation_id: conversation['conversation_id'],
          importer: importer.name.split('::').last,
          counts: counts
        }
      end

      # Ingest an already-built monadic-conversation v1 hash. File-based
      # importers (Markdown / Code / PDF / Office) build the hash up-front
      # by reading the file and calling the right module directly, so they
      # bypass the dispatch step that import_from_text uses.
      def import_conversation(store:, conversation:, visibility: Store::VISIBILITY_PERSONAL)
        counts = Hierarchical.ingest(conversation, store: store, visibility: visibility)
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
          visibility: payload['visibility'],
          messages_count: payload['messages_count'],
          turns_count: payload['turns_count'],
          duration_seconds: payload['duration_seconds'],
          topics: payload['topics'],
          created_at: payload['created_at']
        }.compact
      end

      def rewrite_visibility(store, collection, conversation_id, visibility)
        cursor = nil
        loop do
          page = store.scroll(
            collection: collection,
            filter: store.combine_filters(
              store.visibility_filter(:kb),
              store.conversation_filter(conversation_id)
            ),
            limit: 256, offset: cursor,
            with_vectors: true
          )
          patched = page[:points].map { |p|
            payload = (p['payload'] || {}).merge('visibility' => visibility)
            { id: p['id'], vector: p['vector'], payload: payload }
          }
          store.upsert_points(collection: collection, points: patched) unless patched.empty?
          break if page[:next].nil?
          cursor = page[:next]
        end
      end

      def rewrite_title(store, collection, conversation_id, title)
        # with_vectors: true is required so the upsert below preserves the
        # original embedding vector. Without it the vector field comes
        # back nil and Qdrant rejects the upsert (or worse, replaces the
        # embedding with null silently).
        page = store.scroll(
          collection: collection,
          filter: store.combine_filters(
            store.visibility_filter(:kb),
            store.conversation_filter(conversation_id)
          ),
          limit: 1,
          with_vectors: true
        )
        return false if page[:points].empty?
        patched = page[:points].map { |p|
          payload = (p['payload'] || {}).merge('title' => title)
          { id: p['id'], vector: p['vector'], payload: payload }
        }
        store.upsert_points(collection: collection, points: patched)
        true
      end

      # Try parsing a String as JSON. If it fails, return the string as-is
      # so importers like PlainText / TedTalk (Python repr) can take over.
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
