# frozen_string_literal: true

module Monadic
  module Embeddings
    # Raised when the embeddings_service returns an unexpected status, the
    # network call fails, or the input itself is invalid (e.g. an empty list).
    class ClientError < StandardError; end
  end
end
