# frozen_string_literal: true

require_relative '../vector_store'
require_relative '../embeddings'
require_relative '../utils/app_names'

module Monadic
  module Library
    # Storage facade for the Library. Provides a thin layer over Qdrant
    # that knows about the Library collections and the `conversation_id`
    # payload convention used everywhere.
    #
    # The Library is one shelf: every read sees every entry. Each point
    # still carries `scope_app` ("Global" for new entries; an app's name
    # on entries of earlier versions), which nothing reads by.
    class Store
      Schema = Monadic::VectorStore::Schema

      SCOPE_GLOBAL = 'Global'

      COLLECTIONS = Schema::LIBRARY_COLLECTIONS

      def initialize(vector_store: Monadic::VectorStore.default_backend,
                     embeddings: Monadic::Embeddings.default_client)
        @store = vector_store
        @embeddings = embeddings
      end

      attr_reader :store, :embeddings

      # ─── Bootstrap ─────────────────────────────────────────────────────

      # Collections made earlier get the indexes of the current schema, once
      # per process (see VectorStore::Bootstrap).
      @indexed = {}
      @indexed_mutex = Mutex.new
      class << self
        attr_reader :indexed, :indexed_mutex
      end

      def bootstrap_collections!
        Monadic::VectorStore::Bootstrap.ensure_collections!(
          @store, COLLECTIONS,
          indexed: self.class.indexed, mutex: self.class.indexed_mutex, tag: 'Library'
        )
      end

      # ─── Generic plumbing ──────────────────────────────────────────────

      # Upsert points. Caller must set payload['conversation_id'] and
      # payload['scope_app']. Validates both up front.
      def upsert_points(collection:, points:)
        ensure_library_collection!(collection)
        Array(points).each { |p| validate_point!(p) }
        bootstrap_collections!
        @store.upsert_points(collection: collection, points: points)
      end

      # Search a Library collection: every entry (the Knowledge Base is one
      # shelf; scope_app is written but not searched by).
      def search(collection:, vector:, filter: nil, limit: 5)
        ensure_library_collection!(collection)
        bootstrap_collections!
        @store.search(
          collection: collection,
          vector: vector, vector_name: 'content',
          filter: filter,
          limit: limit
        )
      end

      def delete_conversation(conversation_id)
        bootstrap_collections!
        COLLECTIONS.each do |name|
          @store.delete_points(
            collection: name,
            filter: conversation_filter(conversation_id)
          )
        end
        true
      end

      # The ids of a conversation's points, by Library collection.
      def point_ids(conversation_id)
        COLLECTIONS.to_h do |name|
          ids = []
          offset = nil
          loop do
            page = scroll(collection: name, filter: conversation_filter(conversation_id), limit: 256, offset: offset)
            ids.concat(page[:points].map { |p| p['id'] })
            offset = page[:next]
            break if offset.nil?
          end
          [name, ids]
        end
      end

      # Deletes the points named in ids_by_collection ({ collection => ids }).
      # The summary goes last, so an entry whose turns are being deleted is
      # still listed until the end.
      def delete_point_ids(ids_by_collection)
        bootstrap_collections!
        order = ids_by_collection.keys.sort_by { |name| name == Schema::LIBRARY_SUMMARIES ? 1 : 0 }
        order.each do |name|
          ids = ids_by_collection[name]
          @store.delete_points(collection: name, ids: ids) unless ids.empty?
        end
        true
      end

      # Number of entries made from the kept file of this SHA-256.
      def original_refs(sha256)
        bootstrap_collections!
        @store.count(
          collection: Schema::LIBRARY_SUMMARIES,
          filter: { must: [{ key: 'original.sha256', match: { value: sha256.to_s } }] },
          exact: true
        )
      end

      # The kept file an entry was made from (its summary's 'original'), or nil.
      def original_of(conversation_id)
        page = scroll(collection: Schema::LIBRARY_SUMMARIES, filter: conversation_filter(conversation_id), limit: 1)
        page[:points].first&.dig('payload', 'original')
      end

      # Number of registered conversations.
      def conversation_count
        bootstrap_collections!
        @store.count(collection: Schema::LIBRARY_SUMMARIES, exact: true)
      end

      def scroll(collection:, filter: nil, limit: 256, offset: nil, with_vectors: false)
        ensure_library_collection!(collection)
        bootstrap_collections!
        @store.scroll(collection: collection, filter: filter, limit: limit, offset: offset,
                      with_vectors: with_vectors)
      end

      # ─── Filter helpers ────────────────────────────────────────────────

      def conversation_filter(conversation_id)
        { must: [{ key: 'conversation_id', match: { value: conversation_id.to_s } }] }
      end

      private

      def ensure_library_collection!(name)
        return if COLLECTIONS.include?(name)
        raise ArgumentError,
          "#{name.inspect} is not a Library collection (expected one of #{COLLECTIONS.inspect})"
      end

      def validate_point!(point)
        payload = point[:payload] || point['payload'] || {}
        conv_id = payload['conversation_id'] || payload[:conversation_id]
        if conv_id.nil? || conv_id.to_s.strip.empty?
          raise ArgumentError, "Library point must have payload['conversation_id']"
        end
        scope_app = payload['scope_app'] || payload[:scope_app]
        if scope_app.nil? || scope_app.to_s.strip.empty?
          raise ArgumentError, "Library point must have payload['scope_app'] (an app class name or 'Global')"
        end
      end
    end
  end
end
