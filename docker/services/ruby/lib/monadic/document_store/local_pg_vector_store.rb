# frozen_string_literal: true

require_relative "document_store"

module Monadic
  module DocumentStore
    # Thin wrapper around existing PGVector-based endpoints/logic.
    # Phase 1: Provide method signatures without changing current flows.
    class LocalPgVectorStore < Base
      STORAGE_TYPE = "local_pgvector"

      def initialize(env: nil)
        @env = env
      end

      def import(file:, metadata: {})
        # Delegate to existing /pdf ingestion flow (synchronous) via internal helpers
        # The current app invokes /pdf through AJAX; this wrapper is for future internal use.
        {
          id: SecureRandom.uuid,
          title: (metadata[:title] || (file.respond_to?(:path) ? File.basename(file.path) : "PDF")),
          storage_type: STORAGE_TYPE,
          storage_id: nil,
          created_at: Time.now,
          size: (file.respond_to?(:size) ? file.size : nil),
          status: "imported"
        }
      end

      def search(query:, top_n: 5, options: {})
        # Intentionally unimplemented here. The current app routes search
        # through PGVector helper paths (tools in PDF Navigator app).
        []
      end

      def list
        # Use existing list_titles helper if available
        titles = []
        titles = Kernel.respond_to?(:list_pdf_titles) ? list_pdf_titles : []
        titles.map do |t|
          { id: Digest::SHA1.hexdigest(t), title: t, storage_type: STORAGE_TYPE, storage_id: nil, created_at: nil, size: nil, status: "ready" }
        end
      end

      def delete(id: nil, storage_id: nil)
        # Deletion is handled today via WebSocket message and DB logic.
        # This wrapper intentionally no-ops in Phase 1.
        false
      end
    end
  end
end

