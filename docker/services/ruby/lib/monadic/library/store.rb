# frozen_string_literal: true

require_relative '../vector_store'
require_relative '../embeddings'

module Monadic
  module Library
    # Storage facade for the Library (Phase 1a). Provides a thin layer over
    # Qdrant that knows about the four Library collections and the
    # `visibility` / `conversation_id` payload conventions used everywhere.
    #
    # Library is global across apps (no app_key scoping). External access is
    # gated by visibility:
    #   - 'personal'  : Knowledge Base UI only
    #   - 'shareable' : library_search tool returns hits to other apps
    # 'excluded' data is never persisted in the first place — it does not
    # appear here.
    #
    # Hierarchical ingest (Level 2 turns / Level T trajectory / Level 3
    # summary) is implemented by higher-level modules (Hierarchical /
    # Trajectory) on top of this facade. This class only owns the bootstrap
    # + generic upsert / search / delete plumbing.
    class Store
      Schema = Monadic::VectorStore::Schema

      VISIBILITY_PERSONAL = 'personal'
      VISIBILITY_SHAREABLE = 'shareable'
      VALID_VISIBILITIES = [VISIBILITY_PERSONAL, VISIBILITY_SHAREABLE].freeze

      COLLECTIONS = Schema::LIBRARY_COLLECTIONS

      def initialize(vector_store: Monadic::VectorStore.default_backend,
                     embeddings: Monadic::Embeddings.default_client)
        @store = vector_store
        @embeddings = embeddings
      end

      attr_reader :store, :embeddings

      # ─── Bootstrap ─────────────────────────────────────────────────────

      # Create any Library collections that do not yet exist. Idempotent and
      # cheap to call repeatedly.
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

      # Upsert points into a Library collection. The caller is responsible
      # for setting `payload['conversation_id']` and `payload['visibility']`
      # on each point. Validates collection name and visibility values to
      # catch programming errors early.
      def upsert_points(collection:, points:)
        ensure_library_collection!(collection)
        Array(points).each { |p| validate_point!(p) }
        bootstrap_collections!
        @store.upsert_points(collection: collection, points: points)
      end

      # Search a Library collection. `scope` controls the visibility filter:
      #   :kb       — visibility in {personal, shareable} (KB UI use)
      #   :external — visibility = shareable only (RAG via library_search)
      def search(collection:, vector:, scope: :external, filter: nil, limit: 5)
        ensure_library_collection!(collection)
        bootstrap_collections!
        @store.search(
          collection: collection,
          vector: vector, vector_name: 'content',
          filter: combine_filters(visibility_filter(scope), filter),
          limit: limit
        )
      end

      # Remove every point belonging to the given conversation across all
      # Library collections. Returns true on best-effort success.
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

      # Number of registered conversations — i.e. distinct entries in the
      # summaries collection (which acts as the conversation index).
      def conversation_count(scope: :kb)
        bootstrap_collections!
        @store.count(
          collection: Schema::LIBRARY_SUMMARIES,
          filter: visibility_filter(scope)
        )
      end

      # Page through a Library collection. Mirrors the underlying Qdrant
      # scroll API: returns { points: [...], next: cursor_or_nil }. Used by
      # Manager to enumerate the conversation list and similar batch ops.
      def scroll(collection:, filter: nil, limit: 256, offset: nil)
        ensure_library_collection!(collection)
        bootstrap_collections!
        @store.scroll(collection: collection, filter: filter, limit: limit, offset: offset)
      end

      # ─── Filter helpers (public so higher-level modules can compose) ───

      def visibility_filter(scope)
        case scope
        when :kb
          { must: [{ key: 'visibility', match: { any: VALID_VISIBILITIES } }] }
        when :external
          { must: [{ key: 'visibility', match: { value: VISIBILITY_SHAREABLE } }] }
        else
          raise ArgumentError, "Unknown scope: #{scope.inspect} (expected :kb or :external)"
        end
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
        visibility = payload['visibility'] || payload[:visibility]
        unless VALID_VISIBILITIES.include?(visibility.to_s)
          raise ArgumentError,
            "Library point visibility must be one of #{VALID_VISIBILITIES.inspect}, got #{visibility.inspect}"
        end
      end
    end
  end
end
