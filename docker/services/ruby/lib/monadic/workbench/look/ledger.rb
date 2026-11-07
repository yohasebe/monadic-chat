# frozen_string_literal: true

require 'securerandom'
require 'time'
require_relative '../../workspace/chats'

module Monadic
  module Workbench
    module Look
      # The looks of one request (a user's message and the reply to it), in
      # the order they were made: what each looked at, its image, the tool
      # call it answered, and how far it went towards the model. Held in
      # memory for the reply and let go when the reply ends (take), or
      # after KEEP_FOR without an end (closed, its records kept).
      #
      # The helper that builds a request to the provider names the looks it
      # puts in (prepare): from then on every post of the request is checked
      # with all of them (held, Attempt), whatever the body's text says, and
      # settles them. The thread that built it keeps the ledger too
      # (hold_here), so a post after the ledger was let go is refused. An
      # observation the reply ends with in no sent request is unsent.
      class Ledger
        OBSERVATIONS = 8
        IMAGE_BYTES = 24 * 1024 * 1024
        TEXT_CHARS = 256_000
        # Ledgers held at once, and the images all of them hold, at most:
        # past either a new look is refused (busy); a ledger in use is never
        # let go to make room.
        LEDGERS = 64
        ALL_IMAGE_BYTES = 8 * IMAGE_BYTES
        KEEP_FOR = 2 * 60 * 60
        # How long a closed ledger's records are kept for its reply's end.
        DROP_AFTER = 24 * 60 * 60
        THREAD_KEY = :monadic_workbench_look_ledger
        # How far an observation went: read and kept (acquired); put in a
        # request to the provider (embedded); the provider answered that
        # request with success (sent); stopped before it was sent (unsent);
        # answered with an error (refused); sent and then lost, so whether
        # the provider took it is not known (unknown).
        STATES = %w[acquired embedded sent unsent refused unknown].freeze

        # An observation's id, as it is written in what a request holds.
        ID = /look_[0-9a-f]{16}/

        Observation = Struct.new(:id, :tool_call_id, :item_id, :kind, :name, :path, :version, :scope, :at, :image,
                                 :result, :caption, :text_chars, :lines, :truncated, :empty, :state, :image_sha256,
                                 :source, keyword_init: true)

        @ledgers = {}
        # The image bytes all ledgers hold, reserved before an image is kept
        # and given back when its ledger closes.
        @image_total = 0
        @ledgers_lock = Mutex.new

        class << self
          # The ledger of a request, made the first time. session: the
          # chat's session (where the reply's trace goes). Refused (busy)
          # when LEDGERS are open.
          def for(chat_id, epoch, request_id, session: nil, tab: nil)
            key = [chat_id, epoch, request_id]
            expired = []
            ledger = @ledgers_lock.synchronize do
              expired = expired_ledgers
              unless @ledgers.key?(key)
                open = @ledgers.values.count { |l| !l.closed? } - expired.size
                raise Refused.new('busy', 'the work screen is being looked at by too many replies now') if open >= LEDGERS

                @ledgers[key] = new(chat_id, epoch, request_id, session, tab)
              end
              @ledgers[key]
            end
            ledger
          ensure
            # Outside the lock of all ledgers: closing takes the ledger's own.
            expired&.each(&:close!)
          end

          # The ledger of the request of chat_id, made at any epoch (a
          # Reset does not hide what a reply already holds), or nil.
          def of_request(chat_id, request_id)
            return nil unless chat_id && request_id

            @ledgers_lock.synchronize do
              @ledgers.find { |(c, _e, r), _| c == chat_id && r == request_id }&.last
            end
          end

          # The ledger of the request of chat_id at the chat's epoch now, or
          # nil.
          def find(chat_id, request_id)
            ledger = of_request(chat_id, request_id)
            ledger if ledger && ledger.epoch == Monadic::Workspace::Chats.epoch(chat_id)
          end

          # The reply of request_id ended: its ledger is let go, closed (see
          # close!). Returns it, or nil.
          # Not stopped in between (Cancel): a ledger taken is closed.
          def take(request_id)
            Thread.handle_interrupt(Object => :never) do
              ledger = @ledgers_lock.synchronize do
                key = @ledgers.keys.find { |_c, _e, r| r == request_id }
                key && @ledgers.delete(key)
              end
              ledger&.close!
              ledger
            end
          end

          # Reserves bytes of the images all ledgers may hold: false when
          # they do not fit.
          def reserve(bytes)
            @ledgers_lock.synchronize do
              next false if @image_total + bytes > ALL_IMAGE_BYTES

              @image_total += bytes
              true
            end
          end

          def release(bytes)
            @ledgers_lock.synchronize { @image_total = [@image_total - bytes, 0].max }
          end

          # The thread that builds the requests of ledger's request keeps
          # it, for each post of them to be checked even after the ledger
          # is let go.
          def hold_here(ledger)
            Thread.current[THREAD_KEY] = ledger
          end

          # The ledger this thread keeps for the request request_id, or nil.
          def held_here(chat_id, request_id)
            ledger = Thread.current[THREAD_KEY]
            ledger if ledger && ledger.chat_id == chat_id && ledger.request_id == request_id
          end

          def reset!
            @ledgers_lock.synchronize do
              @ledgers.clear
              @image_total = 0
            end
          end

          private

          # Ledgers open past KEEP_FOR, however long, to be closed (their
          # reply is let go: what they hold is released, and a request that
          # still holds them is not sent). Only a closed ledger is dropped,
          # DROP_AFTER after it closed; until then its records are there for
          # the reply's end to find.
          def expired_ledgers
            now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            @ledgers.delete_if { |_, ledger| (closed_at = ledger.closed_at) && now - closed_at > DROP_AFTER }
            @ledgers.values.select { |ledger| !ledger.closed? && now - ledger.made_at > KEEP_FOR }
          end
        end

        # session, tab: the chat's session and the tab the request came from
        # (where the reply's trace goes, and is saved).
        attr_reader :chat_id, :epoch, :request_id, :made_at, :session, :tab

        def initialize(chat_id, epoch, request_id, session, tab = nil)
          @chat_id = chat_id
          @epoch = epoch
          @request_id = request_id
          @session = session
          @tab = tab
          @made_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          @lock = Mutex.new
          @turn = Mutex.new
          @observations = []
          @reserved = 0
          @held = []
          @closed_at = nil
        end

        # Runs a look (the block) as the only one of the request at a time:
        # busy when another is running.
        def one_at_a_time
          raise Refused.new('busy', 'another look of this reply is running') unless @turn.try_lock

          begin
            yield
          ensure
            @turn.unlock
          end
        end

        def closed?
          !closed_at.nil?
        end

        def closed_at
          @lock.synchronize { @closed_at }
        end

        # Keeps what a look saw ({item_id:, kind:, name:, path:, version:,
        # scope:, image: | text: ..., result:, caption:}) as a new
        # observation: its id. Refused past the request's limits and the
        # limit of all ledgers, keeping what is there.
        #
        # The bytes of its image are reserved, then owned by this ledger
        # (given back when it closes): a thread stopped in between (Cancel)
        # stops after, so they are given back once, by one or the other.
        def add(seen)
          image = seen[:image]
          bytes = image ? image.bytes.bytesize : 0
          Thread.handle_interrupt(Object => :never) do
            raise Refused.new('busy', 'the work screen holds too many images now') if bytes.positive? && !Ledger.reserve(bytes)

            owned = false
            begin
              id = add_reserved(seen, image, bytes)
              owned = true
              id
            ensure
              # Not kept: what was reserved for it is given back.
              Ledger.release(bytes) if bytes.positive? && !owned
            end
          end
        end

        def add_reserved(seen, image, bytes)
          @lock.synchronize do
            raise Refused.new('busy', 'the looks of this reply were let go') if @closed_at
            raise Refused.new('too_large', 'this reply has looked at the work screen enough times') if @observations.size >= OBSERVATIONS

            if image && @observations.sum { |o| o.image ? o.image.bytes.bytesize : 0 } + image.bytes.bytesize > IMAGE_BYTES
              raise Refused.new('too_large', 'this reply has looked at too many images')
            end

            chars = seen[:text].to_s.length
            if @observations.sum { |o| o.text_chars.to_i } + chars > TEXT_CHARS
              raise Refused.new('too_large', 'this reply has looked at too much text')
            end

            id = seen[:id] || "look_#{SecureRandom.hex(8)}"
            lines = if seen[:first_line]
                      { first: seen[:first_line], last: seen[:last_line], total: seen[:total_lines],
                        partial: seen[:partial_line] || nil }.compact
                    end
            @observations << Observation.new(
              id: id, item_id: seen[:item_id], kind: seen[:kind], name: seen[:name], path: seen[:path],
              version: seen[:version], scope: seen[:scope], at: Time.now.utc.iso8601, image: image,
              result: seen[:result], caption: seen[:caption], text_chars: image ? nil : chars, lines: lines,
              truncated: seen[:truncated], empty: seen[:empty], state: 'acquired',
              image_sha256: image&.sha256, source: image&.source || seen[:source]
            )
            @reserved += bytes
            id
          end
        end

        # The tool call whose result the observation id is.
        def bind(id, tool_call_id)
          @lock.synchronize do
            observation = @observations.find { |o| o.id == id }
            observation.tool_call_id = tool_call_id.to_s if observation && observation.tool_call_id.nil?
          end
        end

        # The observations that answer one of tool_call_ids, in the order
        # they were made.
        def answering(tool_call_ids)
          ids = tool_call_ids.compact.map(&:to_s)
          @lock.synchronize { @observations.select { |o| o.tool_call_id && ids.include?(o.tool_call_id) } }
        end

        # Those of them with an image.
        def images_for(tool_call_ids)
          answering(tool_call_ids).select(&:image)
        end

        # The observations bound to a tool call that is not among
        # tool_call_ids (a helper that sends only the last round's results
        # leaves the earlier ones out).
        def left_out(tool_call_ids)
          ids = tool_call_ids.compact.map(&:to_s)
          @lock.synchronize { @observations.select { |o| o.tool_call_id && !ids.include?(o.tool_call_id) } }
        end

        # The request being built holds the observations ids: they are
        # embedded until a post of it settles them (Attempt), and each post
        # of the request from now on is checked with them (held).
        def prepare(ids)
          return if ids.empty?

          @lock.synchronize { @held |= ids }
          mark(ids, 'embedded')
        end

        # The ids of the observations put in a request of the reply so far.
        def held
          @lock.synchronize { @held.dup }
        end

        # The observations still holding what they read (text or image).
        def observations_with_content
          @lock.synchronize { @observations.select { |o| o.result || o.image } }
        end

        def observations(ids)
          @lock.synchronize { @observations.select { |o| ids.include?(o.id) } }
        end

        # Observations ids went as far as state.
        def mark(ids, state)
          raise ArgumentError, "unknown state #{state}" unless STATES.include?(state)

          @lock.synchronize do
            @observations.each do |o|
              next unless ids.include?(o.id)

              o.state = settle(o.state, state)
            end
          end
        end

        # The reply ended (or its ledger expired): what was put in a request
        # and never posted was not sent; the images and texts are let go,
        # and their bytes given back. Once only, and not stopped in between
        # (Cancel): the bytes it no longer holds are given back.
        def close!
          Thread.handle_interrupt(Object => :never) do
            released = @lock.synchronize do
              @closed_at ||= Process.clock_gettime(Process::CLOCK_MONOTONIC)
              @observations.each do |o|
                o.state = 'unsent' if o.state == 'embedded'
                o.image = nil
                o.result = nil
                o.caption = nil
              end
              given_back = @reserved
              @reserved = 0
              given_back
            end
            Ledger.release(released) if released.positive?
          end
        end

        # What the reply's message keeps of the looks: what each was (the
        # whole version, the image's own sha256 and where it came from), no
        # bytes and no text.
        def records
          @lock.synchronize do
            @observations.map do |o|
              { 'id' => o.id, 'item_id' => o.item_id, 'kind' => o.kind, 'name' => o.name, 'path' => o.path,
                'version' => o.version, 'image_sha256' => o.image_sha256, 'source' => o.source,
                'scope' => o.scope, 'at' => o.at, 'lines' => o.lines&.transform_keys(&:to_s),
                'truncated' => o.truncated, 'empty' => o.empty, 'image' => o.kind == 'image',
                'state' => o.state }.compact
            end
          end
        end

        private

        # sent is final; unknown stays unless a later request is sent; any
        # other state is replaced by the latest.
        def settle(was, now)
          return was if was == 'sent'
          return now if now == 'sent'
          return was if was == 'unknown'

          now
        end
      end
    end
  end
end
