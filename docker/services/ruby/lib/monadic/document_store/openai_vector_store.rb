# frozen_string_literal: true

require 'securerandom'
require_relative "document_store"

module Monadic
  module DocumentStore
    # Thin wrapper around OpenAI Files + Vector Store endpoints that already exist.
    # Phase 1: Provide skeletons; real ingestion/search are still driven by
    # /openai/pdf and Responses API hooks.
    class OpenAIVectorStore < Base
      STORAGE_TYPE = "openai_vector_store"

      def initialize(project: nil)
        @project = project
      end

      def import(file:, metadata: {})
        # The real upload is handled via /openai/pdf?action=upload (AJAX in UI).
        # This wrapper returns a placeholder record for future internal use.
        {
          id: SecureRandom.uuid,
          title: (metadata[:title] || (file.respond_to?(:path) ? File.basename(file.path) : "PDF")),
          storage_type: STORAGE_TYPE,
          storage_id: nil, # vs_id/file_id are managed by controller today
          created_at: Time.now,
          size: (file.respond_to?(:size) ? file.size : nil),
          status: "queued"
        }
      end

      def search(query:, top_n: 5, options: {})
        # Searching is performed by Responses API (file_search tool).
        []
      end

      def list
        # Listing is provided via /openai/pdf?action=list; not called here.
        []
      end

      def delete(id: nil, storage_id: nil)
        # Deletion is provided via /openai/pdf?action=delete/clear; not called here.
        false
      end

      def health
        # Basic availability based on API key presence
        ok = defined?(CONFIG) && CONFIG["OPENAI_API_KEY"] && !CONFIG["OPENAI_API_KEY"].to_s.empty?
        { healthy: !!ok, reason: ok ? "ok" : "missing_api_key" }
      end
    end
  end
end
