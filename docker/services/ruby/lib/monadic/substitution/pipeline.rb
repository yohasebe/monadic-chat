# frozen_string_literal: true

require_relative "provider"
require_relative "context"
require_relative "registry"

module Monadic
  module Substitution
    # Orchestrator for user-AI substitution providers.
    #
    # Holds an ordered list of Provider instances and runs them at each lifecycle
    # stage (input, tool_invoke, output, system_prompt_addendum). Providers operate
    # in registration order for input/tool/output transformations; the order is
    # the canonical contract.
    #
    # Convention: register PrivacyFilter before Vocabulary so PII masking happens
    # first on input, and Vocabulary's display decoration runs before Privacy
    # restoration on output (although the two providers' tokens occupy disjoint
    # naming subsets, so order is non-critical for correctness).
    #
    # Token resolution (`#resolve_token`) consults providers in registration
    # order, returning the first match. Unowned tokens yield nil; callers
    # typically pass through the literal `${TOKEN}` form unchanged.
    #
    # Errors raised inside a provider's hook are governed by that provider's
    # #failure_mode:
    #   :open   — log and continue with the value-so-far
    #   :closed — propagate so the caller can refuse the message
    class Pipeline
      # @param session [Hash]
      # @param app [MonadicApp, nil]
      def initialize(session:, app: nil)
        @session = session
        @app = app
        @providers = []
      end

      # All registered providers (frozen view).
      # @return [Array<Provider>]
      def providers
        @providers.dup.freeze
      end

      # Register a provider. Idempotent on identity.
      # @param provider [Provider]
      # @return [self]
      def register(provider)
        unless provider.is_a?(Provider)
          raise ArgumentError, "Expected Substitution::Provider, got #{provider.class}"
        end
        raise ArgumentError, "Provider already registered: #{provider.name}" if @providers.include?(provider)
        Registry.assert_no_collision!(@providers, provider)
        @providers << provider
        self
      end

      # ---- Lifecycle: input ---------------------------------------------------
      def process_input(message)
        fold(@providers, message) { |provider, msg| provider.on_input(msg, context) }
      end

      # ---- Lifecycle: tool invocation ----------------------------------------
      def process_tool_invoke(tool_name, args)
        fold(@providers, args) { |provider, a| provider.on_tool_invoke(tool_name, a, context) }
      end

      # ---- Lifecycle: output rendering ---------------------------------------
      def process_output(text)
        fold(@providers, text) { |provider, t| provider.on_output_render(t, context) }
      end

      # ---- Lifecycle: system_prompt addendum collection ----------------------
      # @return [Array<String>] non-nil addendum strings in registration order
      def system_prompt_addenda
        @providers.each_with_object([]) do |provider, acc|
          value = safely(provider) { provider.system_prompt_addendum(context) }
          acc << value if value.is_a?(String) && !value.empty?
        end
      end

      # ---- Token resolution chain --------------------------------------------
      # Look up a token name across providers. Returns the first owner's value,
      # or nil if no provider claims the token.
      # @param name [String] token name without ${} braces
      # @return [String, nil]
      def resolve_token(name)
        @providers.each do |provider|
          owns = safely(provider) { provider.owns_token?(name) }
          next unless owns
          return safely(provider) { provider.resolve(name, context) }
        end
        nil
      end

      # Merged token => resolved-value map across providers that expose one
      # (currently Vocabulary). Shipped to the frontend for the decoration /
      # hover / reveal-in-explorer layer. Empty hash when no provider resolves.
      # @return [Hash{String=>String}]
      def vocabulary_map
        @providers.each_with_object({}) do |provider, acc|
          next unless provider.respond_to?(:resolved_map)
          map = safely(provider) { provider.resolved_map(context) }
          acc.merge!(map) if map.is_a?(Hash)
        end
      end

      # @return [Substitution::Context] memoized per Pipeline instance
      def context
        @context ||= Context.new(session: @session, app: @app)
      end

      private

      # Fold pattern with per-provider error handling.
      def fold(chain, initial)
        chain.reduce(initial) do |acc, provider|
          begin
            yield(provider, acc)
          rescue StandardError => e
            handle_provider_error(provider, e)
            acc
          end
        end
      end

      # Wrap a single Provider call in error handling that respects failure_mode.
      def safely(provider)
        yield
      rescue StandardError => e
        handle_provider_error(provider, e)
        nil
      end

      def handle_provider_error(provider, error)
        log_provider_error(provider, error)
        raise error if provider.failure_mode == :closed
      end

      def log_provider_error(provider, error)
        return unless defined?(Monadic::Utils::ExtraLogger)
        Monadic::Utils::ExtraLogger.log do
          "[Substitution::Pipeline] Provider #{provider.name} failed: " \
            "#{error.class}: #{error.message}"
        end
      end
    end
  end
end
