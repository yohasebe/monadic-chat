# frozen_string_literal: true

require_relative '../utils/environment'

module Monadic
  module Embeddings
    # Resolves the URL of the embeddings_service container in either Electron
    # (in-container) or local dev mode. Mirrors the privacy/vector_store
    # endpoint pattern so all internal services follow the same convention.
    module Endpoint
      IN_CONTAINER_HOST = 'http://embeddings_service:8000'
      DEV_DEFAULT_PORT = '8002'

      module_function

      def base_url
        return ENV['EMBEDDINGS_URL'] if ENV['EMBEDDINGS_URL'] && !ENV['EMBEDDINGS_URL'].empty?

        if Monadic::Utils::Environment.in_container?
          IN_CONTAINER_HOST
        else
          "http://localhost:#{ENV.fetch('EMBEDDINGS_DEV_PORT', DEV_DEFAULT_PORT)}"
        end
      end
    end
  end
end
