# frozen_string_literal: true

# Convenience entry point. Requiring this file pulls in the full vector store
# subsystem: the abstract Base class, the QdrantBackend implementation, the
# shared schema constants, and the error hierarchy.

require_relative 'vector_store/errors'
require_relative 'vector_store/endpoint'
require_relative 'vector_store/schema'
require_relative 'vector_store/base'
require_relative 'vector_store/qdrant_backend'

module Monadic
  module VectorStore
    # Default factory. Other code should call this rather than instantiating
    # QdrantBackend directly so the implementation can be swapped via env.
    module_function

    def default_backend
      QdrantBackend.new
    end
  end
end
