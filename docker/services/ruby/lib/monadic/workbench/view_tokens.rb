# frozen_string_literal: true

require 'securerandom'

module Monadic
  module Workbench
    # The short-lived tokens in the address of a candidate's image
    # (/workbench/asset/<token>). An HTTP request does not carry the tab's
    # connection, so the address itself is the permission: each token names
    # one item's candidate (by its sha256), for the tab and
    # connection generation it was given to, in one chat at one epoch, and
    # works for TTL seconds. The page asks for new ones over the main socket.
    # Kept in memory only, apart from the tokens that save or remove an image
    # (Approvals), which have no expiry.
    module ViewTokens
      TTL = 300
      LIMIT = 512

      View = Struct.new(:tab, :generation, :chat_id, :epoch, :item_id, :sha256, :expires_at, keyword_init: true)

      @views = {}
      @lock = Mutex.new

      module_function

      def issue(tab:, generation:, chat_id:, epoch:, item_id:, sha256:, now: clock)
        token = SecureRandom.hex(16)
        view = View.new(tab: tab.to_s, generation: generation, chat_id: chat_id, epoch: epoch, item_id: item_id,
                        sha256: sha256, expires_at: now + TTL)
        @lock.synchronize do
          @views.delete_if { |_, v| v.expires_at <= now }
          @views.delete(@views.keys.first) while @views.size >= LIMIT
          @views[token] = view
        end
        token
      end

      # The view of a token that has not expired, or nil.
      def view(token, now: clock)
        return nil unless token.is_a?(String) && token.match?(/\A\h{32}\z/)

        @lock.synchronize do
          view = @views[token]
          next nil unless view

          if view.expires_at <= now
            @views.delete(token)
            next nil
          end
          view
        end
      end

      def drop_connection(tab, generation)
        @lock.synchronize { @views.delete_if { |_, v| v.tab == tab.to_s && v.generation == generation } }
      end

      def drop_chat(chat_id)
        @lock.synchronize { @views.delete_if { |_, v| v.chat_id == chat_id } }
      end

      def clock
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      # For tests.
      def reset!
        @lock.synchronize { @views.clear }
      end
    end
  end
end
