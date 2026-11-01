# frozen_string_literal: true

require 'http'
require 'json'

require_relative 'backend'
require_relative 'endpoint'

module Monadic
  module Utils
    module Privacy
      class PresidioBackend < Backend
        DEFAULT_TIMEOUT = 10

        def initialize(endpoint: Endpoint.base_url, timeout: DEFAULT_TIMEOUT)
          @endpoint = endpoint
          @timeout = timeout
        end

        # The container this was built with masks the strings the user marked
        # (terms); an older one ignores them. Asked once, then kept.
        def supports_terms?
          return @supports_terms unless @supports_terms.nil?

          response = HTTP.timeout(2).get("#{@endpoint}/v1/health")
          body = response.status.success? ? JSON.parse(response.body.to_s) : {}
          @supports_terms = Array(body['capabilities']).include?('terms')
        rescue StandardError
          false
        end

        def anonymize(text:, languages:, registry:, entity_types: nil, options: {}, terms: [])
          if terms.any? && !supports_terms?
            raise BackendError, 'The Privacy container does not mask marked words yet; update it with Actions > Build Privacy Container'
          end

          body = {
            text: text,
            languages: languages,
            registry: registry,
            options: {
              score_threshold: options[:score_threshold] || 0.4,
              honorific_trim: options.fetch(:honorific_trim, true)
            }
          }
          body[:entity_types] = entity_types if entity_types
          body[:terms] = terms.map { |t| { text: t[:text] || t['text'], type: t[:type] || t['type'] } } if terms.any?
          resp = post_json('/v1/anonymize', body)
          raise BackendError, 'Privacy backend gave no masked text' unless resp['masked_text'].is_a?(String)

          {
            masked_text: resp['masked_text'],
            registry: resp['registry'] || {},
            entities: resp['entities'] || [],
            stats: resp['stats'] || {}
          }
        end

        def deanonymize(text:, registry:)
          resp = post_json('/v1/deanonymize', { text: text, registry: registry })
          stats = resp['stats'] || {}
          {
            restored_text: resp['restored_text'],
            missing: stats['missing_placeholders'] || []
          }
        end

        def health
          response = HTTP.timeout(2).get("#{@endpoint}/v1/health")
          response.status.success?
        rescue StandardError
          false
        end

        private

        def post_json(path, body)
          response = HTTP.timeout(@timeout).post("#{@endpoint}#{path}", json: body)
          unless response.status.success?
            raise BackendError, "Privacy backend #{response.status}: #{response.body.to_s[0, 200]}"
          end
          JSON.parse(response.body.to_s)
        rescue HTTP::Error => e
          raise BackendError, "Privacy backend HTTP error: #{e.message}"
        end
      end
    end
  end
end
