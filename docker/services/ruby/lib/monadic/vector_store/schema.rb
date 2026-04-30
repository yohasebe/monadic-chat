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

      # Library (Phase 1a) collections. The Library subsystem stores
      # conversations and documents as a hierarchical embedding tree:
      #   library_summaries — one point per conversation, conv-level index
      #     plus Level 3 summary embedding
      #   library_turns      — Level 2, the main RAG retrieval unit
      #   library_trajectory — Level T, sliding-window discourse trajectory
      #   library_messages   — Level 1, message-level (reserved for Phase 1b+)
      LIBRARY_SUMMARIES = 'library_summaries'
      LIBRARY_TURNS = 'library_turns'
      LIBRARY_TRAJECTORY = 'library_trajectory'
      LIBRARY_MESSAGES = 'library_messages'

      LIBRARY_COLLECTIONS = [
        LIBRARY_SUMMARIES,
        LIBRARY_TURNS,
        LIBRARY_TRAJECTORY,
        LIBRARY_MESSAGES
      ].freeze

      ALL_COLLECTIONS = (
        [HELP_DOCS, HELP_ITEMS, PDF_DOCS, PDF_ITEMS] + LIBRARY_COLLECTIONS
      ).freeze

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
        },
        LIBRARY_SUMMARIES => {
          vectors: { 'content' => { size: EMBEDDING_DIMENSION, distance: DISTANCE } },
          payload_indexes: [
            { field: 'conversation_id', schema: 'keyword' },
            { field: 'visibility', schema: 'keyword' },
            { field: 'source', schema: 'keyword' },
            { field: 'language', schema: 'keyword' }
          ]
        },
        LIBRARY_TURNS => {
          vectors: { 'content' => { size: EMBEDDING_DIMENSION, distance: DISTANCE } },
          payload_indexes: [
            { field: 'conversation_id', schema: 'keyword' },
            { field: 'visibility', schema: 'keyword' },
            { field: 'turn_idx', schema: 'integer' }
          ]
        },
        LIBRARY_TRAJECTORY => {
          vectors: { 'content' => { size: EMBEDDING_DIMENSION, distance: DISTANCE } },
          payload_indexes: [
            { field: 'conversation_id', schema: 'keyword' },
            { field: 'visibility', schema: 'keyword' },
            { field: 'turn_idx', schema: 'integer' }
          ]
        },
        LIBRARY_MESSAGES => {
          vectors: { 'content' => { size: EMBEDDING_DIMENSION, distance: DISTANCE } },
          payload_indexes: [
            { field: 'conversation_id', schema: 'keyword' },
            { field: 'visibility', schema: 'keyword' },
            { field: 'message_id', schema: 'keyword' }
          ]
        }
      }.freeze
    end
  end
end
