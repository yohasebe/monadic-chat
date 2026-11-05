# frozen_string_literal: true

require 'securerandom'

module Monadic
  module Workbench
    # The tokens a tab's connection uses to save or remove an image of the
    # workbench. A token is issued to one connection (tab and generation)
    # for one image (its item and its candidate's sha256), in one chat at
    # one epoch. It has no expiry: it stops working when any of these no
    # longer holds (the connection closed or was replaced, the chat was
    # replaced, the image is gone). Kept in memory only, so none outlives a
    # restart, and never put in a manifest, a snapshot or a tool result.
    module Approvals
      Grant = Struct.new(:tab, :generation, :chat_id, :epoch, :item_id, :sha256, keyword_init: true)

      @grants = {}
      @lock = Mutex.new

      module_function

      # The connection's token for this image: the one it was given before,
      # or a new one.
      def issue(tab:, generation:, chat_id:, epoch:, item_id:, sha256:)
        grant = Grant.new(tab: tab.to_s, generation: generation, chat_id: chat_id, epoch: epoch,
                          item_id: item_id, sha256: sha256)
        @lock.synchronize do
          @grants.key(grant) || SecureRandom.hex(16).tap { |token| @grants[token] = grant }
        end
      end

      # The grant of token when it was issued to this connection, or nil.
      def grant(token, tab:, generation:)
        return nil unless token.is_a?(String) && token.match?(/\A\h{32}\z/)

        grant = @lock.synchronize { @grants[token] }
        return nil unless grant && grant.tab == tab.to_s && grant.generation == generation

        grant
      end

      # The connection closed: its tokens stop working (its tab gets new ones
      # when it comes back).
      def drop_connection(tab, generation)
        @lock.synchronize { @grants.delete_if { |_, g| g.tab == tab.to_s && g.generation == generation } }
      end

      # The chat was replaced: no token of it works any more.
      def drop_chat(chat_id)
        @lock.synchronize { @grants.delete_if { |_, g| g.chat_id == chat_id } }
      end

      # For tests.
      def reset!
        @lock.synchronize { @grants.clear }
      end
    end
  end
end
