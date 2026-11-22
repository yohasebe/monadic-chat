# frozen_string_literal: true

require 'securerandom'

module Monadic
  module WorkScreen
    # The pass a tab's chat socket gives its page for the work screen socket.
    # A tab id only names a tab; the pass shows that the page holds that tab's
    # live connection. It is good once, for TTL seconds, and only while the
    # connection it was issued on is the tab's live one.
    module Tokens
      TTL = 60
      LIMIT = 200

      Grant = Struct.new(:tab, :generation, :expires)

      @lock = Mutex.new
      @grants = {}

      module_function

      def clock
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def issue(tab, generation, now: clock)
        token = SecureRandom.hex(16)
        @lock.synchronize do
          @grants.delete_if { |_, grant| grant.expires <= now }
          @grants.shift while @grants.size >= LIMIT
          @grants[token] = Grant.new(tab.to_s, generation, now + TTL)
        end
        token
      end

      # The grant for token, used up, or nil (unknown, expired, or its
      # connection is no longer the tab's live one).
      def redeem(token, now: clock)
        return nil unless token.is_a?(String) && token.match?(/\A\h{32}\z/)

        grant = @lock.synchronize { @grants.delete(token) }
        return nil unless grant && grant.expires > now
        return nil unless WebSocketHelper.live_generation(grant.tab) == grant.generation

        grant
      end

      # For tests.
      def reset!
        @lock.synchronize { @grants.clear }
      end
    end
  end
end
