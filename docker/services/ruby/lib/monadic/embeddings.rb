# frozen_string_literal: true

# Convenience entry point for the embeddings service client. Calling
#   require 'monadic/embeddings'
# pulls in the Client, the URL endpoint resolver, and the error class.

require_relative 'embeddings/errors'
require_relative 'embeddings/endpoint'
require_relative 'embeddings/client'

module Monadic
  module Embeddings
    module_function

    # Single shared client. Callers that want different timeouts or batch
    # sizes can construct Client.new directly; everyone else should use this.
    def default_client
      @default_client ||= Client.new
    end

    # Reset the cached default (useful in tests).
    def reset_default_client!
      @default_client = nil
    end
  end
end
