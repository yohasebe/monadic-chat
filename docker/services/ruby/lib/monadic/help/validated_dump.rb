# frozen_string_literal: true

require 'digest'
require 'json'
require_relative '../vector_store/schema'

module Monadic
  module Help
    # Validate the entire public distribution before any database mutation.
    # The hash and imported points come from the very same read of the file.
    class ValidatedDump
      VERSION = '1'
      MODEL = 'intfloat/multilingual-e5-base'
      DIMENSION = VectorStore::Schema::EMBEDDING_DIMENSION
      COLLECTIONS = [VectorStore::Schema::HELP_DOCS, VectorStore::Schema::HELP_ITEMS].freeze
      class Invalid < StandardError; end

      attr_reader :data, :sha256

      def initialize(path)
        bytes = File.binread(path)
        @sha256 = Digest::SHA256.hexdigest(bytes)
        @data = JSON.parse(bytes)
        validate!
      rescue JSON::ParserError, SystemCallError => e
        raise Invalid, "Cannot read help dump: #{e.message}"
      end

      def points(collection)
        raise Invalid, 'Unknown help collection' unless COLLECTIONS.include?(collection)

        data.fetch('collections').fetch(collection).fetch('points')
      end

      def record(install_id)
        {
          'install_id' => install_id, 'dump_sha256' => sha256,
          'dump_version' => VERSION, 'embedding_model' => MODEL,
          'embedding_dimension' => DIMENSION,
          'expected_docs' => points(COLLECTIONS[0]).size,
          'expected_items' => points(COLLECTIONS[1]).size,
          'state' => 'installing', 'loaded_at' => nil,
          'exported_at' => data['exported_at']
        }
      end

      private

      def check(condition, message)
        raise Invalid, message unless condition
      end

      def validate!
        check(data.is_a?(Hash), 'Dump must be an object')
        check(data['version'] == VERSION, 'Unsupported dump version')
        check(data['embedding_model'] == MODEL, 'Embedding model mismatch')
        check(data['embedding_dimension'] == DIMENSION, 'Embedding dimension mismatch')
        collections = data['collections']
        check(collections.is_a?(Hash) && collections.keys.sort == COLLECTIONS.sort,
              'Exactly help_docs and help_items are required')
        ids = {}
        COLLECTIONS.each do |name|
          collection = collections[name]
          check(collection.is_a?(Hash), "Invalid collection #{name}")
          entries = collection['points']
          check(entries.is_a?(Array) && !entries.empty?, "Empty or missing points in #{name}")
          ids[name] = {}
          entries.each do |point|
            check(point.is_a?(Hash), "Invalid point in #{name}")
            id = point['id']
            # Help's doc_id payload/index and read APIs use unsigned integers.
            check(id.is_a?(Integer) && id.between?(0, (2**64) - 1), "Invalid ID in #{name}")
            check(!ids[name].key?(id), "Duplicate ID #{id} in #{name}")
            ids[name][id] = true
            payload = point['payload']
            check(payload.is_a?(Hash) && payload['is_internal'] == false,
                  "Point #{name}/#{id} must be explicitly public")
            vector = point['vector']
            check(vector.is_a?(Hash) && vector.keys == ['content'], "Invalid vector names in #{name}/#{id}")
            values = vector['content']
            check(values.is_a?(Array) && values.size == DIMENSION, "Invalid vector dimension in #{name}/#{id}")
            check(values.all? { |v| (v.is_a?(Integer) || v.is_a?(Float)) && v.to_f.finite? && v.abs <= 3.4028234663852886e38 },
                  "Invalid vector number in #{name}/#{id}")
          end
        end
        points(COLLECTIONS[1]).each do |point|
          parent = point['payload']['doc_id']
          check(parent.is_a?(Integer) && ids[COLLECTIONS[0]].key?(parent),
                "Missing document for item #{point['id']}")
        end
      end
    end
  end
end
