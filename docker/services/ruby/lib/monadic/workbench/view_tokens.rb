# frozen_string_literal: true

require 'securerandom'

module Monadic
  module Workbench
    # The short-lived tokens in the address of an image of the workbench
    # (/workbench/asset/<token>). An HTTP request does not carry the tab's
    # connection, so the address itself is the permission: each token names
    # one image (its ledger id) or one file item of the board (its item id),
    # with the version it is for (sha256), and what it is for (:view, shown
    # in the page, or :download, saved as a file), for the tab and
    # connection generation it was given to, in one chat at one epoch, and
    # works for TTL seconds. The page asks for new ones over the main socket.
    # Kept in memory only (as are the tokens that remove an image,
    # Approvals, which have no expiry).
    module ViewTokens
      TTL = 300
      LIMIT = 512

      PURPOSES = %i[view download].freeze

      View = Struct.new(:tab, :generation, :chat_id, :epoch, :artifact_id, :item_id, :sha256, :purpose, :expires_at,
                        keyword_init: true)

      @views = {}
      @lock = Mutex.new

      module_function

      def issue(tab:, generation:, chat_id:, epoch:, sha256:, artifact_id: nil, item_id: nil, purpose: :view, now: clock)
        raise ArgumentError, 'unknown purpose' unless PURPOSES.include?(purpose)
        raise ArgumentError, 'a token names one image or one file' unless [artifact_id, item_id].compact.size == 1

        token = SecureRandom.hex(16)
        view = View.new(tab: tab.to_s, generation: generation, chat_id: chat_id, epoch: epoch, artifact_id: artifact_id,
                        item_id: item_id, sha256: sha256, purpose: purpose, expires_at: now + TTL)
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
