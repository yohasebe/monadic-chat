# frozen_string_literal: true

module Monadic
  module MCP
    # Process-level token budget for the Conduit surface.
    #
    # Conduit's first principle for cost safety (design §5): the platform — not
    # the calling CLI agent — enforces the ceiling. Every Conduit tool that
    # spends provider tokens reserves against this budget BEFORE the call (a
    # hard ceiling that refuses runaway work) and settles the reservation with
    # the actual usage AFTER. A reservation holds its tokens until it is
    # settled, so calls running at the same time cannot each see the same
    # remaining budget and go over it together. A call that ends without
    # settling (an exception, an error reply, or the job killed) is charged
    # what it reserved: it may have sent its request.
    #
    # Most reservations are fixed estimates, so the ceiling bounds what calls
    # are allowed to start with, not the provider's exact bill: a reply longer
    # than its estimate is still recorded in full.
    #
    # Currency is *tokens*, not dollars: model_spec.js carries no pricing, so a
    # token ceiling is the honest, provider-agnostic unit. Counts are estimated
    # with the shared tiktoken tokenizer (send_query does not expose provider
    # usage), which is approximate across providers but sufficient as a safety
    # backstop. Caveat: the estimate counts only VISIBLE text, so reasoning/
    # thinking models (hidden tokens billed at the output rate) would be
    # undercounted by up to an order of magnitude; the query path compensates by
    # charging such models the reserved output (see Conduit#hidden_reasoning_capable?).
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
      @reserved = 0

      # Tokens held for one call. `charge` spends from them as requests go out
      # (holding more when the call needs it and the budget allows), `settle`
      # records what the call spent and gives back what it did not use, and
      # `close` (always, in an ensure) ends a call that was not settled. For a
      # single request, close charges what is still held: the request may have
      # gone out. A call charged as it sends (`pay_as_sent`) has paid for every
      # request that went out, so close gives back the rest.
      class Reservation
        attr_reader :held

        # `keep` is the part `charge` leaves alone: what the reply is held
        # for while the requests are paid for.
        def initialize(held, pay_as_sent: false, keep: 0)
          @held = held
          @pay_as_sent = pay_as_sent
          @keep = keep.to_i.clamp(0, held)
          @open = true
        end

        # Spends `tokens` of the reservation, holding more first if they are
        # not enough. false, with nothing spent, when the budget cannot cover
        # them: the request must not be sent.
        def charge(tokens)
          tokens = tokens.to_i
          CostGuard.update do
            next false unless @open

            extra = tokens - (@held - @keep)
            if extra.positive?
              next false if extra > CostGuard.unheld_remaining

              CostGuard.move(reserved: extra)
              @held += extra
            end
            CostGuard.move(reserved: -tokens, spent: tokens)
            @held -= tokens
            true
          end
        end

        # Records the spend that was not charged as it went (the reply, or the
        # whole call for a single request) and gives back the rest.
        def settle(tokens = 0)
          finish(tokens.to_i)
        end

        def close
          finish(@pay_as_sent ? 0 : nil)
        end

        private

        # nil spends what is still held.
        def finish(tokens)
          CostGuard.update do
            next unless @open

            CostGuard.move(reserved: -@held, spent: tokens || @held)
            @held = 0
            @open = false
          end
        end
      end

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

      def reserved
        @mutex.synchronize { @reserved }
      end

      # What is neither spent nor held by a call still running.
      def remaining
        @mutex.synchronize { unheld_remaining }
      end

      # Holds `projected` tokens for the call made in the block, which gets
      # the Reservation, and closes it when the block ends however it ends.
      # Raises BudgetExceeded, without running the block, when they are not
      # left. Killing the thread cannot come between holding the tokens and
      # closing them: the interrupt waits until the block runs, and until
      # the reservation is closed.
      def reserving(projected, pay_as_sent: false, keep: 0)
        Thread.handle_interrupt(Object => :never) do
          reservation = reserve!(projected, pay_as_sent: pay_as_sent, keep: keep)
          begin
            Thread.handle_interrupt(Object => :immediate) { yield reservation }
          ensure
            reservation.close
          end
        end
      end

      # The hold itself; callers use `reserving`, which closes it.
      def reserve!(projected, pay_as_sent: false, keep: 0)
        projected = projected.to_i
        update do
          remain = unheld_remaining
          if projected > remain
            raise BudgetExceeded,
                  "projected #{projected} tokens exceeds remaining budget " \
                  "#{remain} (ceiling #{budget_total}, already spent #{@spent}, held by running calls #{@reserved})"
          end
          @reserved += projected
          Reservation.new(projected, pay_as_sent: pay_as_sent, keep: keep)
        end
      end

      # Reset cumulative spend (test/admin use).
      def reset!
        @mutex.synchronize do
          @spent = 0
          @reserved = 0
        end
      end

      def status
        total = budget_total
        used, held = @mutex.synchronize { [@spent, @reserved] }
        {
          token_budget: total,
          tokens_spent: used,
          tokens_reserved: held,
          tokens_remaining: [total - used - held, 0].max
        }
      end

      # One change to the ledger, under the lock and not interrupted halfway
      # (a killed thread stops after it, not inside it).
      def update(&block)
        Thread.handle_interrupt(Object => :never) { @mutex.synchronize(&block) }
      end

      def unheld_remaining
        [budget_total - @spent - @reserved, 0].max
      end

      def move(reserved: 0, spent: 0)
        @reserved += reserved
        @spent += spent
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
