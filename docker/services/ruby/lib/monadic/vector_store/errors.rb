# frozen_string_literal: true

module Monadic
  module VectorStore
    # Raised when the underlying vector database returns an unexpected status
    # or the network call itself fails. The Ruby callers should catch this
    # rather than HTTP::Error so a single rescue clause covers both classes
    # of failure.
    class BackendError < StandardError; end

    # Raised when a collection that the caller expected to exist is missing,
    # or when a referenced point cannot be retrieved.
    class NotFoundError < BackendError; end
  end
end
