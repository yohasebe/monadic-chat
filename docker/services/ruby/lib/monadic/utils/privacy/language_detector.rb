# frozen_string_literal: true

require_relative 'pipeline'
require_relative '../string_utils'

module Monadic
  module Utils
    module Privacy
      # Detects the conversation language for Privacy Filter when the sidebar
      # is set to "auto". Operates on user-typed text received via WebSocket
      # (handle_ws_streaming) BEFORE any vendor adapter reconstructs the
      # messages array. This matters because vendor adapters can inject
      # placeholder user messages (e.g. OpenAI Responses API injects
      # "Let's start" when input_messages is empty), which would otherwise
      # become the "first user message" seen by the detector and lock the
      # session to the wrong language.
      #
      # Locking happens once per session and persists in
      # session[:monadic_state][:privacy][:detection]. The detection state is
      # stripped on persist (Registry.strip_for_persist) and re-runs after
      # any conversation reset / re-import — same lifecycle as the registry.
      module LanguageDetector
        module_function

        # Read the enabled language set from PRIVACY_LANGS (a runtime
        # setting — all spaCy models are baked into the privacy image). The
        # value is set in two paths depending on execution mode:
        #   * production (Ruby in container): docker compose injects ENV
        #     from the host `~/monadic/config/env` (compose.yml line 14).
        #   * dev (Ruby on host via `rake server:debug`): ENV is NOT set;
        #     the value is loaded into the CONFIG hash by monadic.rb when it
        #     parses `~/monadic/config/env`.
        # CONFIG is checked first so dev mode works; ENV is the production
        # fallback. Filtered through PRESIDIO_LANGS so a typo cannot leak.
        def installed_languages
          raw_config = (defined?(CONFIG) && CONFIG.is_a?(Hash)) ? CONFIG['PRIVACY_LANGS'] : nil
          raw_env = ENV['PRIVACY_LANGS']
          raw = raw_config || raw_env || 'en'
          codes = raw.to_s.split(',').map(&:strip).reject(&:empty?)
          codes = ['en'] if codes.empty?
          (codes.uniq & Pipeline::PRESIDIO_LANGS)
        end

        def detection_state(session)
          return nil unless session && session.respond_to?(:[])
          session[:monadic_state] ||= {}
          session[:monadic_state][:privacy] ||= { registry: {}, audit: [] }
          session[:monadic_state][:privacy][:detection] ||= {
            language: nil,
            reliable: nil,
            locked: false,
            attempts: 0
          }
        end

        def locked?(session)
          state = detection_state(session)
          state && state[:locked] == true
        end

        # Run CLD on a single user-typed text and lock the session language
        # if the detection is reliable and the resulting code is in the
        # installed Presidio set. No-op when:
        #   * session is unusable
        #   * conversation_language is set to a non-"auto" value (explicit
        #     user choice — no need to auto-detect)
        #   * already locked (idempotent)
        #   * text is nil/empty
        #   * CLD reports reliable: false
        #   * detected code is not in the installed Presidio set
        #
        # @param text [String] the user's actual typed input. Pass the raw
        #   WebSocket payload (obj["message"]); never pass a vendor-adapter
        #   reconstructed messages array — those may contain placeholder
        #   user messages injected by the adapter.
        # @param session [Hash] Rack session
        # @return [Hash, nil] detection state, or nil if session is unusable
        def detect_and_lock!(text, session)
          state = detection_state(session)
          return state if state.nil? || state[:locked]
          return state unless auto_mode?(session)
          return state if text.nil? || text.to_s.strip.empty?

          result = ::StringUtils.detect_language_with_confidence(text)
          state[:attempts] = state[:attempts].to_i + 1
          return state unless result.is_a?(Hash)
          return state unless result[:reliable]
          return state unless installed_languages.include?(result[:code])

          state[:language] = result[:code]
          state[:reliable] = true
          state[:locked] = true
          state
        end

        # True when sidebar conversation_language is "auto" (or unset).
        # Defensive against both symbol- and string-keyed Rack sessions.
        def auto_mode?(session)
          return false unless session && session.respond_to?(:[])
          params = session[:parameters] || session["parameters"]
          return true unless params.respond_to?(:[])
          value = params["conversation_language"] || params[:conversation_language]
          value.nil? || value.to_s.empty? || value.to_s == "auto"
        end

        # Read the locked language out of session state without mutating it.
        # Pipeline#resolve_languages calls this on every mask operation.
        def locked_language(session)
          state = peek_detection_state(session)
          return nil unless state.is_a?(Hash)
          return nil unless (state[:locked] || state["locked"]) == true
          state[:language] || state["language"]
        end

        # Read current confidence indicator (for UI display in later phases).
        # Returns true when the lock was set on a reliable detection, false
        # when not yet locked, nil when no detection has been attempted.
        def locked_reliable(session)
          state = peek_detection_state(session)
          return nil unless state.is_a?(Hash)
          state.key?(:reliable) ? state[:reliable] : state["reliable"]
        end

        # Number of detection attempts run so far in this session.
        def attempt_count(session)
          state = peek_detection_state(session)
          return 0 unless state.is_a?(Hash)
          (state[:attempts] || state["attempts"]).to_i
        end

        # Reset detection state (mirrors registry reset path used by
        # CLEAR_HISTORY / app change in misc_handlers.rb).
        def reset!(session)
          return unless session && session.respond_to?(:[])
          monadic_state = session[:monadic_state] || session["monadic_state"]
          return unless monadic_state.is_a?(Hash)
          privacy = monadic_state[:privacy] || monadic_state["privacy"]
          return unless privacy.is_a?(Hash)
          privacy[:detection] = {
            language: nil,
            reliable: nil,
            locked: false,
            attempts: 0
          }
        end

        def peek_detection_state(session)
          return nil unless session && session.respond_to?(:[])
          monadic_state = session[:monadic_state] || session["monadic_state"]
          return nil unless monadic_state.is_a?(Hash)
          privacy = monadic_state[:privacy] || monadic_state["privacy"]
          return nil unless privacy.is_a?(Hash)
          privacy[:detection] || privacy["detection"]
        end
      end
    end
  end
end
