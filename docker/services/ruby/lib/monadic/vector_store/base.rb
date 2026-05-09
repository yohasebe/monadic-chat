# frozen_string_literal: true

require_relative 'errors'

module Monadic
  module VectorStore
    # Abstract interface that any concrete vector store backend (Qdrant today,
    # potentially something else later) must implement. The interface is
    # intentionally close to Qdrant's surface area so the primary backend can
    # be a thin pass-through; alternative backends pay an adapter cost.
    #
    # All methods raise NotImplementedError on the base class. Concrete
    # backends should raise Errors::BackendError on failure.
    class Base
      # ─── Collection management ─────────────────────────────────────────

      # Create a collection with the given vector configuration.
      # @param name [String] collection name
      # @param vectors [Hash] map of vector_name => { size:, distance: }
      # @param payload_indexes [Array<Hash>] [{ field:, schema: }, ...]
      def create_collection(name:, vectors:, payload_indexes: [])
        raise NotImplementedError
      end

      def delete_collection(name:)
        raise NotImplementedError
      end

      def collection_exists?(name:)
        raise NotImplementedError
      end

      # ─── Point operations ──────────────────────────────────────────────

      # Insert or update points. Each point is { id:, vector:, payload: }.
      # @param vector may be a flat array (when the collection has a single
      #   unnamed vector) or a hash of name => array (named vectors).
      def upsert_points(collection:, points:)
        raise NotImplementedError
      end

      def delete_points(collection:, ids: nil, filter: nil)
        raise NotImplementedError
      end

      # Retrieve specific points by id. Returns an array of point hashes.
      def retrieve_points(collection:, ids:, with_payload: true, with_vectors: false)
        raise NotImplementedError
      end

      # ─── Search ────────────────────────────────────────────────────────

      # k-nearest-neighbour search over the collection.
      # @return [Array<Hash>] each hit is { id:, score:, payload:, vector: }
      def search(collection:, vector:, vector_name: nil, filter: nil, limit: 10,
                 with_payload: true, with_vectors: false)
        raise NotImplementedError
      end

      # Iterate through points matching a filter. Returns { points:, next: }
      # so the caller can loop until next is nil.
      def scroll(collection:, filter: nil, limit: 100, offset: nil,
                 with_payload: true, with_vectors: false)
        raise NotImplementedError
      end

      def count(collection:, filter: nil, exact: false)
        raise NotImplementedError
      end

      # ─── Health ────────────────────────────────────────────────────────

      # Lightweight liveness check. Returns true/false; should never raise.
      def health
        raise NotImplementedError
      end
    end
  end
end
