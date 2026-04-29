# frozen_string_literal: true

module Monadic
  module VectorStore
    # Centralised constants for collection names and shapes. Code that needs
    # to read or write vectors should only refer to these symbols so renaming
    # a collection is a one-line change.
    module Schema
      # Embedding dimension of multilingual-e5-base. If the embedding model
      # changes, all collections must be recreated to match the new size.
      EMBEDDING_DIMENSION = 768

      # Cosine distance pairs naturally with L2-normalised e5 outputs.
      DISTANCE = 'Cosine'

      # Collection identifiers
      HELP_DOCS = 'help_docs'
      HELP_ITEMS = 'help_items'
      PDF_DOCS = 'pdf_docs'
      PDF_ITEMS = 'pdf_items'

      ALL_COLLECTIONS = [HELP_DOCS, HELP_ITEMS, PDF_DOCS, PDF_ITEMS].freeze

      # Per-collection definition. Each entry says how to bootstrap the
      # collection (vector config + payload indexes) when it does not yet
      # exist.
      DEFINITIONS = {
        HELP_DOCS => {
          vectors: { 'content' => { size: EMBEDDING_DIMENSION, distance: DISTANCE } },
          payload_indexes: [
            { field: 'language', schema: 'keyword' },
            { field: 'title', schema: 'text' }
          ]
        },
        HELP_ITEMS => {
          vectors: { 'content' => { size: EMBEDDING_DIMENSION, distance: DISTANCE } },
          payload_indexes: [
            { field: 'doc_id', schema: 'integer' },
            { field: 'language', schema: 'keyword' },
            { field: 'position', schema: 'integer' }
          ]
        },
        PDF_DOCS => {
          vectors: { 'content' => { size: EMBEDDING_DIMENSION, distance: DISTANCE } },
          payload_indexes: [
            { field: 'title', schema: 'text' }
          ]
        },
        PDF_ITEMS => {
          vectors: { 'content' => { size: EMBEDDING_DIMENSION, distance: DISTANCE } },
          payload_indexes: [
            { field: 'doc_id', schema: 'integer' },
            { field: 'position', schema: 'integer' }
          ]
        }
      }.freeze
    end
  end
end
