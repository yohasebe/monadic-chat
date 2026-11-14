# frozen_string_literal: true

require 'json'
require 'set'
require_relative '../shell'
require_relative '../workspace/chats'
require_relative 'browser_operator'

module MonadicSharedTools
  # Who may open a browser session on the Selenium node, so that no request
  # waits in Selenium's queue and no chat reaches another chat's page.
  #
  # - A chat may keep one browser open (start_browser and the actions after
  #   it). With two or more slots, one is left for short jobs: at most
  #   total - 1 chats keep one at a time (one chat when there is one slot).
  # - A short job (a diagram preview, a page capture or fetch, a check)
  #   opens a session of its own for the job.
  # - A new session is admitted only while a slot is free. The slots in use
  #   are the chats' browsers, the starts and jobs running, and every other
  #   session Selenium reports (/status): one that failed to close, one
  #   opened elsewhere, or a job's own (counted twice while it runs, unless
  #   the job names it). A session that failed to close keeps its slot this
  #   way until Selenium ends it (SE_NODE_SESSION_TIMEOUT); nothing here
  #   tracks it. When Selenium cannot be asked, no session is opened.
  #
  # A chat's browser is used by one call at a time (op_lock). It is closed
  # when the chat is replaced (Reset, another app, an import, another chat
  # from the history) and when it has been unused for IDLE_LIMIT seconds,
  # on a background worker. Each replacement ends an epoch of the chat
  # (Chats.epoch): work begun in an earlier epoch (current_work, kept from
  # when the work began) opens, uses and closes nothing, even when the chat
  # id comes back (history Continue).
  #
  # Whenever a chat stops holding its browser (closed, replaced, idle, or
  # found gone from Selenium), the listeners (on_closed) are told, outside
  # the lock.
  module BrowserOwner
    IDLE_LIMIT = 300
    TICK = 30
    # Seconds to wait for Selenium's report, and for a close.
    STATUS_TIMEOUT = 10
    CLOSE_TIMEOUT = 30
    # Reports taken again when the slots changed while one was read.
    OBSERVE_TRIES = 3

    # instance: a number of its own for each browser opened, so a browser
    # started again in the same chat is told apart. window: the WebDriver
    # window handle the tools act on (Chromium's CDP target id), as the
    # last tool reported it.
    Browser = Struct.new(:session, :used_at, :instance, :epoch, :window)
    # What the work screen may know of a chat's browser.
    View = Struct.new(:chat, :epoch, :instance, :session, :window)

    # A browser session was not opened; the message says why.
    class Refused < StandardError; end

    class Full < Refused
      def initialize(msg = "No browser is free right now: every browser session is in use. Retry when one has finished.")
        super
      end
    end

    class Unavailable < Refused
      def initialize(msg = "The browser service is not available right now. Retry in a moment; " \
                           "if it persists, restart Monadic Chat.")
        super
      end
    end

    @lock = Mutex.new
    @browsers = {}
    @starting = {}
    @jobs = 0
    @job_sessions = Set.new
    # Bumped whenever a slot may have been given up, so that an admission
    # decided on an older report reads Selenium again.
    @revision = 0
    @instances = 0
    # Per chat, kept for good: the lock every caller of the chat waits on.
    @op_locks = {}
    @runner = nil
    @closed_listeners = []
    @queue = Queue.new
    @worker = nil
    @last_reap = 0

    module_function

    def clock
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    # The chat the current work is done for and its epoch when the work
    # began: [chat, epoch], or [nil, nil] outside a chat. Both come from the
    # chat scope EgressGuard sets on the connection when a chat starts,
    # which the work's threads and fibers inherit.
    def current_work
      key = Monadic::Utils::Privacy::EgressGuard::CHAT_KEY if defined?(Monadic::Utils::Privacy::EgressGuard)
      scope = key && Fiber[key]
      return [scope.chat_id, scope.epoch || epoch(scope.chat_id)] if scope&.chat_id

      [Thread.current[:session], Thread.current[:rack_session]].compact.each do |session|
        id = session[:chat_id] || session['chat_id']
        return [id, epoch(id)] if id
      end
      [nil, nil]
    end

    def current_chat
      current_work.first
    end

    # The output of web_navigator.py with args (an Array), run in the Python
    # container.
    def navigator(args, timeout: 120)
      runner = @lock.synchronize { @runner }
      return runner.call(args, timeout) if runner

      stdout, = Monadic::Shell.exec(container: :python, argv: ['web_navigator.py', *args], timeout: timeout)
      stdout
    end

    # For tests: runner.call(args, timeout) in place of the Python container.
    def runner=(callable)
      @lock.synchronize { @runner = callable }
    end

    def op_lock(chat)
      @lock.synchronize { @op_locks[chat] ||= Mutex.new }
    end

    # Runs the block as a tool acting on the chat's browser: the user's
    # operation from the work screen ends first (BrowserOperator), then the
    # block runs under op_lock. recovery: a tool that closes or replaces
    # the browser, which runs even when the user's operation could not end.
    def acting(chat, recovery: false, &block)
      BrowserOperator.as_tool(chat, recovery: recovery) { op_lock(chat).synchronize(&block) }
    rescue BrowserOperator::Unreleased => e
      { success: false, error: e.message }
    end

    # The chat's epoch now; work keeps the one it began in.
    def epoch(chat)
      Monadic::Workspace::Chats.epoch(chat)
    end

    # True while the chat is still in the epoch work began in.
    def live?(chat, work_epoch)
      Monadic::Workspace::Chats.epoch(chat) == work_epoch
    end

    # Admits a start of chat's browser for work of epoch: :ok, or
    # :no_chat, :replaced, :chats_full, :full, :unavailable. The chat holds
    # no browser here (a new start closes the old one first).
    def begin_start(chat, epoch)
      return :no_chat unless chat

      admit do |observed, total|
        next :replaced unless live?(chat, epoch)

        holding = (@browsers.keys | @starting.keys) - [chat]
        next :chats_full if holding.size >= [total - 1, 1].max
        next :full if taken(observed) >= total

        @starting[chat] = true
        :ok
      end
    end

    # The start ended, with the session it made or nil. True when the chat
    # keeps it; false when the chat was replaced meanwhile (the caller has it
    # closed).
    def finish_start(chat, session_id, epoch, window: nil)
      kept = @lock.synchronize do
        @starting.delete(chat)
        @revision += 1
        next false if session_id.nil? || !live?(chat, epoch)

        @browsers[chat] = Browser.new(session_id, clock, @instances += 1, epoch, window)
        true
      end
      start_worker if kept
      kept
    end

    # The chat's browser session for an action of epoch, or nil.
    def session_for(chat, epoch)
      @lock.synchronize do
        browser = live?(chat, epoch) && @browsers[chat]
        next nil unless browser

        browser.used_at = clock
        browser.session
      end
    end

    # True when session is still the browser of chat in epoch (after an
    # action).
    def holds?(chat, session_id, epoch)
      @lock.synchronize do
        browser = @browsers[chat]
        next false unless live?(chat, epoch) && browser && browser.session == session_id

        browser.used_at = clock
        true
      end
    end

    # The chat's browser as the work screen may see it, or nil. Reading it
    # does not count as using the browser (the idle close goes on).
    def view(chat)
      @lock.synchronize do
        browser = @browsers[chat]
        next nil unless browser && live?(chat, browser.epoch)

        View.new(chat, browser.epoch, browser.instance, browser.session, browser.window)
      end
    end

    # A tool on the chat's browser reported the window it acts on now; nil
    # when it could not tell (the work screen then shows nothing).
    def note_window(chat, session_id, window)
      @lock.synchronize do
        browser = @browsers[chat]
        browser.window = window if browser && browser.session == session_id
      end
    end

    def replaced?(chat, epoch)
      !live?(chat, epoch)
    end

    # The chat gives its browser up: its session, for the caller to close,
    # or nil (none, or the work is of an earlier epoch).
    def release(chat, epoch)
      session = @lock.synchronize do
        next nil unless live?(chat, epoch)

        released = @browsers.delete(chat)&.session
        @revision += 1 if released
        released
      end
      closed(chat) if session
      session
    end

    # listener.call(chat) whenever chat stops holding its browser.
    def on_closed(&listener)
      @lock.synchronize { @closed_listeners << listener }
    end

    # Tells the listeners (outside the lock); a listener that fails does
    # not keep the others from being told.
    def closed(chat)
      listeners = @lock.synchronize { @closed_listeners.dup }
      listeners.each do |listener|
        listener.call(chat)
      rescue StandardError
        nil
      end
    end

    # The chat's browser (session_id) was found gone (its CDP connection
    # ended). When Selenium reports it no longer has that session, the chat
    # stops holding it; when Selenium cannot be asked, or still has it, or
    # the chat now holds another browser, nothing changes. True when the
    # chat let it go.
    def confirm_gone(chat, session_id)
      observed = observe
      return false unless observed && !observed[:sessions].include?(session_id)

      forgotten = @lock.synchronize do
        next false unless @browsers[chat]&.session == session_id

        @browsers.delete(chat)
        @revision += 1
        true
      end
      closed(chat) if forgotten
      forgotten
    end

    # confirm_gone on a thread of its own (asking Selenium takes time).
    def confirm_gone_later(chat, session_id)
      Thread.new { confirm_gone(chat, session_id) }.report_on_exception = false
    end

    # A short job: yields name_session, within a slot of its own, or raises
    # Refused (Full, Unavailable). A job that knows its session
    # names it (name_session.call(id)) so that it is not counted twice. The
    # job closes its session itself; one it fails to close keeps its slot,
    # through Selenium's report, until Selenium ends it.
    def with_job
      code = admit do |observed, total|
        next :full if taken(observed) >= total

        @jobs += 1
        :ok
      end
      raise(code == :unavailable ? Unavailable : Full) unless code == :ok

      named = nil
      name_session = lambda do |id|
        named = id
        @lock.synchronize { @job_sessions << id }
      end
      begin
        yield(name_session)
      ensure
        @lock.synchronize do
          @jobs -= 1
          @job_sessions.delete(named) if named
          @revision += 1
        end
      end
    end

    # The chat was replaced (its epoch has ended): its browser is closed in
    # the background.
    def chat_replaced(chat)
      return unless chat

      browser = @lock.synchronize do
        @revision += 1
        @browsers.delete(chat)
      end
      return unless browser

      close_later(browser.session)
      closed(chat)
    end

    # Closes a session now. True when it is closed or was already gone.
    def close(session_id)
      output = navigator(['--action', 'stop', '--managed', '--session-id', session_id.to_s], timeout: CLOSE_TIMEOUT)
      result_of(output)&.dig('success') == true
    end

    # A close that fails is left to Selenium (its slot is still counted).
    def close_quietly(session_id)
      close(session_id)
    rescue StandardError
      false
    end

    def close_later(session_id)
      @queue << session_id
      start_worker
    end

    # Closes the browsers left unused for IDLE_LIMIT seconds (not one an
    # action is using).
    def reap(now: clock)
      idle = @lock.synchronize do
        @last_reap = now
        chats = @browsers.select do |chat, browser|
          now - browser.used_at >= IDLE_LIMIT && !@op_locks[chat]&.locked?
        end.keys
        @revision += 1 unless chats.empty?
        chats.to_h { |chat| [chat, @browsers.delete(chat).session] }
      end
      idle.each do |chat, session_id|
        closed(chat)
        close_quietly(session_id)
      end
    end

    def start_worker
      @lock.synchronize do
        next if @worker&.alive?

        @worker = Thread.new { work }
        @worker.report_on_exception = false
      end
    end

    def work
      loop do
        session_id = begin
          @queue.pop(timeout: TICK)
        rescue StandardError
          nil
        end
        close_quietly(session_id) if session_id
        reap if clock - @last_reap >= TICK
      end
    end

    # Reads Selenium's report (outside the lock) and yields it with the
    # number of slots under the lock, to decide. When a slot may have been
    # given up while the report was read, the report may miss a session
    # that did not close: it is read again. :unavailable when Selenium
    # cannot be asked; :full when the slots keep changing.
    def admit
      OBSERVE_TRIES.times do
        revision = @lock.synchronize { @revision }
        observed = observe
        return :unavailable unless observed

        @lock.synchronize do
          return yield(observed, observed[:max]) if @revision == revision
        end
      end
      :full
    end

    # What Selenium reports: { sessions: [ids], max: n }, or nil when it
    # cannot be asked or reports no slots.
    def observe
      result = result_of(navigator(['--action', 'status'], timeout: STATUS_TIMEOUT))
      return nil unless result && result['success'] == true && result['max_sessions'].to_i.positive?

      { sessions: Array(result['sessions']), max: result['max_sessions'].to_i }
    rescue StandardError
      nil
    end

    def result_of(output)
      json = output.to_s[/\{.+\}/m]
      json && JSON.parse(json)
    rescue JSON::ParserError
      nil
    end

    # The slots in use: the chats' browsers, the starts and the jobs, and
    # every session Selenium reports that is not a chat's browser or a
    # job's named session.
    def taken(observed)
      known = @browsers.values.map(&:session) + @job_sessions.to_a
      @browsers.size + @starting.size + @jobs + (observed[:sessions] - known).size
    end

    def snapshot
      @lock.synchronize do
        { browsers: @browsers.transform_values(&:session), starting: @starting.keys,
          jobs: @jobs, job_sessions: @job_sessions.to_a }
      end
    end

    # For tests.
    def reset!
      @lock.synchronize do
        @browsers.clear
        @starting.clear
        @jobs = 0
        @job_sessions.clear
        @revision = 0
        @instances = 0
        @op_locks.clear
        @runner = nil
      end
      @queue.clear
    end
  end
end

# A chat the user replaced gives its browser up.
Monadic::Workspace::Chats.on_change do |event, session|
  if event == :replaced
    MonadicSharedTools::BrowserOwner.chat_replaced(session[Monadic::Workspace::Chats::SESSION_KEY] ||
                                                   session[Monadic::Workspace::Chats::SESSION_KEY.to_s])
  end
end

# What the user held of a chat's browser goes with the browser.
MonadicSharedTools::BrowserOwner.on_closed { |chat| MonadicSharedTools::BrowserOperator.forget(chat) }
