# frozen_string_literal: true

require 'json'

require_relative '../vector_store'

module Monadic
  module Help
    # Bulk-loads a prebuilt JSON dump into Qdrant. The dump is produced by the
    # offline build pipeline (rake help:build) and shipped inside the Ruby
    # container image, so the help database is searchable on first start
    # without re-running embedding inference.
    #
    # Dump format (version 1):
    #   {
    #     "version": "1",
    #     "embedding_model": "intfloat/multilingual-e5-base",
    #     "embedding_dimension": 768,
    #     "exported_at": "2026-04-29T...",
    #     "collections": {
    #       "help_docs":  { "points": [ { "id": Int, "vector": {name: [...]}, "payload": {...} }, ... ] },
    #       "help_items": { "points": [ ... ] }
    #     }
    #   }
    module DumpLoader
      DUMP_VERSION = '1'
      DEFAULT_BATCH_SIZE = 256

      module_function

      # Returns a hash with per-collection counts on success, or nil on
      # validation failure (caller decides how to react).
      def load(store:, path:, batch_size: DEFAULT_BATCH_SIZE, log: $stdout)
        data = JSON.parse(File.read(path))
        return nil unless valid_dump?(data, log: log)

        counts = {}
        (data['collections'] || {}).each do |coll_name, coll_data|
          points = Array(coll_data['points']).map do |p|
            { id: p['id'], vector: p['vector'], payload: p['payload'] }
          end
          imported = 0
          points.each_slice(batch_size) do |batch|
            store.upsert_points(collection: coll_name, points: batch)
            imported += batch.size
          end
          counts[coll_name] = imported
          log.puts "[DumpLoader] #{coll_name}: imported #{imported} points"
        end
        counts
      end

      def valid_dump?(data, log: $stdout)
        unless data.is_a?(Hash) && data['version'] == DUMP_VERSION
          log.puts "[DumpLoader] unsupported dump version: #{data['version'].inspect}"
          return false
        end

        expected_dim = Monadic::VectorStore::Schema::EMBEDDING_DIMENSION
        actual_dim = data['embedding_dimension'].to_i
        unless actual_dim == expected_dim
          log.puts "[DumpLoader] dimension mismatch: dump=#{actual_dim} expected=#{expected_dim}"
          return false
        end
        true
      end
    end
  end
end
