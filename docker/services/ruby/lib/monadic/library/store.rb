# frozen_string_literal: true

require_relative '../vector_store'
require_relative '../embeddings'

module Monadic
  module Library
    # Storage facade for the Library. Provides a thin layer over Qdrant
    # that knows about the Library collections and the `scope_app` /
    # `conversation_id` payload conventions used everywhere.
    #
    # The Library is shared across apps. Cross-app retrieval is gated by
    # the `scope_app` payload field on each conversation:
    #   - "<AppClassName>" (e.g. "ChatOpenAI", "JupyterNotebookGrok") —
    #     library_search only returns hits when the requesting app
    #     matches this exact class. Provider variants are intentionally
    #     separate scopes ("ChatOpenAI" and "ChatClaude" do not share).
    #   - "Global" — searchable from every app + every provider.
    #
    # The Knowledge Base UI sees every entry regardless of scope_app —
    # scoping is a retrieval-time concern, not a visibility-from-the-user
    # concern.
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

      def bootstrap_collections!
        COLLECTIONS.each do |name|
          next if @store.collection_exists?(name: name)
          defn = Schema::DEFINITIONS[name]
          @store.create_collection(
            name: name,
            vectors: defn[:vectors],
            payload_indexes: defn[:payload_indexes]
          )
        end
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

      # Search a Library collection. Pass `app_name:` to restrict to
      # entries scoped to that app or "Global". Pass nil (default) to
      # search across every entry — used by the KB UI's full-inventory
      # surfaces.
      def search(collection:, vector:, app_name: nil, filter: nil, limit: 5)
        ensure_library_collection!(collection)
        bootstrap_collections!
        @store.search(
          collection: collection,
          vector: vector, vector_name: 'content',
          filter: combine_filters(scope_filter(app_name), filter),
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

      # Number of registered conversations. Pass app_name to count only
      # entries this app would see (its own + Global); pass nil for the
      # total.
      def conversation_count(app_name: nil)
        bootstrap_collections!
        @store.count(
          collection: Schema::LIBRARY_SUMMARIES,
          filter: scope_filter(app_name),
          exact: true
        )
      end

      def scroll(collection:, filter: nil, limit: 256, offset: nil, with_vectors: false)
        ensure_library_collection!(collection)
        bootstrap_collections!
        @store.scroll(collection: collection, filter: filter, limit: limit, offset: offset,
                      with_vectors: with_vectors)
      end

      # ─── Filter helpers ────────────────────────────────────────────────

      # Returns a filter that matches scope_app == app_name OR
      # scope_app == "Global". When app_name is nil/empty, returns nil so
      # the caller's combine_filters skips the scope clause entirely
      # (used by the KB UI to show every entry).
      def scope_filter(app_name)
        s = app_name.to_s.strip
        return nil if s.empty?
        { must: [{ key: 'scope_app', match: { any: [s, SCOPE_GLOBAL] } }] }
      end

      def conversation_filter(conversation_id)
        { must: [{ key: 'conversation_id', match: { value: conversation_id.to_s } }] }
      end

      def combine_filters(*filters)
        merged = { must: [] }
        filters.compact.each do |f|
          merged[:must].concat(Array(f[:must])) if f[:must]
        end
        merged[:must].empty? ? nil : merged
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
