# frozen_string_literal: true

require 'json'
require 'securerandom'

module Monadic
  module Workbench
    # A one-time request to a tab's page for what its work screen shows now
    # (the lines of a text in view), for a look. The request is written to
    # the connection the look was made for, and nowhere else; the page
    # answers by an HTTP POST to /workbench/capture/<id> (CaptureServer), so
    # that the answer does not wait for the connection's messages to be
    # read. The id is the permission to answer: it is written only to that
    # connection, it is hard to guess, and it is taken once.
    #
    # What the page answers is what it showed when it answered: an answer
    # sent before a change the user made (another item, a Reset) reached
    # the server is taken. The look checks again, before it keeps the
    # observation, that the chat, the connection and the selection are
    # still the ones it asked for; whether the observation may then go to
    # the model is checked when each request is sent (Look::Attempt).
    module Capture
      # How long the page has to answer, at most.
      WAIT = 10
      # How often a waiting look checks again that it may still wait.
      RECHECK = 0.25
      # Captures waiting at once, and answers being read at once.
      PENDING = 8
      READING = 8
      # Bytes of an answer: of what is not an image, and of an image's
      # base64 (asked only when the capture wants an image).
      BODY_LIMIT = 256 * 1024
      IMAGE_LIMIT = 5 * 1024 * 1024
      ID = /\A[A-Za-z0-9_-]{43}\z/

      class Failed < StandardError
        attr_reader :reason

        def initialize(reason, message)
          @reason = reason
          super(message)
        end
      end

      # One request: the tab's connection it was written to, the request it
      # is for, and what came of it (an answer, or why there is none).
      Pending = Struct.new(:id, :tab, :generation, :chat_id, :request_id, :deadline, :wants, :body_limit, :reading,
                           :answer, :failure, keyword_init: true)

      # What an answer may hold, by what was asked for (wants); anything
      # else is left out.
      FIELDS = {
        nil => %w[range note], 'image' => %w[image image_note crop], 'selection' => %w[selection_text selection_cut],
        'relay' => %w[relay relay_browser]
      }.freeze

      @pending = {}
      @reading = 0
      @lock = Mutex.new
      @changed = ConditionVariable.new
      # How a request reaches the page: (tab, generation, chat_id, json) →
      # true when written to that connection. Set by the WebSocket layer.
      @transport = nil

      class << self
        attr_accessor :transport

        # Asks the page of tab's connection (generation) for wants about
        # item_id at version (selection serial), and waits for its answer,
        # until deadline (monotonic seconds) or WAIT, checking every
        # RECHECK that valid still holds. Returns the answer (a Hash) or
        # raises Failed.
        # op: the press the page answers for from what it fixed then (Show),
        # or nil for what it shows now.
        def request(tab:, generation:, chat_id:, request_id:, item_id:, version:, serial:, wants:, deadline:, valid:,
                    op: nil)
          now = clock
          ends = [deadline, now + WAIT].min
          limit = wants.intersect?(%w[image relay]) ? IMAGE_LIMIT + BODY_LIMIT : BODY_LIMIT
          pending = register(tab, generation, chat_id, request_id, ends, wants, limit)
          payload = { 'type' => 'workbench_capture', 'id' => pending.id, 'item_id' => item_id, 'version' => version,
                      'serial' => serial, 'wants' => wants, 'wait_ms' => ((ends - now) * 1000).floor }
          payload['op'] = op if op
          unless transport&.call(tab, generation, chat_id, JSON.generate(payload))
            settle(pending, failure: ['connection_gone', "the tab's page could not be asked"])
          end
          wait(pending, valid)
        ensure
          drop(pending) if pending
        end

        # Reads the answer to id (CaptureServer), of length bytes: the block,
        # given the capture's deadline, reads it (a Hash, or nil when it
        # could not). nil when id is not waiting for an answer, the answer
        # is longer than the capture takes, one is being read for it, or
        # READING answers are being read; otherwise whether the
        # answer read was taken. The room to read is held until the block
        # ends, also when the capture ended meanwhile, and given back once
        # (not stopped in between).
        def reading(id, length)
          Thread.handle_interrupt(Object => :never) do
            deadline = start_reading(id, length)
            return nil unless deadline

            begin
              answer = Thread.handle_interrupt(Object => :immediate) { yield deadline }
              take(id, answer)
            ensure
              end_reading(id)
            end
          end
        end

        # The tab's captures are let go (its connection closed, or a newer
        # connection took the tab: except_generation keeps that one's).
        def revoke_tab(tab, generation: nil, except_generation: nil)
          revoke('the tab\'s connection changed') do |p|
            p.tab == tab.to_s && (generation.nil? || p.generation == generation) &&
              (except_generation.nil? || p.generation != except_generation)
          end
        end

        # The reply of request_id ended.
        def revoke_request(request_id)
          revoke('the reply ended') { |p| p.request_id == request_id }
        end

        # The chat became Private.
        def revoke_chat(chat_id)
          revoke('the chat is Private now') { |p| p.chat_id == chat_id }
        end

        def waiting
          @lock.synchronize { @pending.size }
        end

        def reset!
          @lock.synchronize do
            @pending.clear
            @reading = 0
          end
        end

        private

        def clock
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end

        def register(tab, generation, chat_id, request_id, deadline, wants, body_limit)
          @lock.synchronize do
            raise Failed.new('busy', 'the work screen is being asked by too many replies now') if @pending.size >= PENDING

            id = SecureRandom.urlsafe_base64(32)
            @pending[id] = Pending.new(id: id, tab: tab.to_s, generation: generation, chat_id: chat_id,
                                       request_id: request_id, deadline: deadline, wants: wants, body_limit: body_limit,
                                       reading: false)
          end
        end

        # Waits for an answer: checks valid (outside the lock) every RECHECK.
        def wait(pending, valid)
          loop do
            outcome = @lock.synchronize do
              unless pending.answer || pending.failure
                left = pending.deadline - clock
                @changed.wait(@lock, [left, RECHECK].min) if left.positive?
              end
              if pending.answer || pending.failure
                [pending.answer, pending.failure]
              elsif pending.deadline <= clock
                pending.failure = ['capture_timeout', 'the page did not answer in time']
                [nil, pending.failure]
              end
            end
            if outcome
              answer, failure = outcome
              raise Failed.new(*failure) if failure

              return answer
            end
            settle(pending, failure: ['selection_changed', 'the work screen or the chat changed']) unless valid.call
          end
        end

        # The first of an answer and a failure is kept.
        def settle(pending, failure:)
          @lock.synchronize do
            next if pending.answer || pending.failure

            pending.failure = failure
            @changed.broadcast
          end
        end

        def revoke(why)
          @lock.synchronize do
            @pending.each_value do |pending|
              next if pending.answer || pending.failure || !yield(pending)

              pending.failure = ['cancelled', why]
            end
            @changed.broadcast
          end
        end

        def drop(pending)
          @lock.synchronize { @pending.delete(pending.id) }
        end

        def start_reading(id, length)
          @lock.synchronize do
            pending = @pending[id]
            next nil unless pending && pending.answer.nil? && pending.failure.nil? && !pending.reading
            next nil if length > pending.body_limit
            next nil if @reading >= READING || pending.deadline <= clock

            pending.reading = true
            @reading += 1
            pending.deadline
          end
        end

        # The answer read for id is taken when the capture still waits: of
        # it, only what was asked for, an image's base64 of at most
        # IMAGE_LIMIT and the rest of at most BODY_LIMIT.
        def take(id, answer)
          wants = @lock.synchronize { @pending[id]&.wants }
          answer = kept(answer, wants) if wants
          @lock.synchronize do
            pending = @pending[id]
            next false unless answer.is_a?(Hash) && pending && pending.answer.nil? && pending.failure.nil? &&
                              pending.deadline > clock

            pending.answer = answer
            @changed.broadcast
            true
          end
        end

        def kept(answer, wants)
          return nil unless answer.is_a?(Hash)

          fields = FIELDS[nil] + wants.flat_map { |want| FIELDS.fetch(want, []) }
          answer = answer.slice(*fields)
          images = answer.values_at('image', 'relay').compact
          return nil unless images.size <= 1 && images.all? { |i| i.is_a?(String) && i.bytesize <= IMAGE_LIMIT }
          return nil if JSON.generate(answer.except('image', 'relay')).bytesize > BODY_LIMIT

          answer
        rescue JSON::GeneratorError
          nil
        end

        def end_reading(id)
          @lock.synchronize do
            @reading -= 1
            pending = @pending[id]
            pending.reading = false if pending
          end
        end
      end
    end
  end
end
