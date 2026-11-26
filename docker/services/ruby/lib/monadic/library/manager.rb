# frozen_string_literal: true

require 'json'
require 'securerandom'
require_relative 'store'
require_relative 'hierarchical'
require_relative 'retriever'
require_relative 'importers'
require_relative 'file_importer'
require_relative 'originals'

module Monadic
  module Library
    # High-level Knowledge Base operations consumed by the Knowledge Base
    # app's tools. These methods sit on top of Store / Hierarchical /
    # Retriever / Importers and expose conversation-level concepts.
    #
    # The Knowledge Base is one shelf: every read sees every entry.
    # Points carry `scope_app` (new entries "Global"; entries of earlier
    # versions may name an app), which nothing reads by.
    module Manager
      class Changed < StandardError; end

      # Changes of one entry (an update, a rename, a delete) run one at a
      # time: the entry's id picks one of these locks.
      ENTRY_LOCKS = Array.new(64) { Mutex.new }.freeze

      module_function

      def with_entry(conversation_id, &)
        ENTRY_LOCKS[conversation_id.to_s.hash % ENTRY_LOCKS.size].synchronize(&)
      end

      # ─── List / inspect ────────────────────────────────────────────────

      # The fields of an entry's row (summary_row): read without the
      # messages and the rest of the summary.
      ROW_FIELDS = %w[conversation_id content_type title source language license messages_count turns_count
                      duration_seconds topics created_at source_chat_id].freeze

      # The entries of the summaries collection, newest first (the same date
      # ordered by id), limit of them (nil: all). Qdrant pages in id order,
      # not by date: every page is read before sorting.
      def list_conversations(store:, limit: 100)
        rows = []
        cursor = nil
        loop do
          page = store.scroll(collection: VectorStore::Schema::LIBRARY_SUMMARIES, limit: 256, offset: cursor,
                              with_payload: ROW_FIELDS)
          page[:points].each { |p| rows << summary_row(p['payload'] || {}) }
          break if page[:next].nil?

          cursor = page[:next]
        end
        rows = rows.sort_by { |r| [r[:created_at].to_s, r[:conversation_id].to_s] }.reverse
        limit ? rows.first(limit) : rows
      end

      # Fetch the full payload of a conversation's summary point. Returns
      # nil when no matching conversation is registered.
      def get_conversation_details(store:, conversation_id:)
        page = store.scroll(
          collection: VectorStore::Schema::LIBRARY_SUMMARIES,
          filter: store.conversation_filter(conversation_id),
          limit: 1
        )
        return nil if page[:points].empty?
        summary_row(page[:points].first['payload'] || {})
      end

      # Fetch verbatim messages + metadata for the Conversation Viewer.
      def get_conversation_messages(store:, conversation_id:)
        page = store.scroll(
          collection: VectorStore::Schema::LIBRARY_SUMMARIES,
          filter: store.conversation_filter(conversation_id),
          limit: 1
        )
        return nil if page[:points].empty?
        payload = page[:points].first['payload'] || {}
        {
          conversation_id: payload['conversation_id'],
          title: payload['title'],
          source: payload['source'],
          language: payload['language'],
          turns_count: payload['turns_count'],
          messages_count: payload['messages_count'],
          created_at: payload['created_at'],
          messages: payload['messages'],
          participants: payload['participants'],
          skipped_reason: payload['messages_skipped_reason']
        }
      end

      # ─── Mutate ────────────────────────────────────────────────────────

      MAX_TITLE_LENGTH = 200

      def update_title(store:, conversation_id:, title:)
        normalized = title.to_s.strip
        if normalized.empty?
          raise ArgumentError, 'title must not be blank'
        end
        if normalized.length > MAX_TITLE_LENGTH
          raise ArgumentError, "title must be #{MAX_TITLE_LENGTH} characters or fewer"
        end

        with_entry(conversation_id) do
          rewrite_payload_fields(store, VectorStore::Schema::LIBRARY_SUMMARIES, conversation_id,
                                 { 'title' => normalized, 'revision' => SecureRandom.hex(8) }, limit: 1)
        end
        true
      end

      # Deletes the entry, and then the kept file it was made from when no
      # other entry names it (Originals.remove_if_unused).
      def delete_conversation(store:, conversation_id:)
        with_entry(conversation_id) do
          sha256 = store.original_of(conversation_id)&.dig('sha256')
          store.delete_conversation(conversation_id)
          Originals.remove_if_unused(sha256) { |s| store.original_refs(s) } if sha256
        end
        true
      end

      # ─── Import + ingest ───────────────────────────────────────────────

      # Imports a file (FileImporter): its bytes are kept (Originals) and
      # named on the entry as 'original'. When the import fails, the kept
      # file goes again unless another entry or import has it. on_stage is
      # called with :extracting and :embedding_storing.
      def import_file(store:, path:, filename:, options: {}, on_stage: nil)
        kept = Originals.keep(path)
        imported = false
        begin
          on_stage&.call(:extracting)
          conversation = FileImporter.build_conversation(path: path, filename: filename, options: options)
          on_stage&.call(:embedding_storing)
          original = { 'sha256' => kept[:sha256], 'filename' => File.basename(filename.to_s),
                       'extension' => File.extname(filename.to_s).delete_prefix('.').downcase, 'bytes' => kept[:bytes] }
          counts = Hierarchical.ingest(conversation, store: store, original: original)
          imported = true
          { conversation_id: conversation['conversation_id'], counts: counts, original: original }
        ensure
          Originals.release(kept[:sha256])
          Originals.remove_if_unused(kept[:sha256]) { |s| store.original_refs(s) } unless imported
        end
      end

      # A new version of an entry (conversation_id) from a file, while the
      # entry is still at revision (the version the user chose; Changed
      # otherwise, also when it is gone): written under the same id first,
      # then the earlier version's points are deleted by id, and its kept
      # file goes unless another entry has it. A failed import leaves the
      # entry as it was. leftover: some points of the earlier version could
      # not be deleted.
      def replace_file(store:, conversation_id:, revision:, path:, filename:, options: {}, on_stage: nil)
        with_entry(conversation_id) do
          raise Changed, 'the entry changed' unless store.revision_of(conversation_id) == revision.to_s

          prior = store.point_ids(conversation_id)
          prior_sha = store.original_of(conversation_id)&.dig('sha256')
          result = import_file(store: store, path: path, filename: filename,
                               options: options.merge(conversation_id: conversation_id), on_stage: on_stage)
          leftover = begin
            store.delete_point_ids(prior)
            false
          rescue StandardError
            true
          end
          if prior_sha && prior_sha != result.dig(:original, 'sha256')
            Originals.remove_if_unused(prior_sha) { |s| store.original_refs(s) }
          end
          result.merge(updated: true, leftover: leftover)
        end
      end

      def import_conversation(store:, conversation:)
        counts = Hierarchical.ingest(conversation, store: store)
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
          messages_count: payload['messages_count'],
          turns_count: payload['turns_count'],
          duration_seconds: payload['duration_seconds'],
          topics: payload['topics'],
          created_at: payload['created_at'],
          source_chat_id: payload['source_chat_id']
        }.compact
      end

      # Rewrite a single payload field across every point matching the
      # given conversation_id in `collection`. Used by update_title
      # (summaries only). Setting
      # `limit:` caps how many points to scroll per page; for summaries
      # there is exactly one point so 1 is enough.
      def rewrite_payload_fields(store, collection, conversation_id, fields, limit: 256)
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
            payload = (p['payload'] || {}).merge(fields)
            { id: p['id'], vector: p['vector'], payload: payload }
          }
          store.upsert_points(collection: collection, points: patched)
          break if page[:next].nil?
          cursor = page[:next]
        end
      end
    end
  end
end
