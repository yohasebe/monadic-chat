# frozen_string_literal: true

require_relative '../utils/environment'

module Monadic
  module Extractor
    # Resolves the URL of the extractor_service (Knowledge Base Quality
    # Pack — Docling + RapidOCR). Mirrors the embeddings/endpoint and
    # privacy endpoint conventions so that all internal services follow
    # the same dev/in-container resolution pattern.
    module Endpoint
      IN_CONTAINER_HOST = 'http://extractor_service:8000'
      DEV_DEFAULT_PORT = '8003'

      module_function

      def base_url
        return ENV['EXTRACTOR_URL'] if ENV['EXTRACTOR_URL'] && !ENV['EXTRACTOR_URL'].empty?

        if Monadic::Utils::Environment.in_container?
          IN_CONTAINER_HOST
        else
          "http://localhost:#{ENV.fetch('EXTRACTOR_DEV_PORT', DEV_DEFAULT_PORT)}"
        end
      end
    end
  end
end
