# frozen_string_literal: true

require_relative 'backend'
require_relative 'presidio_backend'
require_relative 'registry'
require_relative 'types'

module Monadic
  module Utils
    module Privacy
      # 8-step pipeline (see docs_dev/privacy_filter_design.md):
      #   register_input → extract_entities → update_registry → render_masked
      #   → send_to_llm (vendor adapter) → validate_placeholders
      #   → restore_for_user → append_audit
      #
      # The vendor adapter calls #before_send_to_llm and #after_receive_from_llm
      # at the http.post boundary; this class hides everything else.
      class Pipeline
        TTS_PLACEHOLDER_RE = /<<([A-Z_]+)_(\d+)>>/

        def initialize(backend:, config:, session:)
          @backend = backend
          @config = config || {}
          @registry = Registry.new(session)
        end

        def enabled?
          @config[:enabled] == true
        end

        # @param raw_message [Privacy::RawMessage]
        # @return [Privacy::MaskedMessage] or RawMessage on :pass failure
        def before_send_to_llm(raw_message)
          return raw_message unless enabled?

          result = @backend.anonymize(
            text: raw_message.text,
            languages: Array(@config[:languages]),
            registry: @registry.registry,
            options: {
              score_threshold: @config[:score_threshold],
              honorific_trim: @config[:honorific_trim]
            }
          )
          @registry.merge!(result[:registry])
          @registry.append_audit(:anonymize, added: result[:entities].map { |e| e['placeholder'] || e[:placeholder] })
          raw_message.to_masked(result[:masked_text], result[:entities])
        rescue BackendError => e
          handle_failure(e, raw_message)
        end

        # @param masked_response_text [String]
        # @return [Privacy::RestoredResponse]
        def after_receive_from_llm(masked_response_text)
          return RestoredResponse.new(masked_response_text, {}) unless enabled?

          result = @backend.deanonymize(
            text: masked_response_text,
            registry: @registry.registry
          )
          @registry.append_audit(:deanonymize, missing: result[:missing])
          RestoredResponse.new(result[:restored_text], { missing_placeholders: result[:missing] })
        rescue BackendError => e
          # Restoration failures fall back to the raw masked text — the user
          # will see placeholders rather than wrong values. Log so we know.
          warn "[Privacy] deanonymize failed: #{e.message}"
          RestoredResponse.new(masked_response_text, { error: e.message })
        end

        # TTS gets sanitized placeholders ("PERSON 1") rather than the
        # original PII or raw "<<PERSON_1>>". Keeps audio safe and readable.
        def sanitize_for_tts(masked_text)
          return masked_text unless enabled?
          masked_text.gsub(TTS_PLACEHOLDER_RE) { "#{Regexp.last_match(1).tr('_', ' ')} #{Regexp.last_match(2)}" }
        end

        def registry_count
          @registry.count
        end

        def registry_state
          @registry.state
        end

        private

        def handle_failure(err, raw_message)
          mode = (@config[:on_failure] || :block).to_sym
          case mode
          when :block
            raise BackendError, "Privacy backend failed (on_failure=:block): #{err.message}"
          when :pass
            warn "[Privacy] backend failed, passing raw text: #{err.message}"
            raw_message
          else
            raise BackendError, "Unknown on_failure mode: #{mode}"
          end
        end
      end
    end
  end
end
