# frozen_string_literal: true

require_relative 'backend'
require_relative 'presidio_backend'
require_relative 'registry'
require_relative 'types'
# Loaded lazily inside #resolve_languages to avoid a require cycle:
# language_detector.rb depends on this file's PRESIDIO_LANGS constant.

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

        # Languages for which the Privacy container can build a spaCy NER model.
        # Mirrors docker/services/privacy/language_map.json keys.
        PRESIDIO_LANGS = %w[en de es fr it ja nl pt zh].freeze

        def initialize(backend:, config:, session:)
          @backend = backend
          @config = config || {}
          @session = session
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
            languages: resolve_languages,
            registry: @registry.registry,
            entity_types: presidio_entity_types,
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
        #
        # The meta hash carries:
        #   :missing_placeholders - placeholders the LLM emitted that no longer
        #     appear in the registry (logged for the audit trail).
        #   :restored_spans - one entry per *unique* placeholder that was
        #     actually substituted, of shape
        #       { placeholder:, entity_type:, original: }
        #     The UI uses this to wrap restored values in the assistant card
        #     so the user can see which information leaked the placeholder
        #     boundary. We deliberately do not include character offsets:
        #     markdown rendering shifts them and the frontend matches by
        #     text-node walking instead.
        def after_receive_from_llm(masked_response_text)
          return RestoredResponse.new(masked_response_text, {}) unless enabled?

          # Restore locally rather than calling the backend's /v1/deanonymize.
          # The container does the same simple find-and-replace; doing it
          # here keeps the spans we attach in lockstep with the text we
          # ship to the UI and lets restoration succeed even when the
          # privacy container is briefly unreachable.
          restored = restore_with_spans(masked_response_text)
          @registry.append_audit(:deanonymize, missing: restored[:missing])
          RestoredResponse.new(
            restored[:text],
            {
              missing_placeholders: restored[:missing],
              restored_spans: restored[:spans]
            }
          )
        rescue StandardError => e
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

        # Walk masked_text replacing each `<<TYPE_N>>` with its registry
        # value and collecting metadata for the UI's unmask-highlight layer.
        #
        # Returns { text:, spans:, missing: }.
        #
        # The spans array carries one entry per *unique* placeholder that was
        # actually substituted ({ placeholder:, entity_type:, original: }).
        # We deduplicate so that the frontend only walks the DOM once per
        # restored value even if the LLM repeated the placeholder.
        def restore_with_spans(masked_text)
          reg = @registry.registry
          seen = {}
          spans = []
          missing = []

          restored_text = masked_text.gsub(TTS_PLACEHOLDER_RE) do
            match = Regexp.last_match
            placeholder = match[0]
            type_str = match[1]

            if reg.key?(placeholder)
              original = reg[placeholder]
              unless seen.key?(placeholder)
                seen[placeholder] = true
                spans << {
                  placeholder: placeholder,
                  entity_type: type_str,
                  original: original
                }
              end
              original
            else
              missing << placeholder unless missing.include?(placeholder)
              placeholder
            end
          end

          { text: restored_text, spans: spans, missing: missing }
        end

        # Resolve the language array passed to /v1/anonymize from the active
        # session's conversation_language. The Privacy container is built with
        # one or more spaCy NER models (PRIVACY_LANGS env at build time); the
        # frontend toggle gate prevents the toggle from being enabled when the
        # current conversation_language is not in the installed set, so by the
        # time we reach here the language is expected to be available. The
        # final `["en"]` fallback exists as a safety net for legacy callers
        # that bypass the gate (programmatic LLM paths, etc.).
        #
        # "auto" branches:
        #   1. If LanguageDetector has locked a language for this session,
        #      use it (the lock happens in apply_privacy_to_messages on the
        #      first user message that produces a CLD-reliable detection
        #      restricted to PRIVACY_LANGS).
        #   2. Otherwise, fall back to "en". This keeps the safe default for
        #      the very first turn (before any user message exists) and for
        #      sessions where no user message has yet been reliably classified.
        def resolve_languages
          conv_lang = session_param("conversation_language")
          if conv_lang == "auto"
            require_relative 'language_detector'
            locked = LanguageDetector.locked_language(@session)
            return [locked] if locked && PRESIDIO_LANGS.include?(locked)
            return ["en"]
          end
          return ["en"] if conv_lang.nil? || conv_lang.empty?
          return [conv_lang] if PRESIDIO_LANGS.include?(conv_lang)
          ["en"]
        end

        # Read a key from session[:parameters] regardless of whether keys are
        # symbol- or string-indexed (Rack::Session quirk under different
        # session stores).
        def session_param(key)
          return nil unless @session
          params = @session[:parameters] || @session["parameters"]
          return nil unless params.respond_to?(:[])
          params[key.to_s] || params[key.to_sym]
        end

        # Map DSL symbols (:person, :email, ...) to Presidio canonical entity
        # type strings ("PERSON", "EMAIL_ADDRESS", ...). Returns nil when
        # mask_types is unset so the backend keeps legacy unfiltered behavior.
        def presidio_entity_types
          types = @config[:mask_types]
          return nil if types.nil? || types.empty?
          types.map { |t| PRESIDIO_TYPE_MAP[t.to_sym] }.compact
        end

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
