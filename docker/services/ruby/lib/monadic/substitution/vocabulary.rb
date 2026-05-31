# frozen_string_literal: true

require_relative '../utils/environment'
require "date"

module Monadic
  module Substitution
    # Built-in vocabulary token registry.
    #
    # Vocabulary is the second Substitution provider (after PrivacyFilter): it
    # lets the user and the assistant share `${TOKEN}` variables that resolve to
    # paths / state the model should not need to know verbatim (e.g. ${SHARED}
    # for the synced data folder). Tokens live in the unified `${...}` namespace
    # but occupy a disjoint subset from Privacy's `<<TYPE_N>>` placeholders:
    # vocabulary tokens are single-word UPPER_CASE.
    #
    # This module is the single source of truth for *which* built-in tokens
    # exist. The MDSL `vocabulary do; use :name; end` parser (Phase 3) validates
    # `use` against BUILTINS so a typo fails at load time. The resolver/display
    # logic and the Vocabulary provider that expands `${TOKEN}` arrive in Phase
    # 4; this phase only fixes the vocabulary that apps can opt into.
    module Vocabulary
      # name (symbol used in `use :name`) => metadata.
      #   :token       — the `${TOKEN}` name (single-word UPPER_CASE).
      #   :description — surfaced to the LLM via the system-prompt addendum.
      #   :resolve     — proc taking the session hash (decision D), returning the
      #                  value `${TOKEN}` expands to. Runtime-only: BUILTINS is a
      #                  constant, never `.inspect`-serialized (only the plain
      #                  symbol list in settings[:vocabulary] is), so procs here
      #                  are safe.
      #   :display     — per-token display behavior (decision E) consumed by the
      #                  frontend decoration walker:
      #                    :decorate — keep the literal ${TOKEN} symbol visible
      #                                with a hover tooltip + click-to-reveal
      #                                (path-like values, e.g. ${SHARED}).
      #                    :expand   — replace the token with its resolved VALUE
      #                                in the rendered output (value-like tokens,
      #                                e.g. ${TODAY}/${MODEL}/${APP}/${LANG}).
      #                  A missing :display is treated as :decorate by every read
      #                  point (defensive default).
      BUILTINS = {
        shared: {
          token: "SHARED",
          description: "The shared data folder synced between you and the user. " \
                       "Refer to files there as ${SHARED}/<name>.",
          display: :decorate,
          resolve: ->(_session) { Monadic::Utils::Environment.shared_volume }
        },
        today: {
          token: "TODAY",
          description: "Today's date in ISO 8601 form (YYYY-MM-DD).",
          display: :expand,
          resolve: ->(_session) { Date.today.to_s }
        },
        model: {
          token: "MODEL",
          description: "The AI model currently answering this conversation.",
          display: :expand,
          resolve: ->(session) { Monadic::Substitution::Vocabulary.current_model(session) }
        },
        app: {
          token: "APP",
          description: "The display name of the app currently in use.",
          display: :expand,
          resolve: ->(session) { Monadic::Substitution::Vocabulary.current_app_display_name(session) }
        },
        lang: {
          token: "LANG",
          description: "The language you should reply in for this conversation.",
          display: :expand,
          resolve: ->(session) { Monadic::Substitution::Vocabulary.conversation_language(session) }
        },
        # Session-state tokens (NOT in DEFAULT_TOKENS): an app opts in via
        # `vocabulary do; use :last_image; end` so the variable only appears
        # where it is meaningful (image generators, Jupyter). The plumbing that
        # populates the state already exists (image tools save "last_images",
        # Jupyter tools save "notebook_filename"); these resolvers only read it.
        last_image: {
          token: "LAST_IMAGE",
          description: "The filename of the most recently generated image in this session.",
          display: :expand,
          resolve: ->(session) { Monadic::Substitution::Vocabulary.last_generated_image(session) }
        },
        notebook: {
          token: "NOTEBOOK",
          description: "The filename of the Jupyter notebook currently in use.",
          display: :expand,
          resolve: ->(session) { Monadic::Substitution::Vocabulary.current_notebook(session) }
        }
      }.freeze

      # Tokens that are ON by default for every app (universal interface
      # variables). Apps opt out entirely with `vocabulary false`.
      DEFAULT_TOKENS = %i[shared today model app lang].freeze

      module_function

      # @param name [Symbol, String]
      def builtin?(name)
        BUILTINS.key?(name.to_sym)
      end

      # @return [Array<Symbol>] the opt-in names recognised by `use`
      def builtin_names
        BUILTINS.keys
      end

      # Effective vocabulary token symbols for an app — the single source of
      # truth consulted by every read point (the pipeline builder and the
      # system-prompt injector), so MDSL apps and Ruby-class apps behave
      # identically with no per-app wiring.
      #
      # Policy: `${SHARED}` is ON by default for every app (Monadic Chat's
      # shared-folder integration is a universal capability), unless the app
      # opts out with `vocabulary false` (settings[:vocabulary][:enabled] ==
      # false). An app may also declare extra built-ins via `vocabulary do; use
      # …; end`; unknown names are filtered out.
      #
      # @param app_settings [Hash, nil] symbol- or string-keyed app settings
      # @return [Array<Symbol>]
      def tokens_for(app_settings)
        vocab = app_settings && (app_settings[:vocabulary] || app_settings["vocabulary"])
        if vocab
          enabled = vocab.key?(:enabled) ? vocab[:enabled] : vocab["enabled"]
          return [] if enabled == false
        end
        declared = (vocab && (vocab[:tokens] || vocab["tokens"])) || []
        (DEFAULT_TOKENS + declared.map(&:to_sym)).uniq.select { |t| builtin?(t) }
      end

      # Build (or reuse) the session-scoped Substitution::Pipeline carrying the
      # Vocabulary provider. This is the single source of truth for *how* the
      # pipeline is constructed: both the vendor-helper mixin
      # (BaseVendorHelper#substitution_pipeline_for, used in tool-call paths)
      # and the WebSocket streaming handler's display-decoration attach site
      # call here, so the build logic lives in exactly one place.
      #
      # Memoizes into session[:_substitution_pipeline]. Returns nil when the
      # app exposes no vocabulary tokens (opted out via `vocabulary false`); in
      # that case the ivar is left untouched so opt-out apps stay fully off.
      #
      # @param session [Hash, #[]] session-like store
      # @param app_settings [Hash, nil] symbol- or string-keyed app settings
      # @return [Monadic::Substitution::Pipeline, nil]
      def build_pipeline(session, app_settings = nil)
        return nil unless session && session.respond_to?(:[])
        return session[:_substitution_pipeline] if session[:_substitution_pipeline]

        tokens = tokens_for(app_settings)
        return nil if tokens.empty?

        require_relative "pipeline"
        require_relative "providers/vocabulary"
        pipeline = Pipeline.new(session: session, app: nil)
        pipeline.register(Providers::Vocabulary.new(tokens: tokens))
        session[:_substitution_pipeline] = pipeline
      end

      # Look up a built-in by its `${TOKEN}` name (e.g. "SHARED"). Used by the
      # Vocabulary provider to resolve a token captured from text/args.
      # @param token [String]
      # @return [Hash, nil] the metadata entry, or nil if no such token
      def entry_for_token(token)
        BUILTINS.each_value.find { |meta| meta[:token] == token }
      end

      # Structured description of the vocabulary tokens enabled for an app, for
      # the Web UI "Available Variables" panel. This is the single source of
      # truth for that panel: the enabled set comes from #tokens_for, the
      # descriptions/display modes from BUILTINS, and the resolved values from
      # the same resolvers used at runtime (session-dependent). A nil value
      # means "unavailable in this context" — the token is still listed so the
      # user knows it exists; the value is simply omitted by the frontend.
      #
      # Defensive: a resolver that raises yields a nil value rather than
      # breaking the panel.
      #
      # @param session [Hash, #[]] session-like store (resolvers read params)
      # @param app_settings [Hash, nil] symbol- or string-keyed app settings
      # @return [Array<Hash>] e.g.
      #   [{ token: "TODAY", description: "...", display: "expand", value: "2026-05-31" }, ...]
      def describe_for(session, app_settings)
        tokens_for(app_settings).filter_map do |name|
          meta = BUILTINS[name]
          next nil unless meta

          value = begin
            meta[:resolve].call(session)
          rescue StandardError
            nil
          end

          {
            token: meta[:token],
            description: meta[:description],
            display: (meta[:display] || :decorate).to_s,
            value: value
          }
        end
      end

      # Helpers backing the stateful built-in resolvers. Defensive: any missing
      # piece yields nil so the pipeline keeps the literal ${TOKEN} (failure
      # mode :open).

      # @param session [Hash]
      # @return [String, nil]
      def current_model(session)
        params = session_params(session)
        params && (params["model"] || params[:model])
      end

      # @param session [Hash]
      # @return [String, nil] human-readable display name of the active app
      def current_app_display_name(session)
        params = session_params(session)
        app_name = params && (params["app_name"] || params[:app_name])
        return nil unless app_name
        if defined?(APPS) && (app = APPS[app_name]) && app.respond_to?(:settings)
          app.settings["display_name"] || app.settings[:display_name] || app_name
        else
          app_name
        end
      end

      # @param session [Hash]
      # @return [String, nil] conversation language, falling back to UI language;
      #   nil when only "auto" is known (so the literal ${LANG} is kept)
      def conversation_language(session)
        params = session_params(session)
        return nil unless params
        lang = params["conversation_language"] || params[:conversation_language]
        lang = nil if lang == "auto"
        lang ||= params["ui_language"] || params[:ui_language]
        lang
      end

      # @param session [Hash]
      # @return [String, nil] basename of the most recently generated image in
      #   this session, or nil. Reads the unified monadic_state "last_images"
      #   slot for the active app first (where all image generators save), then
      #   falls back to the provider-specific legacy single-image keys.
      def last_generated_image(session)
        params = session_params(session)
        app_name = params && (params["app_name"] || params[:app_name])
        ms = monadic_state(session)
        if app_name
          entry = ms[app_name] || ms[app_name.to_s]
          slot = entry && (entry[:last_images] || entry["last_images"])
          data = slot && (slot[:data] || slot["data"])
          first = data.is_a?(Array) ? data.first : nil
          return File.basename(first.to_s) if first && !first.to_s.empty?
        end
        legacy = session[:openai_last_image] || session[:grok_last_image] ||
                 session[:gemini3_last_image]
        legacy && !legacy.to_s.empty? ? File.basename(legacy.to_s) : nil
      end

      # @param session [Hash]
      # @return [String, nil] filename of the current Jupyter notebook, or nil.
      #   Reads the active app's monadic_state "context" slot, where the Jupyter
      #   tools persist "notebook_filename" on create/open.
      def current_notebook(session)
        params = session_params(session)
        app_name = params && (params["app_name"] || params[:app_name])
        return nil unless app_name
        ms = monadic_state(session)
        entry = ms[app_name] || ms[app_name.to_s]
        slot = entry && (entry[:context] || entry["context"])
        data = slot && (slot[:data] || slot["data"])
        return nil unless data
        name = data["notebook_filename"] || data[:notebook_filename]
        name && !name.to_s.empty? ? name.to_s : nil
      end

      # @return [Hash] the monadic_state namespace (symbol/string tolerant), or {}
      def monadic_state(session)
        return {} unless session.respond_to?(:[])
        session[:monadic_state] || session["monadic_state"] || {}
      end

      # @return [Hash, nil]
      def session_params(session)
        return nil unless session.respond_to?(:[])
        session[:parameters] || session["parameters"]
      end
    end
  end
end
