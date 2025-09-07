# frozen_string_literal: true

# Abstract interface for PDF document storage/search backends.
# Implementations should absorb provider differences and expose
# a uniform contract to the app/UI.
module Monadic
  module DocumentStore
    class Base
      # Import a PDF file into the store.
      # @param file [Tempfile,String,IO] PDF binary (or path)
      # @param metadata [Hash] optional metadata (e.g., title)
      # @return [Hash] { id:, title:, storage_type:, storage_id:, created_at:, size:, status: }
      def import(file:, metadata: {})
        raise NotImplementedError
      end

      # Search documents by query text.
      # @param query [String]
      # @param top_n [Integer]
      # @param options [Hash]
      # @return [Array<Hash>] [{ id:, title:, storage_type:, storage_id:, snippet:, meta: {...} }]
      def search(query:, top_n: 5, options: {})
        raise NotImplementedError
      end

      # List managed documents.
      # @return [Array<Hash>] [{ id:, title:, storage_type:, storage_id:, created_at:, size:, status: }]
      def list
        raise NotImplementedError
      end

      # Delete a document (by logical id or provider-specific storage_id)
      # @param id [String,nil]
      # @param storage_id [String,nil]
      # @return [Boolean]
      def delete(id: nil, storage_id: nil)
        raise NotImplementedError
      end

      # Health check of the backend.
      # @return [Hash] { healthy: Boolean, reason: String }
      def health
        { healthy: true, reason: "ok" }
      end

      # Optional: normalize search results for UI.
      def format_results(results)
        results
      end
    end
  end
end

