# frozen_string_literal: true

module Monadic
  module Substitution
    # Abstract base class for Substitution Pipeline providers.
    #
    # A provider participates in the user-AI substitution lifecycle by overriding
    # one or more hook methods. The Pipeline runs registered providers in order
    # at each lifecycle stage. Each hook receives the value-so-far and a Context
    # object, and returns the (possibly transformed) value.
    #
    # Token resolution chain:
    #   Providers also declare which named tokens (`${TOKEN_NAME}` syntax) they own
    #   via #owns_token? and #resolve, so multiple providers can coexist in the
    #   unified `${...}` namespace (e.g., PrivacyFilter owns `${PERSON_1}`, Vocabulary
    #   owns `${SHARED}`).
    #
    # Subclasses override hook methods selectively; defaults are no-ops.
    class Provider
      # ---- Lifecycle hooks ---------------------------------------------------

      # Called when a user message arrives, before the LLM sees it.
      # @param message [String] user-submitted text
      # @param context [Substitution::Context]
      # @return [String] transformed (or unchanged) message
      def on_input(message, context)
        message
      end

      # Called when the LLM emits a tool call, before the tool executes.
      # Args may be a deeply-nested Hash/Array/String structure.
      # @param tool_name [String]
      # @param args [Object]
      # @param context [Substitution::Context]
      # @return [Object] transformed args
      def on_tool_invoke(tool_name, args, context)
        args
      end

      # Called when LLM output is rendered for the user.
      # @param text [String]
      # @param context [Substitution::Context]
      # @return [String]
      def on_output_render(text, context)
        text
      end

      # Called once per turn to contribute auto-injected text to system_prompt.
      # @param context [Substitution::Context]
      # @return [String, nil] addendum text or nil to skip
      def system_prompt_addendum(context)
        nil
      end

      # ---- Token resolution --------------------------------------------------

      # @param name [String] e.g. "SHARED" or "PERSON_1" (without `${...}` braces)
      # @return [Boolean] true if this provider owns the token
      def owns_token?(_name)
        false
      end

      # Names of the static `${TOKEN}` tokens this provider owns, for collision
      # detection by Substitution::Registry. Providers whose namespace is
      # dynamic/unbounded (e.g. PrivacyFilter's `<<TYPE_N>>`) return [].
      # @return [Array<String>]
      def token_names
        []
      end

      # @param name [String]
      # @param context [Substitution::Context]
      # @return [String, nil] resolved value or nil if unresolvable
      def resolve(_name, _context)
        nil
      end

      # ---- Identification & policy ------------------------------------------

      # Provider identifier used in logs and state keys.
      def name
        @name ||= self.class.name.to_s.split("::").last
      end

      # :open  — exceptions are logged, the value-so-far is passed through
      # :closed — exceptions are re-raised; the caller must handle them
      # PrivacyFilter declares :closed (PII leak prevention).
      # Vocabulary declares :open (substitution failure should not break UX).
      def failure_mode
        :open
      end

      # Per-provider session state slot. Providers should namespace internal
      # state through this accessor so the session hash never collides.
      # @param context [Substitution::Context]
      # @return [Hash]
      def state(context)
        store = (context.session[:substitution_state] ||= {})
        store[name] ||= {}
      end
    end
  end
end
