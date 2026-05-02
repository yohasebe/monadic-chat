# frozen_string_literal: true

require 'http'
require 'json'

require_relative 'endpoint'

module Monadic
  module Extractor
    # HTTP client for the extractor_service (Knowledge Base Quality Pack).
    # Wraps the FastAPI surface (/v1/health, /v1/info, /v1/extract) into a
    # small Ruby API. Stateless: every request is independent; the server
    # owns the Docling DocumentConverter singleton.
    #
    # Conventions:
    #   - `path` is a container-side path under /monadic/data (the shared
    #     volume). Callers must translate host paths before invoking
    #     #extract.
    #   - extraction can take 10s-2m on a cold large PDF; we set a long
    #     default timeout but leave it overridable per call.
    class Client
      DEFAULT_TIMEOUT = 600         # seconds; OCR over many pages can be slow
      HEALTH_TIMEOUT = 2            # seconds; liveness probe stays cheap

      class ServiceUnavailableError < StandardError; end
      class ExtractionFailedError < StandardError; end

      def initialize(endpoint: Endpoint.base_url, timeout: DEFAULT_TIMEOUT)
        @endpoint = endpoint.chomp('/')
        @timeout = timeout
      end

      # Liveness probe. Returns true/false; never raises.
      def health
        response = HTTP.timeout(HEALTH_TIMEOUT).get("#{@endpoint}/v1/health")
        response.status.success?
      rescue HTTP::Error, Errno::ECONNREFUSED, SocketError
        false
      end

      # Returns the parsed /v1/info body, or nil if unreachable.
      def info
        response = HTTP.timeout(HEALTH_TIMEOUT).get("#{@endpoint}/v1/info")
        return nil unless response.status.success?
        JSON.parse(response.body.to_s)
      rescue HTTP::Error, JSON::ParserError, Errno::ECONNREFUSED, SocketError
        nil
      end

      # Extract a document. Returns the response body as a Hash with keys
      # `title`, `author`, `page_count`, `markdown`, `extractor_meta`.
      #
      # @param path [String] container-side path under /monadic/data
      # @param format [String] 'auto' | 'pdf' | 'docx' | 'xlsx' | 'pptx'
      # @param ocr [String] 'auto' | 'always' | 'never' (advisory)
      # @param language_hint [Array<String>] optional ISO-639-1 hints
      def extract(path:, format: 'auto', ocr: 'auto', language_hint: [])
        body = {
          'path' => path,
          'format' => format,
          'ocr' => ocr,
          'language_hint' => Array(language_hint)
        }
        begin
          response = HTTP.timeout(@timeout)
                         .headers(content_type: 'application/json')
                         .post("#{@endpoint}/v1/extract", body: JSON.dump(body))
        rescue HTTP::Error, Errno::ECONNREFUSED, SocketError => e
          raise ServiceUnavailableError, "extractor_service unreachable: #{e.message}"
        end

        unless response.status.success?
          raise ExtractionFailedError,
                "extractor_service returned #{response.status.code}: #{response.body.to_s[0, 500]}"
        end

        JSON.parse(response.body.to_s)
      rescue JSON::ParserError => e
        raise ExtractionFailedError, "extractor_service returned non-JSON: #{e.message}"
      end
    end
  end
end
