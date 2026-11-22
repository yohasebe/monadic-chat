# frozen_string_literal: true

module MonadicSharedTools
  # Who acts on a chat's browser: its tools, or the user from the work
  # screen, one at a time.
  #
  # The user operates the browser through one work screen stream at a time
  # (claim gives an operation number). A tool reserves the browser before it
  # takes the chat's op_lock (BrowserOwner.acting): from then on no input is
  # taken, the operation is being revoked, and the tool waits until the
  # stream says what it pressed was let go (released). A stream that could
  # not let go leaves the browser unusable for the user and for tools,
  # except those that close or replace it (recovery), until the chat's
  # browser is gone (forget).
  #
  # Each reservation has a token of its own; the browser is the user's
  # again only when none is left. State changes are short and under one
  # lock; a tool waits (ConditionVariable) outside every other lock, on the
  # state, not on a signal. The stream learns of a revocation by asking
  # (revoking?), never from another thread.
  #
  # Accepted inputs are counted (acted); the next request tells the agent
  # once (pending_notice, consume). What was typed is never kept.
  module BrowserOperator
    class Unreleased < StandardError
      def initialize(msg = 'What the user pressed in this browser could not be let go. ' \
                           'Close the browser and open it again.')
        super
      end
    end

    # Seconds a tool waits for the user's operation to end.
    RELEASE_LIMIT = 1.5

    State = Struct.new(:instance, :status, :op, :owner, :tokens, :acted, :consumed)

    @lock = Mutex.new
    @changed = ConditionVariable.new
    @states = {}
    @serial = 0
    # The user may operate a browser only when this is on (the page, the
    # notices and a check on a real browser come first).
    @enabled = false

    module_function

    def enabled?
      @enabled
    end

    # For tests.
    def enabled=(value)
      @enabled = value
    end

    # The user asks to operate the chat's browser (instance) through owner:
    # an operation number, or why not (:disabled, :busy, :taken, :unavailable).
    def claim(chat, instance, owner)
      return :disabled unless enabled?

      @lock.synchronize do
        state = @states[chat]
        if state
          next :busy unless state.tokens.empty?
          next :unavailable if state.status == :unavailable
          next :busy if state.status == :revoking
          if state.status == :active
            next state.owner.equal?(owner) && state.instance == instance ? state.op : :taken
          end
          # Another browser of the chat: what was counted was of the one before.
          start_browser(state, instance) if state.instance != instance
        else
          state = @states[chat] = fresh(instance)
        end

        state.status = :active
        state.op = (@serial += 1)
        state.owner = owner
        state.op
      end
    end

    # Whether an input of op may go to the browser now.
    def accept?(chat, op)
      @lock.synchronize { active?(@states[chat], op) }
    end

    # An input of op was taken: counted for the agent. False when op no
    # longer holds.
    def acted(chat, op)
      @lock.synchronize do
        state = @states[chat]
        next false unless active?(state, op)

        state.acted += 1
        true
      end
    end

    # Whether op is being revoked (a tool reserved the browser): the stream
    # stops taking input and lets go of what it pressed. A stream that finds
    # accept? false for any other reason stops as well (a wait that timed
    # out leaves the browser unavailable, no longer revoking).
    def revoking?(chat, op)
      @lock.synchronize do
        state = @states[chat]
        !!(state && state.op == op && state.status == :revoking)
      end
    end

    # The user ends op (or the stream does): it lets go of what it pressed
    # next, then says released.
    def ending(chat, op)
      @lock.synchronize do
        state = @states[chat]
        state.status = :revoking if state && state.op == op && state.status == :active
      end
    end

    # The stream let go of what op pressed (ok), or could not tell (not ok).
    def released(chat, op, ok:)
      @lock.synchronize do
        state = @states[chat]
        next unless state && state.op == op && %i[active revoking].include?(state.status)

        state.status = ok ? :idle : :unavailable
        state.owner = nil
        @changed.broadcast
      end
    end

    # A tool reserves the chat's browser: a token for done.
    def reserve(chat)
      @lock.synchronize do
        state = (@states[chat] ||= fresh(nil))
        token = Object.new
        state.tokens << token
        state.status = :revoking if state.status == :active
        token
      end
    end

    # Waits until the user's operation has ended: :released, :unavailable,
    # or :timeout (which is not a release: the browser is then unavailable).
    def await_released(chat, timeout: RELEASE_LIMIT)
      deadline = clock + timeout
      @lock.synchronize do
        loop do
          state = @states[chat]
          break :released if state.nil? || state.status == :idle
          break :unavailable if state.status == :unavailable

          left = deadline - clock
          if left <= 0
            state.status = :unavailable
            state.owner = nil
            @changed.broadcast
            break :timeout
          end
          @changed.wait(@lock, left)
        end
      end
    end

    def done(chat, token)
      @lock.synchronize do
        state = @states[chat]
        state&.tokens&.delete(token)
      end
    end

    # Runs the block as the chat's tool: the user's operation ends first.
    # A tool that is not a recovery is refused (Unreleased) when it could
    # not end.
    def as_tool(chat, recovery: false)
      token = reserve(chat)
      result = await_released(chat)
      raise Unreleased if result != :released && !recovery

      yield
    ensure
      done(chat, token) if token
    end

    Notice = Struct.new(:instance, :count)

    # What to tell the agent of the inputs taken on the chat's browser since
    # it was last told (a Notice), or nil.
    def pending_notice(chat)
      @lock.synchronize do
        state = @states[chat]
        state && state.acted > state.consumed ? Notice.new(state.instance, state.acted) : nil
      end
    end

    # The agent was told notice; one of another browser tells nothing here.
    def consume(chat, notice)
      @lock.synchronize do
        state = @states[chat]
        next unless state && notice && state.instance == notice.instance

        state.consumed = [state.consumed, notice.count].max
      end
    end

    # The chat's browser is gone: what was held for it goes too.
    def forget(chat)
      @lock.synchronize do
        state = @states[chat]
        next unless state

        # A tool still waiting keeps its reservation.
        if state.tokens.empty?
          @states.delete(chat)
        else
          start_browser(state, nil)
        end
        @changed.broadcast
      end
    end

    # For tests.
    def reset!
      @lock.synchronize do
        @states.clear
        @serial = 0
        @changed.broadcast
      end
    end

    def clock
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def fresh(instance)
      State.new(instance, :idle, nil, nil, [], 0, 0)
    end

    # The state is of browser instance from now on: nothing of the one
    # before stays but the tools' reservations.
    def start_browser(state, instance)
      state.instance = instance
      state.status = :idle
      state.op = nil
      state.owner = nil
      state.acted = 0
      state.consumed = 0
    end

    def active?(state, op)
      !!(state && state.op == op && state.status == :active)
    end
  end
end
