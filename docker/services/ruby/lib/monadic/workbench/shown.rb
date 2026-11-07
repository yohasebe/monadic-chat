# frozen_string_literal: true

require 'securerandom'

module Monadic
  module Workbench
    # What the user is about to show the assistant from the work screen
    # ("Show to the assistant"), held for the message being written: one
    # entry per press (an operation the page names), bound to the tab's
    # connection, the chat and its epoch. An entry is being prepared, then
    # ready (with what was taken, under an id the page attaches to its
    # message), handed to a message being accepted, and ends taken by it
    # (what it held then belongs to the message's request), removed, failed
    # or expired; an ended one is remembered a while (ENDED_LIMIT at most)
    # so that a late completion or a resent press does not bring it back.
    #
    # A draft (a connection's generation in a chat) holds DRAFT_ENTRIES at
    # most, of IMAGE_BYTES and TEXT_CHARS; all drafts hold ALL_ENTRIES and
    # ALL_IMAGE_BYTES. An entry being prepared counts already. What is not
    # taken within TTL is let go, whether or not anything else happens.
    module Shown
      DRAFT_ENTRIES = 8
      IMAGE_BYTES = 24 * 1024 * 1024
      TEXT_CHARS = 256_000
      ALL_ENTRIES = 64
      ALL_IMAGE_BYTES = 8 * IMAGE_BYTES
      TTL = 30 * 60
      ENDED_TTL = 10 * 60
      ENDED_LIMIT = 256
      SWEEP_EVERY = 60
      OP_ID = /\A[0-9a-f]{16}\z/
      SNAPSHOT_ID = /\A[A-Za-z0-9_-]{22}\z/

      class Refused < StandardError
        attr_reader :reason, :ids

        # ids: the snapshot ids that are why (others may still be shown).
        def initialize(reason, message, ids: nil)
          @reason = reason
          @ids = ids
          super(message)
        end
      end

      # One press: its state (preparing, ready, taken, removed, failed,
      # expired) and, once ready, what was taken (seen: the parts of an
      # observation) and what it holds.
      Entry = Struct.new(:op_id, :snapshot_id, :tab, :generation, :chat_id, :epoch, :state, :seen, :image_bytes,
                         :chars, :expires_at, :ended_at, keyword_init: true)

      @entries = {}
      @lock = Mutex.new
      @sweeper = nil

      class << self
        # A press is being prepared: refused (busy) past the limits, and
        # for an operation this draft already has or had.
        def start(tab:, generation:, chat_id:, epoch:, op_id:)
          raise Refused.new('unknown', 'the operation is not one the page can name') unless op_id.to_s.match?(OP_ID)

          start_sweeper
          @lock.synchronize do
            sweep
            key = [tab.to_s, generation, op_id]
            raise Refused.new('unknown', 'this was already shown') if @entries.key?(key)

            open = @entries.values.reject { |e| ended?(e) }
            raise Refused.new('busy', 'too much is being shown now') if open.size >= ALL_ENTRIES
            if draft(open, tab, generation, chat_id).size >= DRAFT_ENTRIES
              raise Refused.new('busy', 'this message already shows as much as it can')
            end

            @entries[key] = Entry.new(op_id: op_id, tab: tab.to_s, generation: generation, chat_id: chat_id, epoch: epoch,
                                      state: 'preparing', image_bytes: 0, chars: 0,
                                      expires_at: clock + TTL)
          end
        end

        # What was taken for the press is ready (seen, with :image and the
        # text parts): its entry, with its snapshot_id; nil when the press
        # ended meanwhile (removed, Reset...), and then nothing is kept.
        # Refused (too_large) past the draft's or all limits.
        def finish(tab:, generation:, op_id:, seen:)
          bytes = seen[:image] ? seen[:image].bytes.bytesize : 0
          chars = seen[:text].to_s.length + seen[:selection].to_s.length
          @lock.synchronize do
            entry = @entries[[tab.to_s, generation, op_id]]
            next nil unless entry&.state == 'preparing' && entry.expires_at > clock

            holding = @entries.values.select { |e| %w[ready handing].include?(e.state) }
            ready = draft(holding, tab, generation, entry.chat_id)
            all = holding
            if ready.sum(&:image_bytes) + bytes > IMAGE_BYTES || ready.sum(&:chars) + chars > TEXT_CHARS ||
               all.sum(&:image_bytes) + bytes > ALL_IMAGE_BYTES
              end!(entry, 'failed')
              raise Refused.new('too_large', 'this message cannot show more than this')
            end

            entry.seen = seen
            entry.image_bytes = bytes
            entry.chars = chars
            entry.snapshot_id = SecureRandom.urlsafe_base64(16)
            entry.state = 'ready'
            entry.dup
          end
        end

        def failed(tab:, generation:, op_id:)
          @lock.synchronize do
            entry = @entries[[tab.to_s, generation, op_id]]
            end!(entry, 'failed') if entry && !ended?(entry)
          end
        end

        # The user took the press back (being prepared or ready).
        def remove(tab:, generation:, op_id:)
          @lock.synchronize do
            entry = @entries[[tab.to_s, generation, op_id]]
            end!(entry, 'removed') if entry && !ended?(entry)
          end
        end

        # The entries of snapshot_ids, handed all at once to a message sent
        # from the tab's connection in chat_id at epoch, or none: refused
        # when any of them is not ready, is another draft's, has expired,
        # or holds an image the model does not take (images: false). They
        # stay held (handing) until the message takes them (commit) or gives
        # them back (give_back).
        def take_all(tab:, generation:, chat_id:, epoch:, snapshot_ids:, images:)
          ids = snapshot_ids
          unless ids.is_a?(Array) && !ids.empty? && ids.size <= DRAFT_ENTRIES &&
                 ids.all? { |id| id.is_a?(String) && id.match?(SNAPSHOT_ID) } && ids.uniq.size == ids.size
            raise Refused.new('unknown', 'what the message shows is not what the page was given')
          end

          @lock.synchronize do
            sweep
            entries = ids.map do |id|
              @entries.values.find { |e| e.snapshot_id == id && e.tab == tab.to_s && e.generation == generation }
            end
            gone = ids.each_index.reject { |at| entries[at]&.state == 'ready' }.map { |at| ids[at] }
            unless gone.empty?
              raise Refused.new('expired', 'something the message shows is no longer held; show it again', ids: gone)
            end
            unless entries.all? { |e| e.chat_id == chat_id && e.epoch == epoch }
              raise Refused.new('changed', 'something the message shows was taken in another chat')
            end
            raise Refused.new('vision_unsupported', 'the model does not take images') if !images && entries.any? { |e| e.seen[:image] }

            entries.each { |e| e.state = 'handing' }
            entries.map(&:dup)
          end
        end

        # The message takes what was handed to it, all of it: the entries
        # end, and what they held is the request's now. Refused (nothing
        # taken) when any of them is no longer the one handed, still being
        # handed and within its time (taken back, Private, Reset, expired).
        def commit(handed)
          @lock.synchronize do
            entries = handed.map { |copy| @entries[[copy.tab, copy.generation, copy.op_id]] }
            gone = entries.zip(handed).reject do |entry, copy|
              entry && entry.snapshot_id == copy.snapshot_id && entry.state == 'handing' && entry.expires_at > clock
            end
            unless gone.empty?
              raise Refused.new('expired', 'something the message shows is no longer held; show it again',
                                ids: gone.map { |_entry, copy| copy.snapshot_id })
            end

            entries.each { |entry| end!(entry, 'taken') }
          end
        end

        # What was handed to a message that was not accepted after all is
        # ready again, unless it was let go meanwhile (removed, Private,
        # Reset, expired): then it stays ended.
        def give_back(handed)
          @lock.synchronize do
            handed.each do |copy|
              entry = @entries[[copy.tab, copy.generation, copy.op_id]]
              entry.state = 'ready' if entry&.state == 'handing' && entry.expires_at > clock
            end
          end
        end

        # The entries of a tab's connection (generation; or all but
        # except_generation) are let go.
        def revoke_tab(tab, generation: nil, except_generation: nil)
          revoke do |e|
            e.tab == tab.to_s && (generation.nil? || e.generation == generation) &&
              (except_generation.nil? || e.generation != except_generation)
          end
        end

        # The entries of a chat are let go (Reset, Private).
        def revoke_chat(chat_id)
          revoke { |e| e.chat_id == chat_id }
        end

        # The press's state now, or nil.
        def state(tab:, generation:, op_id:)
          @lock.synchronize { @entries[[tab.to_s, generation, op_id]]&.state }
        end

        def reset!
          @lock.synchronize { @entries.clear }
        end

        def sweep_now
          @lock.synchronize { sweep }
        end

        private

        def clock
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end

        def ended?(entry)
          %w[taken removed failed expired].include?(entry.state)
        end

        def draft(entries, tab, generation, chat_id)
          entries.select { |e| e.tab == tab.to_s && e.generation == generation && e.chat_id == chat_id }
        end

        # Ends entry: what it held is let go (its record of having been is
        # kept a while).
        def end!(entry, state)
          entry.state = state
          entry.seen = nil
          entry.image_bytes = 0
          entry.chars = 0
          entry.ended_at = clock
        end

        def revoke
          @lock.synchronize do
            @entries.each_value { |e| end!(e, 'removed') if !ended?(e) && yield(e) }
          end
          # Presses waiting for a worker (Show) look again.
          Monadic::Workbench::Show.wake if defined?(Monadic::Workbench::Show)
        end

        # Under the lock: what has expired is let go; what ended long ago, or
        # past ENDED_LIMIT of them, is forgotten.
        def sweep
          now = clock
          @entries.each_value { |e| end!(e, 'expired') if !ended?(e) && e.expires_at <= now }
          @entries.delete_if { |_, e| e.ended_at && now - e.ended_at > ENDED_TTL }
          ended = @entries.select { |_, e| e.ended_at }.sort_by { |_, e| e.ended_at }
          ended.first([ended.size - ENDED_LIMIT, 0].max).each { |key, _| @entries.delete(key) }
        end

        public

        # Seconds left before what entry holds is let go.
        def left(entry)
          [(entry.expires_at - clock).floor, 0].max
        end

        # Expired entries are let go even when nothing else happens.
        def start_sweeper
          return if @sweeper&.alive?

          @sweeper = Thread.new do
            loop do
              sleep SWEEP_EVERY
              sweep_now
            end
          end
        end
      end
    end
  end
end
