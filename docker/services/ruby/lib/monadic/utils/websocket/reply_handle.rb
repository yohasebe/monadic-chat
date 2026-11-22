# frozen_string_literal: true

require 'securerandom'

module WebSocketHelper
  # One answer being written (an answer to a user's message), from the moment
  # it is accepted until it has ended. Its phase goes waiting (the worker has
  # not begun) → running → answered (what it made is in the queue) → saving
  # (the HTML handler took it to record) → ended (its end was given:
  # finish_reply ran). Cancelling it is a mark that never goes away, apart
  # from the phase: what waits on it can still tell, after it ended, that it
  # was cancelled.
  #
  # Who ends it: the worker, for every end but a recorded answer (its ensure
  # gives "no_reply" when the answer was not taken to be recorded); the HTML
  # handler, for an answer it took (saving); whoever made the worker, when
  # the worker could not be made. What stops it only cancels it and wakes
  # what waits (Replies.stop_and_settle), never ends it in the worker's
  # place.
  #
  # Under its lock only the phase and marks change; nothing is joined,
  # written or sent there.
  class ReplyHandle
    PHASES = %i[waiting running answered saving ended].freeze

    attr_reader :request_id, :chat_id, :tab, :generation

    def initialize(request_id:, chat_id:, tab:, generation:)
      @request_id = request_id
      @chat_id = chat_id
      @tab = tab.to_s
      @generation = generation
      @lock = Mutex.new
      @changed = ConditionVariable.new
      @phase = :waiting
      @cancelled = false
      # The worker gave its end: what it made can no longer be taken.
      @closed = false
      @thread = nil
      @children = []
      @stop_asked_at = nil
      @late = false
    end

    def phase
      @lock.synchronize { @phase }
    end

    def cancelled?
      @lock.synchronize { @cancelled }
    end

    def ended?
      phase == :ended
    end

    # Whether a new answer must wait for this one (one answer at a time): it
    # is still being written, or it is being stopped. An answer made and not
    # cancelled waits for its HTML only and lets the next message in.
    def busy?
      @lock.synchronize do
        next false if @phase == :ended || @phase == :saving

        @cancelled || @phase != :answered
      end
    end

    # The worker that writes it: from now on it may begin.
    def attach(thread)
      @lock.synchronize do
        @thread = thread
        @changed.broadcast
      end
    end

    def attached?
      @lock.synchronize { !@thread.nil? }
    end

    # The worker begins (true) unless the answer was cancelled before it
    # could. It waits until it is attached, so that what cancels it sees the
    # thread it may stop.
    def begin!
      @lock.synchronize do
        @changed.wait(@lock) while @thread.nil?
        next false if @cancelled || @phase != :waiting

        @phase = :running
        true
      end
    end

    # What the worker made goes to the queue (the block puts it there) only
    # while it is running and not cancelled: the two decisions are one. Run
    # with interrupts held off by the caller, so that what was put is never
    # left as not put.
    def answer!
      @lock.synchronize do
        next false if @cancelled || @phase != :running

        yield
        @phase = :answered
        @changed.broadcast
        true
      end
    end

    # The worker, having answered, waits until the answer is taken to be
    # recorded (it may be recorded and ended before the worker comes to
    # wait) or is cancelled.
    def await_handoff
      @lock.synchronize do
        @changed.wait(@lock) while @phase == :answered && !@cancelled
      end
    end

    # The HTML handler takes the answer to record it: it can, unless it was
    # cancelled first. From here a Cancel no longer stops it.
    def take_for_saving
      @lock.synchronize do
        next false if @cancelled || @closed || @phase != :answered

        @phase = :saving
        @changed.broadcast
        true
      end
    end

    # The worker's own end: true when the end is the worker's to give (the
    # answer was not taken to be recorded); what it made can then no longer
    # be taken. (Not a Cancel: an answer that failed was not cancelled.)
    def worker_owns_end!
      @lock.synchronize do
        next false if @phase == :saving || @phase == :ended

        @closed = true
        @changed.broadcast
        true
      end
    end

    # Cancels it (once; asking again changes nothing). What it returns is
    # what the caller stops, outside the lock: the worker's thread when it is
    # running (a worker that has not begun ends at its gate, and one that has
    # answered ends when woken), and the work it started of its own.
    def cancel!
      @lock.synchronize do
        next [nil, []] if @phase == :saving || @phase == :ended

        first = !@cancelled
        @cancelled = true
        @stop_asked_at ||= clock
        @changed.broadcast
        next [nil, []] unless first

        [(@phase == :running ? @thread : nil), @children.dup]
      end
    end

    # Work the answer starts of its own (speech for it): held with the
    # answer, and refused (false) once it was cancelled, so that nothing it
    # starts is left behind by a Cancel.
    def adopt(child)
      @lock.synchronize do
        next false if @cancelled

        @children << child
        true
      end
    end

    # A file the answer writes (put_on_workbench): allowed while it is
    # running and not cancelled, decided once here. A Cancel that comes
    # after does not undo it: the file is written whole (the writer holds
    # off the stop) and stays. Only the decision is made under the lock.
    def admit_write
      @lock.synchronize { !@cancelled && @phase == :running }
    end

    def end!
      late = @lock.synchronize do
        @phase = :ended
        @changed.broadcast
        @late
      end
      Monadic::Utils::ExtraLogger.log { "[Reply] #{@request_id} ended after a stop that went past #{REPLY_STOP_WAIT}s" } if late
      Replies.forget(self)
    end

    # Waits for what the HTML handler and Play wait for: the answer made
    # (answered) or the answer over (ended). A cancelled answer is to be
    # waited for until it ended (wait_ended), never left while it may still
    # write.
    def wait_answer
      @lock.synchronize do
        @changed.wait(@lock) until @phase == :answered || @phase == :saving || @phase == :ended || @cancelled
        @cancelled && @phase != :ended ? :cancelled : @phase
      end
    end

    # Waits until it has ended. Past REPLY_STOP_WAIT seconds from when it was
    # first asked to stop, that is noted once (the request, never what it
    # holds; once for all who wait), and the wait goes on.
    def wait_ended
      loop do
        note = false
        over = @lock.synchronize do
          next true if @phase == :ended

          notice_at = @stop_asked_at && !@late ? @stop_asked_at + REPLY_STOP_WAIT : nil
          if notice_at && clock >= notice_at
            @late = true
            note = true
          else
            @changed.wait(@lock, notice_at && notice_at - clock)
          end
          false
        end
        return if over

        Monadic::Utils::ExtraLogger.log { "[Reply] #{@request_id} is still stopping after #{REPLY_STOP_WAIT}s" } if note
      end
    end

    private

    def clock
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end

  # The answers being written, and the tokens a page stops one with by HTTP
  # (ReplyCancelServer): a token is given only to the connection the answer
  # runs for, and is the permission to stop it. Tokens are held for TOKENS
  # answers at most: past that a new answer gets none (its page stops it by
  # the WebSocket Cancel only); one that runs keeps its own.
  module Replies
    TOKENS = 256
    TOKEN = /\A[A-Za-z0-9_-]{43}\z/

    @handles = {}
    @tokens = {}
    @lock = Mutex.new

    class << self
      # A new answer: its handle, and its token (nil past TOKENS).
      def open(request_id:, chat_id:, tab:, generation:)
        handle = ReplyHandle.new(request_id: request_id, chat_id: chat_id, tab: tab, generation: generation)
        @lock.synchronize do
          @handles[request_id] = handle
          next [handle, nil] if @tokens.size >= TOKENS

          token = SecureRandom.urlsafe_base64(32)
          @tokens[token] = handle
          [handle, token]
        end
      end

      def find(request_id)
        @lock.synchronize { @handles[request_id] }
      end

      # The answer a token stops, or nil (not a token, not given, ended).
      def by_token(token)
        return nil unless token.is_a?(String) && token.match?(TOKEN)

        @lock.synchronize { @tokens[token] }
      end

      def forget(handle)
        @lock.synchronize do
          @handles.delete(handle.request_id) if @handles[handle.request_id].equal?(handle)
          @tokens.delete_if { |_, h| h.equal?(handle) }
        end
      end

      # The tokens of a tab's connection are no longer good (it closed).
      def forget_tokens(tab, generation)
        @lock.synchronize { @tokens.delete_if { |_, h| h.tab == tab.to_s && h.generation == generation } }
      end

      # Cancels the answer and stops what it runs, without waiting.
      def cancel(handle)
        thread, children = handle.cancel!
        # The stop is known from now on to whatever next builds a request
        # for the chat (a new connection of the tab too), before the worker
        # has ended; a failure to note it never keeps the answer running.
        note_stopped(handle)
        thread&.kill
        Monadic::Workbench::Capture.revoke_request(handle.request_id) if defined?(Monadic::Workbench::Capture)
        children.each { |child| stop_child(child) }
        nil
      end

      def note_stopped(handle)
        return unless handle.cancelled? && defined?(Monadic::Workspace::StoppedReplies)

        Monadic::Workspace::StoppedReplies.record(handle.chat_id, handle.request_id)
      rescue StandardError => e
        Monadic::Utils::ExtraLogger.log { "[Reply] the stop was not noted: #{e.class}" }
      end

      # Cancels the answer and waits until it has ended: what comes next in
      # the tab's chat does not overlap with what the answer still writes.
      def stop_and_settle(handle)
        cancel(handle)
        handle.wait_ended
      end

      # Speech the answer started, without waiting: the speech its starter
      # has kept is stopped here; what the starter makes after this, it stops
      # itself (the answer was cancelled before this looked).
      def stop_child(child)
        stop_speech(child[:tts_thread])
      end

      # A speech thread, with its prefetches.
      def stop_speech(tts)
        return unless tts.is_a?(Thread)

        Array(tts[:tts_futures]).each { |future| future.kill if future&.alive? }
        tts.kill
      end

      def reset!
        @lock.synchronize do
          @handles.clear
          @tokens.clear
        end
      end
    end
  end
end
