# frozen_string_literal: true

require 'cgi'
require_relative '../provider'
require_relative '../vocabulary'

module Monadic
  module Substitution
    module Providers
      # Vocabulary provider: gives meaning to the `${TOKEN}` variables an app
      # opted into via `vocabulary do; use :shared; end`.
      #
      #   * on_tool_invoke — EXPANDS `${SHARED}` (and the prefix of
      #     `${SHARED}/sub/path`) to the resolved value so tools operate on the
      #     real, mode-aware path.
      #   * on_output_render — DECORATES `${SHARED}` for display: keeps the
      #     stable symbol visible, wraps it in <code> with a hover title showing
      #     what it resolves to. It does NOT expand, so the user keeps the shared
      #     reference.
      #   * on_input — no-op: the model is told (via the system-prompt addendum)
      #     to use `${SHARED}`, so user/assistant text carries it verbatim.
      #
      # Tokens are single-word UPPER_CASE, disjoint from Privacy's `<<TYPE_N>>`.
      # failure_mode is :open — a substitution miss must never break a turn.
      #
      # NOTE: the enclosing class is named Vocabulary, which shadows the registry
      # module Monadic::Substitution::Vocabulary in lexical lookup, so every
      # registry reference below is fully qualified.
      class Vocabulary < Substitution::Provider
        # ${TOKEN} where TOKEN is single-word UPPER_CASE (e.g. ${SHARED}).
        TOKEN_RE = /\$\{([A-Z][A-Z_]*)\}/

        # @param tokens [Array<Symbol>] opt-in names from settings[:vocabulary][:tokens]
        def initialize(tokens:)
          super()
          @tokens = Array(tokens).map(&:to_sym)
        end

        def failure_mode
          :open
        end

        # ---- Token ownership / resolution -------------------------------------

        # @param name [String] token name without braces, e.g. "SHARED"
        def owns_token?(name)
          enabled_token_names.include?(name)
        end

        # @param name [String] token name without braces
        # @return [String, nil] resolved value, or nil if this app does not
        #   expose the token
        def resolve(name, context)
          entry = enabled_entries.find { |e| e[:token] == name }
          return nil unless entry
          entry[:resolve].call(context.session)
        end

        # ---- Lifecycle hooks --------------------------------------------------

        # Expand owned tokens to their resolved values across a (possibly nested)
        # tool-argument structure.
        def on_tool_invoke(_tool_name, args, context)
          deep_expand(args, context)
        end

        # Decorate owned tokens for display without expanding them.
        #
        # NOTE: kept for the provider contract, but no longer on the live path.
        # Phase 6 ships #resolved_map to the frontend, which decorates the
        # rendered DOM (so it works inside markdown `<code>` spans, where the
        # LLM tends to put paths, and supports click-to-reveal). Backend HTML
        # injection here could not reach tokens inside backtick code.
        def on_output_render(text, context)
          return text unless text.is_a?(String)
          transform_outside_code(text) { |seg| decorate_segment(seg, context) }
        end

        # Map of each enabled token to its resolved value, for the frontend's
        # decoration/hover/reveal layer. e.g. { "SHARED" => "/monadic/data" }.
        def resolved_map(context)
          enabled_entries.each_with_object({}) do |entry, acc|
            acc[entry[:token]] = resolve(entry[:token], context)
          end
        end

        # Describe the exposed variables so the model uses them verbatim rather
        # than guessing absolute paths.
        def system_prompt_addendum(_context)
          entries = enabled_entries
          return nil if entries.empty?

          lines = entries.map { |e| "- `${#{e[:token]}}` — #{e[:description]}" }
          "## Shared variables\n\n" \
            "These variables resolve automatically in file paths and tool calls. " \
            "Use them verbatim — do not substitute absolute paths yourself:\n" +
            lines.join("\n")
        end

        private

        # The BUILTINS entries this app actually exposes.
        def enabled_entries
          @enabled_entries ||= @tokens.filter_map { |t| Monadic::Substitution::Vocabulary::BUILTINS[t] }
        end

        def enabled_token_names
          @enabled_token_names ||= enabled_entries.map { |e| e[:token] }
        end

        # Recursively expand owned `${TOKEN}` occurrences in strings; pass other
        # value types through untouched.
        def deep_expand(obj, context)
          case obj
          when String
            transform_outside_code(obj) { |seg| expand_segment(seg, context) }
          when Array
            obj.map { |e| deep_expand(e, context) }
          when Hash
            obj.each_with_object({}) { |(k, v), h| h[k] = deep_expand(v, context) }
          else
            obj
          end
        end

        def expand_segment(segment, context)
          segment.gsub(TOKEN_RE) do
            name = Regexp.last_match(1)
            owns_token?(name) ? resolve(name, context).to_s : Regexp.last_match(0)
          end
        end

        def decorate_segment(segment, context)
          segment.gsub(TOKEN_RE) do
            name = Regexp.last_match(1)
            next Regexp.last_match(0) unless owns_token?(name)

            # The resolved value lands in a title attribute → must be escaped.
            resolved = CGI.escapeHTML(resolve(name, context).to_s)
            %(<code class="vocab-token" title="#{resolved}">${#{name}}</code>)
          end
        end

        # Yield each run of `text` that is OUTSIDE a backtick code span to the
        # block (transforming it); leave backtick-wrapped runs literal so a user
        # can write `${SHARED}` to mean the token itself (escape, decision B).
        def transform_outside_code(text)
          text.gsub(/(`[^`]*`)|([^`]+)/) do
            code = Regexp.last_match(1)
            code || yield(Regexp.last_match(2))
          end
        end
      end
    end
  end
end
