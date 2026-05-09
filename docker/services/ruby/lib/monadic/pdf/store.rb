# frozen_string_literal: true

require 'securerandom'
require 'time'

require_relative '../vector_store'
require_relative '../embeddings'

module Monadic
  module Pdf
    # Storage facade for user-uploaded PDFs. Backed by Qdrant collections
    # (pdf_docs and pdf_items) and the embeddings_service container.
    #
    # PDFs are scoped to an `app_key` so different apps see only their own
    # uploads. The default app_key 'global' is used by the generic /pdf
    # upload endpoint; app-specific tools should construct a Store with the
    # app's normalised name.
    class Store
      Schema = Monadic::VectorStore::Schema

      COLLECTIONS = [Schema::PDF_DOCS, Schema::PDF_ITEMS].freeze
      DEFAULT_APP_KEY = 'global'

      def initialize(app_key: DEFAULT_APP_KEY,
                     vector_store: Monadic::VectorStore.default_backend,
                     embeddings: Monadic::Embeddings.default_client)
        @app_key = app_key.to_s
        @store = vector_store
        @embeddings = embeddings
      end

      attr_reader :app_key, :store, :embeddings

      # ─── Bootstrap ─────────────────────────────────────────────────────

      # Create the pdf_docs and pdf_items collections if they do not yet
      # exist. Idempotent and cheap to call repeatedly.
      def bootstrap_collections!
        COLLECTIONS.each do |name|
          next if @store.collection_exists?(name: name)
          defn = Schema::DEFINITIONS[name]
          @store.create_collection(
            name: name,
            vectors: defn[:vectors],
            payload_indexes: defn[:payload_indexes]
          )
        end
      end

      # ─── Read API ──────────────────────────────────────────────────────

      def any_docs?
        bootstrap_collections!
        @store.count(collection: Schema::PDF_DOCS, filter: app_filter) > 0
      end

      def list_titles
        scroll_all(Schema::PDF_DOCS, filter: app_filter).map do |point|
          payload = point['payload'] || {}
          {
            doc_id: point['id'],
            title: payload['title'],
            items: payload['items'].to_i,
            metadata: payload['metadata'] || {},
            created_at: payload['created_at']
          }
        end
      end

      def find_closest_text(text, top_n: 1)
        bootstrap_collections!
        vec = @embeddings.embed_query(text)
        hits = @store.search(
          collection: Schema::PDF_ITEMS,
          vector: vec, vector_name: 'content',
          filter: app_filter, limit: top_n
        )
        hits.map { |hit| item_hit_to_row(hit) }
      end

      def find_closest_doc(text, top_n: 1)
        bootstrap_collections!
        vec = @embeddings.embed_query(text)
        hits = @store.search(
          collection: Schema::PDF_DOCS,
          vector: vec, vector_name: 'content',
          filter: app_filter, limit: top_n
        )
        hits.map { |hit| doc_hit_to_row(hit) }
      end

      def get_text_snippet(doc_id, position)
        items = scroll_all(
          Schema::PDF_ITEMS,
          filter: combine_filters(
            doc_id_filter(doc_id),
            position_filter(position),
            app_filter
          )
        )
        items.first&.dig('payload')
      end

      def get_text_snippets(doc_id)
        items = scroll_all(
          Schema::PDF_ITEMS,
          filter: combine_filters(doc_id_filter(doc_id), app_filter)
        )
        items
          .map { |p| p['payload'] || {} }
          .sort_by { |p| (p['position'] || 0).to_i }
      end

      # ─── Write API ─────────────────────────────────────────────────────

      # Insert a new doc plus its chunked items. Embeddings are computed via
      # the embeddings_service. Returns the assigned doc_id.
      #
      # @param doc_data [Hash] { title:, metadata: {} }
      # @param items_data [Array<Hash>] [ { text:, metadata: {} }, ... ]
      def store_embeddings(doc_data, items_data)
        bootstrap_collections!

        item_texts = Array(items_data).map { |i| i.fetch(:text) }
        if item_texts.empty?
          raise ArgumentError, 'store_embeddings requires at least one item'
        end

        item_vectors = @embeddings.embed_passages(item_texts)
        doc_vector = mean_vector(item_vectors)
        doc_id = generate_id
        timestamp = Time.now.utc.iso8601

        doc_payload = {
          'app_key' => @app_key,
          'title' => doc_data[:title],
          'items' => item_texts.size,
          'metadata' => doc_data[:metadata] || {},
          'created_at' => timestamp
        }
        @store.upsert_points(
          collection: Schema::PDF_DOCS,
          points: [{
            id: doc_id,
            vector: { 'content' => doc_vector },
            payload: doc_payload
          }]
        )

        item_points = items_data.each_with_index.map do |item, idx|
          {
            id: generate_id,
            vector: { 'content' => item_vectors[idx] },
            payload: {
              'app_key' => @app_key,
              'doc_id' => doc_id,
              'text' => item[:text],
              'position' => idx,
              'metadata' => item[:metadata] || {},
              'created_at' => timestamp
            }
          }
        end
        @store.upsert_points(collection: Schema::PDF_ITEMS, points: item_points)

        doc_id
      end

      # ─── Deletion ──────────────────────────────────────────────────────

      def delete_doc(doc_id)
        bootstrap_collections!
        # Remove items first (filter by doc_id) so a partial failure leaves
        # the parent doc record dangling rather than orphan items.
        @store.delete_points(
          collection: Schema::PDF_ITEMS,
          filter: combine_filters(doc_id_filter(doc_id), app_filter)
        )
        @store.delete_points(
          collection: Schema::PDF_DOCS,
          filter: combine_filters(id_filter(doc_id), app_filter)
        )
        true
      end

      # Wipe all PDF data for this app_key.
      def clear_all
        bootstrap_collections!
        COLLECTIONS.each do |name|
          @store.delete_points(collection: name, filter: app_filter)
        end
        true
      end

      private

      def generate_id
        # Qdrant accepts unsigned 64-bit integers or UUID strings. Use
        # SecureRandom-derived UUIDs so IDs are globally unique across apps.
        SecureRandom.uuid
      end

      def mean_vector(vectors)
        return [] if vectors.empty?
        size = vectors.first.size
        sum = Array.new(size, 0.0)
        vectors.each do |v|
          v.each_with_index { |x, i| sum[i] += x.to_f }
        end
        sum.map { |x| x / vectors.size.to_f }
      end

      # ─── Filter helpers ────────────────────────────────────────────────

      def app_filter
        { must: [{ key: 'app_key', match: { value: @app_key } }] }
      end

      def doc_id_filter(doc_id)
        { must: [{ key: 'doc_id', match: { value: doc_id.to_s } }] }
      end

      def id_filter(doc_id)
        { must: [{ has_id: [doc_id] }] }
      end

      def position_filter(position)
        { must: [{ key: 'position', match: { value: position.to_i } }] }
      end

      def combine_filters(*filters)
        merged = { must: [] }
        filters.compact.each do |f|
          merged[:must].concat(Array(f[:must])) if f[:must]
        end
        merged
      end

      # ─── Hit decoding ──────────────────────────────────────────────────

      def item_hit_to_row(hit)
        payload = hit['payload'] || {}
        {
          text: payload['text'],
          doc_id: payload['doc_id'],
          position: payload['position'],
          metadata: payload['metadata'] || {},
          similarity: hit['score'].to_f
        }
      end

      def doc_hit_to_row(hit)
        payload = hit['payload'] || {}
        {
          doc_id: hit['id'],
          title: payload['title'],
          items: payload['items'].to_i,
          metadata: payload['metadata'] || {},
          similarity: hit['score'].to_f
        }
      end

      def scroll_all(collection, filter: nil, batch_size: 256)
        results = []
        offset = nil
        loop do
          page = @store.scroll(
            collection: collection,
            filter: filter,
            limit: batch_size,
            offset: offset
          )
          results.concat(page[:points])
          break if page[:next].nil?
          offset = page[:next]
        end
        results
      end
    end
  end
end
