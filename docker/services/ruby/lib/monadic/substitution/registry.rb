# frozen_string_literal: true

require_relative "vocabulary"

module Monadic
  module Substitution
    # Raised when two providers (or a built-in definition) claim the same
    # `${TOKEN}` name, or when a built-in token would collide with Privacy's
    # `<<TYPE_N>>` placeholder namespace.
    class TokenCollisionError < StandardError; end

    # Central authority for `${TOKEN}` name ownership.
    #
    # Vocabulary tokens live in the unified `${...}` namespace as single-word
    # UPPER_CASE names (SHARED, TODAY, MODEL, ...). Privacy placeholders live in
    # a *separate* `<<TYPE_N>>` namespace whose inner names always end in
    # `_<digits>` (PERSON_1, EMAIL_2, ...). The two are syntactically disjoint by
    # delimiter; this registry additionally enforces that no built-in vocabulary
    # token could ever be confused with a Privacy placeholder, and detects two
    # providers claiming the same `${}` name at pipeline-registration time.
    module Registry
      # Privacy placeholder inner-name shape: UPPER_CASE ending in `_<digits>`.
      PRIVACY_TOKEN_RE = /\A[A-Z][A-Z_]*_\d+\z/
      # Valid vocabulary token shape: single-word UPPER_CASE (underscores ok).
      VOCAB_TOKEN_RE = /\A[A-Z][A-Z_]*\z/

      module_function

      # @return [Array<String>] every built-in `${TOKEN}` name
      def builtin_tokens
        Vocabulary::BUILTINS.each_value.map { |meta| meta[:token] }
      end

      # @param name [String, Symbol]
      def privacy_token?(name)
        PRIVACY_TOKEN_RE.match?(name.to_s)
      end

      # Is the given `${}` token name already spoken for (built-in) or
      # indistinguishable from a Privacy placeholder?
      # @param name [String, Symbol]
      def reserved?(name)
        builtin_tokens.include?(name.to_s) || privacy_token?(name)
      end

      # Static `${}` token names a provider owns, for collision detection.
      # Providers with a dynamic/unbounded namespace return [].
      def static_token_names(provider)
        return [] unless provider.respond_to?(:token_names)
        Array(provider.token_names).map(&:to_s)
      end

      # Raise if the new provider claims any `${}` name already claimed by an
      # already-registered provider.
      # @param existing [Array<Provider>]
      # @param incoming [Provider]
      def assert_no_collision!(existing, incoming)
        incoming_names = static_token_names(incoming)
        return if incoming_names.empty?
        existing.each do |provider|
          overlap = static_token_names(provider) & incoming_names
          next if overlap.empty?
          raise TokenCollisionError,
                "Token name collision between #{provider.name} and " \
                "#{incoming.name}: #{overlap.sort.join(', ')}"
        end
      end

      # Invariant guard over the built-in vocabulary (call from a spec). Ensures
      # built-in tokens are unique, are well-formed single-word UPPER_CASE, and
      # are disjoint from the Privacy `<<TYPE_N>>` namespace (never end in
      # `_<digits>`).
      # @raise [TokenCollisionError]
      # @return [true]
      def validate_builtins!
        tokens = builtin_tokens
        dupes = tokens.tally.select { |_, count| count > 1 }.keys
        unless dupes.empty?
          raise TokenCollisionError, "Duplicate built-in tokens: #{dupes.sort.join(', ')}"
        end
        tokens.each do |token|
          unless VOCAB_TOKEN_RE.match?(token)
            raise TokenCollisionError, "Malformed built-in token (not single-word UPPER_CASE): #{token}"
          end
          if privacy_token?(token)
            raise TokenCollisionError, "Built-in token #{token} collides with the Privacy <<TYPE_N>> namespace"
          end
        end
        true
      end
    end
  end
end
