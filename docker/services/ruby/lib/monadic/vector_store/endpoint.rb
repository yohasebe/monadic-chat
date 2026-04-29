# frozen_string_literal: true

require_relative '../utils/environment'

module Monadic
  module VectorStore
    # Resolves the URL of the qdrant_service container in either Electron
    # (in-container) or local dev mode, mirroring the privacy/endpoint.rb
    # pattern so all internal services follow the same convention.
    module Endpoint
      IN_CONTAINER_HOST = 'http://qdrant_service:6333'
      DEV_DEFAULT_PORT = '6333'

      module_function

      def base_url
        return ENV['QDRANT_URL'] if ENV['QDRANT_URL'] && !ENV['QDRANT_URL'].empty?

        if Monadic::Utils::Environment.in_container?
          IN_CONTAINER_HOST
        else
          "http://localhost:#{ENV.fetch('QDRANT_DEV_PORT', DEV_DEFAULT_PORT)}"
        end
      end
    end
  end
end
