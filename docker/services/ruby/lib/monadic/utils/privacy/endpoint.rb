# frozen_string_literal: true

require_relative '../environment'

module Monadic
  module Utils
    module Privacy
      module Endpoint
        IN_CONTAINER_HOST = 'http://privacy_service:8000'
        DEV_DEFAULT_PORT = '8001'

        module_function

        def base_url
          if Monadic::Utils::Environment.in_container?
            IN_CONTAINER_HOST
          else
            "http://localhost:#{ENV.fetch('PRIVACY_DEV_PORT', DEV_DEFAULT_PORT)}"
          end
        end
      end
    end
  end
end
