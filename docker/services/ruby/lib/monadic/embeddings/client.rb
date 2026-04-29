# frozen_string_literal: true

require 'http'
require 'json'

require_relative 'endpoint'
require_relative 'errors'

module Monadic
  module Embeddings
    # HTTP client for the embeddings_service container. Wraps the FastAPI
    # surface (/v1/embed, /v1/health, /v1/info) into a small Ruby API and
    # transparently chunks oversized batches so callers can pass arbitrarily
    # long input lists without thinking about server-side limits.
    #
    # Convention: pass :query for short queries that retrieve documents,
    # :passage for the documents themselves. The server applies the e5
    # task-specific prefix accordingly. Returned vectors are L2-normalized so
    # cosine similarity collapses to a dot product downstream.
    class Client
      DEFAULT_TIMEOUT = 60   # seconds; CPU embed of 256 texts can take ~30s
      DEFAULT_BATCH_SIZE = 64
      RETRYABLE_STATUSES = [408, 429, 500, 502, 503, 504].freeze
      MAX_RETRIES = 3
      INITIAL_BACKOFF = 0.5  # seconds

      def initialize(endpoint: Endpoint.base_url,
                     timeout: DEFAULT_TIMEOUT,
                     batch_size: DEFAULT_BATCH_SIZE)
        @endpoint = endpoint.chomp('/')
        @timeout = timeout
        @batch_size = batch_size
      end

      # ─── High-level convenience helpers ────────────────────────────────

      # Embed a single query string. Returns one vector (Array<Float>).
      def embed_query(text)
        embed(texts: [text], task: :query).first
      end

      # Embed a batch of passages. Returns Array<Array<Float>>.
      def embed_passages(texts)
        embed(texts: Array(texts), task: :passage)
      end

      # ─── Core API ──────────────────────────────────────────────────────

      # Embed a list of texts with a chosen task prefix. The list is split
      # into client-side batches of @batch_size each so that the server's
      # MAX_BATCH limit is never hit, regardless of caller input size.
      #
      # @param texts [Array<String>] non-empty
      # @param task [Symbol] :query, :passage, or :raw
      # @return [Array<Array<Float>>] vectors in the same order as input
      def embed(texts:, task: :passage)
        validate_inputs!(texts, task)

        result = []
        Array(texts).each_slice(@batch_size) do |batch|
          response = post_with_retry('/v1/embed', { texts: batch, task: task.to_s })
          vectors = response['vectors']
          unless vectors.is_a?(Array) && vectors.size == batch.size
            raise ClientError,
                  "embeddings service returned #{vectors.is_a?(Array) ? vectors.size : 'non-array'} vectors for batch of #{batch.size}"
          end
          result.concat(vectors)
        end
        result
      end

      # ─── Introspection ─────────────────────────────────────────────────

      # Liveness probe. Returns true/false; never raises.
      def health
        response = HTTP.timeout(2).get("#{@endpoint}/v1/health")
        response.status.success?
      rescue HTTP::Error
        false
      end

      # Returns server info: { 'model' => ..., 'dimension' => 768, ... }.
      def info
        response = HTTP.timeout(@timeout).get("#{@endpoint}/v1/info")
        unless response.status.success?
          raise ClientError, "embeddings /v1/info failed: #{response.status.code}"
        end
        JSON.parse(response.body.to_s)
      rescue HTTP::Error => e
        raise ClientError, "embeddings HTTP error on /v1/info: #{e.message}"
      end

      private

      def validate_inputs!(texts, task)
        unless texts.is_a?(Array) || texts.respond_to?(:to_a)
          raise ClientError, "texts must be an array, got #{texts.class}"
        end
        if Array(texts).empty?
          raise ClientError, 'texts cannot be empty'
        end
        unless %i[query passage raw].include?(task)
          raise ClientError, "unknown task #{task.inspect}; expected :query, :passage, or :raw"
        end
      end

      def post_with_retry(path, body)
        attempt = 0
        backoff = INITIAL_BACKOFF
        loop do
          attempt += 1
          response = HTTP.timeout(@timeout).post("#{@endpoint}#{path}", json: body)
          if response.status.success?
            return JSON.parse(response.body.to_s)
          end

          # Retry on transient server-side conditions, not on caller errors.
          if RETRYABLE_STATUSES.include?(response.status.code) && attempt < MAX_RETRIES
            sleep(backoff)
            backoff *= 2
            next
          end

          raise ClientError,
                "embeddings #{path} -> #{response.status.code} #{response.body.to_s[0, 200]}"
        rescue HTTP::Error => e
          # Network-level errors are retryable up to MAX_RETRIES.
          raise ClientError, "embeddings HTTP error on #{path}: #{e.message}" if attempt >= MAX_RETRIES

          sleep(backoff)
          backoff *= 2
        end
      end
    end
  end
end
