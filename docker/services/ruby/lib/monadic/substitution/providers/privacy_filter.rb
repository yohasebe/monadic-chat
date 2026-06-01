# frozen_string_literal: true

require_relative '../provider'
require_relative '../../utils/privacy/backend'
require_relative '../../utils/privacy/presidio_backend'
require_relative '../../utils/privacy/registry'
require_relative '../../utils/privacy/types'
# language_detector is required lazily inside #resolve_languages to break the
# pipeline <-> language_detector require cycle (language_detector requires the
# Privacy::Pipeline alias, which requires this file).

module Monadic
  module Substitution
    module Providers
      # Privacy Filter as a Substitution::Provider.
      #
      # Masks PII in user/assistant text before it reaches the LLM and restores
      # the original values in the response. Detection runs in the Python
      # Presidio container (docker/services/privacy); this class is the Ruby
      # orchestration: language/entity-type resolution, registry bookkeeping,
      # restoration, and TTS sanitization.
      #
      # 8-step pipeline (see docs_dev/privacy_filter_design.md):
      #   register_input -> extract_entities -> update_registry -> render_masked
      #   -> send_to_llm (vendor adapter) -> validate_placeholders
      #   -> restore_for_user -> append_audit
      #
      # State home: the Registry lives at session[:monadic_state][:privacy] (NOT
      # the generic Provider#state slot) so it stays in lockstep with the reset,
      # export, language-detection, and persistence-stripping paths. #state is
      # overridden to fail loudly rather than create an orphan slot.
      #
      # Two public surfaces coexist:
      #   * Generic Provider hooks (on_input / on_output_render) — String in/out,
      #     for the Substitution::Pipeline chain (wired in a later phase).
      #   * Legacy rich methods (before_send_to_llm -> MaskedMessage,
      #     after_receive_from_llm -> RestoredResponse, sanitize_*, registry_*) —
      #     consumed by the existing vendor adapters, handlers, and agents.
      # Both share one masking/restoration core so they cannot drift.
      class PrivacyFilter < Substitution::Provider
        TTS_PLACEHOLDER_RE = /<<([A-Z_]+)_(\d+)>>/

        # Restoration matcher that tolerates minor corruptions an LLM sometimes
        # injects around a placeholder — stray '?' or whitespace, e.g.
        # "<<?EMAIL_ADDRESS_2?>>" or "<< PERSON_1 >>". TTS_PLACEHOLDER_RE stays
        # the canonical wire-format definition (used by the golden drift-guard);
        # RESTORE_RE only widens what we accept *back* from the model so a
        # lightly mangled token still restores instead of leaking the broken
        # token to the user. The captured TYPE_N rebuilds the clean registry
        # key, so the corruption never reaches the UI.
        RESTORE_RE = /<<[\s?]*([A-Z_]+)_(\d+)[\s?]*>>/

        # Languages for which the Privacy container can build a spaCy NER model.
        # Mirrors docker/services/privacy/language_map.json keys.
        PRESIDIO_LANGS = %w[en de es fr it ja nl pt zh].freeze

        def initialize(backend:, config:, session:)
          super()
          @backend = backend
          @config = config || {}
          @session = session
          @registry = Monadic::Utils::Privacy::Registry.new(session)
        end

        def enabled?
          @config[:enabled] == true
        end

        # :closed — masking failures must never silently leak PII; the caller
        # (or Substitution::Pipeline) must refuse the message.
        def failure_mode
          :closed
        end

        # Privacy state lives in the Registry, not the generic provider slot.
        # Overridden to prevent an orphan session[:substitution_state] entry
        # that would escape strip_for_persist / reset / export.
        def state(_context)
          raise NotImplementedError,
                'PrivacyFilter stores state in Registry (session[:monadic_state][:privacy]), not Provider#state'
        end

        # ---- Generic Provider hooks (String in/out) ---------------------------

        # @return [String] masked text. Raises BackendError on backend failure;
        #   the Substitution::Pipeline governs that via failure_mode (:closed).
        def on_input(message, _context)
          return message unless enabled?
          mask_core(message)[:masked_text]
        end

        # @return [String] restored text.
        def on_output_render(text, _context)
          return text unless enabled?
          restore_with_spans(text)[:text]
        end

        # ---- Legacy rich methods (consumed by adapters/handlers/agents) -------

        # @param raw_message [Privacy::RawMessage]
        # @return [Privacy::MaskedMessage] or RawMessage on :pass failure
        def before_send_to_llm(raw_message)
          return raw_message unless enabled?

          result = mask_core(raw_message.text)
          raw_message.to_masked(result[:masked_text], result[:entities])
        rescue Monadic::Utils::Privacy::BackendError => e
          handle_failure(e, raw_message)
        end

        # @param masked_response_text [String]
        # @return [Privacy::RestoredResponse]
        #
        # meta carries :missing_placeholders (placeholders with no registry
        # entry, logged for audit) and :restored_spans (one entry per unique
        # substituted placeholder — { placeholder:, entity_type:, original: } —
        # the UI uses these to wrap restored values; no char offsets because
        # markdown rendering shifts them and the frontend matches by text-node
        # walking).
        def after_receive_from_llm(masked_response_text)
          return Monadic::Utils::Privacy::RestoredResponse.new(masked_response_text, {}) unless enabled?

          # Restore locally rather than calling the backend's /v1/deanonymize:
          # the container does the same find-and-replace, and doing it here keeps
          # the spans in lockstep with the text we ship and lets restoration
          # succeed even when the privacy container is briefly unreachable.
          restored = restore_with_spans(masked_response_text)
          @registry.append_audit(:deanonymize, missing: restored[:missing])
          Monadic::Utils::Privacy::RestoredResponse.new(
            restored[:text],
            {
              missing_placeholders: restored[:missing],
              restored_spans: restored[:spans]
            }
          )
        rescue StandardError => e
          # Restoration failures fall back to the raw masked text — the user
          # sees placeholders rather than wrong values. Log so we know.
          warn "[Privacy] deanonymize failed: #{e.message}"
          Monadic::Utils::Privacy::RestoredResponse.new(masked_response_text, { error: e.message })
        end

        # TTS gets sanitized placeholders ("PERSON 1") rather than the original
        # PII or raw "<<PERSON_1>>". Keeps audio safe and readable.
        def sanitize_for_tts(masked_text)
          return masked_text unless enabled?
          masked_text.gsub(RESTORE_RE) { "#{Regexp.last_match(1).tr('_', ' ')} #{Regexp.last_match(2)}" }
        end

        # Counterpart for the **restored** path: the assistant card text has the
        # original PII back in place. When TTS replays it we must (1) avoid
        # sending PII to the cloud TTS provider and (2) avoid reading out long
        # phone numbers / emails character-by-character. Solution: walk the
        # registry and replace each original value with the same short label
        # sanitize_for_tts produces ("PERSON 1", "EMAIL ADDRESS 1", ...). Pure
        # Ruby reverse lookup; no privacy backend round-trip.
        def sanitize_restored_for_tts(restored_text)
          return restored_text unless enabled?
          return restored_text unless restored_text.is_a?(String) && !restored_text.empty?
          reg = @registry.registry
          return restored_text if reg.empty?

          # Sort by original length descending so longer entities are replaced
          # before any shorter substring of theirs.
          ordered = reg.sort_by { |_, original| -original.to_s.length }
          ordered.each_with_object(restored_text.dup) do |(placeholder, original), out|
            next if original.to_s.empty?
            m = placeholder.match(/\A<<([A-Z_]+)_(\d+)>>\z/)
            next unless m
            label = "#{m[1].tr('_', ' ')} #{m[2]}"
            out.gsub!(original.to_s, label)
          end
        end

        def registry_count
          @registry.count
        end

        def registry_state
          @registry.state
        end

        # Flatten the registry into the shape the frontend's unmask-highlight
        # walker consumes: one entry per registered (placeholder, original) pair.
        def registry_entries
          reg = @registry.registry
          reg.map do |placeholder, original|
            m = placeholder.match(/\A<<([A-Z_]+)_(\d+)>>\z/)
            {
              placeholder: placeholder,
              entity_type: m ? m[1] : 'UNKNOWN',
              original: original
            }
          end
        end

        private

        # Shared masking core for on_input and before_send_to_llm. Anonymizes via
        # the backend, merges the returned registry, and appends the audit entry.
        # Deliberately does NOT rescue BackendError — each caller applies its own
        # failure policy (before_send_to_llm -> handle_failure; on_input ->
        # Substitution::Pipeline failure_mode).
        # @return [Hash] backend result { masked_text:, registry:, entities:, stats: }
        def mask_core(text)
          result = @backend.anonymize(
            text: text,
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
          result
        end

        # Walk masked_text replacing each `<<TYPE_N>>` with its registry value
        # and collecting metadata for the UI's unmask-highlight layer.
        # @return [Hash] { text:, spans:, missing: }
        # spans carries one entry per *unique* substituted placeholder; we
        # deduplicate so the frontend walks the DOM once per restored value.
        def restore_with_spans(masked_text)
          reg = @registry.registry
          seen = {}
          spans = []
          missing = []

          restored_text = masked_text.gsub(RESTORE_RE) do
            match = Regexp.last_match
            type_str = match[1]
            # Rebuild the canonical key from the captured TYPE_N so a lightly
            # corrupted token ("<<?EMAIL_ADDRESS_2?>>") maps to the clean
            # registry key "<<EMAIL_ADDRESS_2>>" — both on restore and in the
            # span/missing metadata, so the corruption never surfaces.
            placeholder = "<<#{type_str}_#{match[2]}>>"

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
        # session's conversation_language. See the historical note in
        # docs_dev for the "auto" lock semantics; the final ["en"] is a safety
        # net for callers that bypass the frontend gate.
        def resolve_languages
          conv_lang = session_param('conversation_language')
          if conv_lang == 'auto'
            require_relative '../../utils/privacy/language_detector'
            locked = Monadic::Utils::Privacy::LanguageDetector.locked_language(@session)
            return [locked] if locked && PRESIDIO_LANGS.include?(locked)
            return ['en']
          end
          return ['en'] if conv_lang.nil? || conv_lang.empty?
          return [conv_lang] if PRESIDIO_LANGS.include?(conv_lang)
          ['en']
        end

        # Read a key from session[:parameters] regardless of symbol/string keys
        # (Rack::Session quirk under different session stores).
        def session_param(key)
          return nil unless @session
          params = @session[:parameters] || @session['parameters']
          return nil unless params.respond_to?(:[])
          params[key.to_s] || params[key.to_sym]
        end

        # Map DSL symbols (:person, :email, ...) to Presidio canonical entity
        # strings. Returns nil when mask_types is unset so the backend keeps
        # legacy unfiltered behavior.
        def presidio_entity_types
          types = @config[:mask_types]
          return nil if types.nil? || types.empty?
          types.map { |t| Monadic::Utils::Privacy::PRESIDIO_TYPE_MAP[t.to_sym] }.compact
        end

        def handle_failure(err, raw_message)
          mode = (@config[:on_failure] || :block).to_sym
          case mode
          when :block
            raise Monadic::Utils::Privacy::BackendError,
                  "Privacy backend failed (on_failure=:block): #{err.message}"
          when :pass
            warn "[Privacy] backend failed, passing raw text: #{err.message}"
            raw_message
          else
            raise Monadic::Utils::Privacy::BackendError, "Unknown on_failure mode: #{mode}"
          end
        end
      end
    end
  end
end
