# frozen_string_literal: true

module Monadic
  module MCP
    # Process-level token budget for the Conduit surface.
    #
    # Conduit's first principle for cost safety (design §5): the platform — not
    # the calling CLI agent — enforces the ceiling. Every Conduit tool that
    # spends provider tokens reserves against this budget BEFORE the call (a
    # hard ceiling that refuses runaway work) and records actual usage AFTER.
    #
    # Currency is *tokens*, not dollars: model_spec.js carries no pricing, so a
    # token ceiling is the honest, provider-agnostic unit. Counts are estimated
    # with the shared tiktoken tokenizer (send_query does not expose provider
    # usage), which is approximate across providers but sufficient as a safety
    # backstop.
    #
    # The budget is cumulative for the life of the server process and surfaced
    # in monadic_status. Raise it via CONFIG["CONDUIT_TOKEN_BUDGET"]; it resets
    # when the process restarts. Fail-closed: when the ceiling is reached,
    # further spending tools are refused rather than silently proceeding.
    module CostGuard
      DEFAULT_TOKEN_BUDGET = 1_000_000

      class BudgetExceeded < StandardError; end

      @mutex = Mutex.new
      @spent = 0

      module_function

      # Configured ceiling (tokens). Falls back to DEFAULT_TOKEN_BUDGET when
      # unset or non-positive.
      def budget_total
        raw = (defined?(CONFIG) && CONFIG) ? CONFIG["CONDUIT_TOKEN_BUDGET"] : nil
        n = raw.to_s.strip.to_i
        n.positive? ? n : DEFAULT_TOKEN_BUDGET
      end

      def spent
        @mutex.synchronize { @spent }
      end

      def remaining
        [budget_total - spent, 0].max
      end

      # Reserve `projected` tokens before a call. Raises BudgetExceeded if the
      # projection would push cumulative spend past the ceiling. Does NOT record
      # the spend — call record() with the actual amount once the call returns.
      def ensure_within!(projected)
        projected = projected.to_i
        @mutex.synchronize do
          remain = [budget_total - @spent, 0].max
          if projected > remain
            raise BudgetExceeded,
                  "projected #{projected} tokens exceeds remaining budget " \
                  "#{remain} (ceiling #{budget_total}, already spent #{@spent})"
          end
        end
      end

      # Record actual tokens spent by a completed call.
      def record(tokens)
        @mutex.synchronize { @spent += tokens.to_i }
      end

      # Reset cumulative spend (test/admin use).
      def reset!
        @mutex.synchronize { @spent = 0 }
      end

      def status
        total = budget_total
        used = spent
        {
          token_budget: total,
          tokens_spent: used,
          tokens_remaining: [total - used, 0].max
        }
      end

      # Best-effort token count using the shared tiktoken tokenizer, with a
      # crude length-based fallback when the tokenizer is unavailable.
      def estimate_tokens(text)
        str = text.to_s
        return 0 if str.empty?

        if defined?(MonadicApp) && defined?(MonadicApp::TOKENIZER) && MonadicApp::TOKENIZER
          MonadicApp::TOKENIZER.count_tokens(str)
        else
          (str.length / 4.0).ceil
        end
      rescue StandardError
        (str.length / 4.0).ceil
      end
    end
  end
end
