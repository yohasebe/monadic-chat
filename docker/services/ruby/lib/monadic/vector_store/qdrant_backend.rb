# frozen_string_literal: true

require 'http'
require 'json'

require_relative 'base'
require_relative 'endpoint'
require_relative 'errors'

module Monadic
  module VectorStore
    # Concrete VectorStore backed by a qdrant_service container reachable over
    # HTTP. The class is a thin pass-through over Qdrant's REST API; it does
    # not try to mask Qdrant-specific concepts (payload, named vectors) since
    # those concepts are precisely what we want to expose to callers.
    class QdrantBackend < Base
      DEFAULT_TIMEOUT = 30

      def initialize(endpoint: Endpoint.base_url, timeout: DEFAULT_TIMEOUT)
        @endpoint = endpoint.chomp('/')
        @timeout = timeout
      end

      # ─── Collection management ─────────────────────────────────────────

      def create_collection(name:, vectors:, payload_indexes: [])
        body = { vectors: normalize_vectors_config(vectors) }
        put("/collections/#{name}", body)
        payload_indexes.each do |idx|
          put("/collections/#{name}/index", {
            field_name: idx[:field],
            field_schema: idx[:schema]
          })
        end
        true
      end

      def delete_collection(name:)
        response = HTTP.timeout(@timeout).delete("#{@endpoint}/collections/#{name}")
        unless response.status.success? || response.status.code == 404
          raise BackendError, "delete_collection(#{name}) failed: #{response.status.code} #{body_excerpt(response)}"
        end
        true
      end

      def collection_exists?(name:)
        response = HTTP.timeout(@timeout).get("#{@endpoint}/collections/#{name}")
        response.status.success?
      rescue HTTP::Error
        false
      end

      # ─── Point operations ──────────────────────────────────────────────

      def upsert_points(collection:, points:)
        body = {
          points: points.map { |p|
            entry = { id: p.fetch(:id), vector: p.fetch(:vector) }
            entry[:payload] = p[:payload] if p[:payload]
            entry
          }
        }
        result = put("/collections/#{collection}/points?wait=true", body)
        result['result']
      end

      def delete_points(collection:, ids: nil, filter: nil)
        if ids.nil? && filter.nil?
          raise ArgumentError, 'delete_points requires either ids: or filter:'
        end

        body = ids ? { points: Array(ids) } : { filter: filter }
        result = post("/collections/#{collection}/points/delete?wait=true", body)
        result['result']
      end

      def retrieve_points(collection:, ids:, with_payload: true, with_vectors: false)
        body = {
          ids: Array(ids),
          with_payload: with_payload,
          with_vector: with_vectors
        }
        result = post("/collections/#{collection}/points", body)
        Array(result['result'])
      end

      # ─── Search ────────────────────────────────────────────────────────

      def search(collection:, vector:, vector_name: nil, filter: nil, limit: 10,
                 with_payload: true, with_vectors: false)
        body = {
          vector: vector_name ? { name: vector_name, vector: vector } : vector,
          limit: limit,
          with_payload: with_payload,
          with_vector: with_vectors
        }
        body[:filter] = filter if filter
        result = post("/collections/#{collection}/points/search", body)
        Array(result['result'])
      end

      def scroll(collection:, filter: nil, limit: 100, offset: nil,
                 with_payload: true, with_vectors: false)
        body = {
          limit: limit,
          with_payload: with_payload,
          with_vector: with_vectors
        }
        body[:filter] = filter if filter
        body[:offset] = offset if offset
        result = post("/collections/#{collection}/points/scroll", body)
        {
          points: Array(result.dig('result', 'points')),
          next: result.dig('result', 'next_page_offset')
        }
      end

      def count(collection:, filter: nil, exact: false)
        body = { exact: exact }
        body[:filter] = filter if filter
        result = post("/collections/#{collection}/points/count", body)
        Integer(result.dig('result', 'count') || 0)
      end

      # ─── Health ────────────────────────────────────────────────────────

      def health
        response = HTTP.timeout(2).get("#{@endpoint}/healthz")
        response.status.success?
      rescue HTTP::Error
        false
      end

      private

      # Qdrant accepts either a single { size:, distance: } block (unnamed
      # vector) or a map of named vectors. We always emit the latter form so
      # collections can grow extra named vectors later without a schema
      # rewrite.
      def normalize_vectors_config(vectors)
        vectors.transform_values do |cfg|
          { size: cfg.fetch(:size), distance: cfg.fetch(:distance) }
        end
      end

      def put(path, body)
        request(:put, path, body)
      end

      def post(path, body)
        request(:post, path, body)
      end

      def request(method, path, body)
        response = HTTP.timeout(@timeout).public_send(method, "#{@endpoint}#{path}", json: body)
        unless response.status.success?
          raise BackendError, "Qdrant #{method.upcase} #{path} -> #{response.status.code} #{body_excerpt(response)}"
        end
        JSON.parse(response.body.to_s)
      rescue HTTP::Error => e
        raise BackendError, "Qdrant HTTP error on #{method.upcase} #{path}: #{e.message}"
      end

      def body_excerpt(response)
        response.body.to_s[0, 200]
      end
    end
  end
end
