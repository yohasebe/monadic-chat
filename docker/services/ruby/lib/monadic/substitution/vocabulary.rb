# frozen_string_literal: true

require_relative '../utils/environment'

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
      BUILTINS = {
        shared: {
          token: "SHARED",
          description: "The shared data folder synced between you and the user. " \
                       "Refer to files there as ${SHARED}/<name>.",
          resolve: ->(_session) { Monadic::Utils::Environment.shared_volume }
        }
      }.freeze

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
        ([:shared] + declared.map(&:to_sym)).uniq.select { |t| builtin?(t) }
      end

      # Look up a built-in by its `${TOKEN}` name (e.g. "SHARED"). Used by the
      # Vocabulary provider to resolve a token captured from text/args.
      # @param token [String]
      # @return [Hash, nil] the metadata entry, or nil if no such token
      def entry_for_token(token)
        BUILTINS.each_value.find { |meta| meta[:token] == token }
      end
    end
  end
end
