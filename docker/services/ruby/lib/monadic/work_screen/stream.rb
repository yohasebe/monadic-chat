# frozen_string_literal: true

require 'json'
require 'async'
require 'async/queue'
require_relative 'tokens'
require_relative 'cdp'
require_relative 'browser_binding'
require_relative 'viewport'
require_relative '../shared_tools/browser_owner'
require_relative '../workspace/chats'

module Monadic
  module WorkScreen
    # One work screen socket: the page of a tab watches its chat's browser.
    #
    # The page first shows its pass (Tokens); nothing is sent before that.
    # A tab has one work screen socket at a time: a newer one closes the
    # older. On subscribe the stream is bound to the tab's live connection,
    # the chat it is in then, the chat's epoch, the browser instance the
    # page selected (a subscribe names it; another browser of the chat is
    # not shown in its place) and the window the tools act on, and is checked against them again every
    # CHECK seconds and before each frame. When only the window changed, the
    # same browser is shown again on its new window (or waited for while the
    # window is not known); any other change ends the stream, with the
    # reason. A new subscribe binds afresh.
    #
    # Frames: the page gets at most one frame it has not drawn
    # (frame-consumed), no more than one per INTERVAL, always the newest.
    # What is sent to the page is written by a task of its own, so a page
    # that does not read cannot hold up the checks; a write that does not
    # finish within WRITE_LIMIT, or too many waiting, closes the socket. A
    # frame or a live state still waiting is dropped once its stream has
    # stopped or its binding no longer holds.
    class Stream
      AUTH_LIMIT = 5
      INTERVAL = 0.125
      CHECK = 0.5
      CONSUME_LIMIT = 15
      WRITE_LIMIT = 10
      OUTBOX_LIMIT = 8
      # Seconds a stopped stream gets to close its CDP connection.
      STOP_LIMIT = 5
      INBOUND_LIMIT = 1024
      # Base64 characters of one frame.
      FRAME_LIMIT = 2_000_000
      MAX_WIDTH = 1280
      MAX_HEIGHT = 900

      Binding = BrowserBinding

      @viewers = {}
      @viewers_lock = Mutex.new

      # The tab's work screen socket is now stream; the one before it is
      # closed.
      def self.claim(tab, stream)
        previous = @viewers_lock.synchronize do
          old = @viewers[tab]
          @viewers[tab] = stream
          old
        end
        previous&.close unless previous.equal?(stream)
      end

      def self.leave(tab, stream)
        @viewers_lock.synchronize { @viewers.delete(tab) if @viewers[tab].equal?(stream) }
      end

      # For tests.
      def self.reset!
        @viewers_lock.synchronize { @viewers.clear }
      end

      def initialize(socket, connector: ->(url) { Cdp.open(url) }, cdp_url: WorkScreen.method(:cdp_url))
        @socket = socket
        @connector = connector
        @cdp_url = cdp_url
        @stream = 0
        @frame = 0
        @task = nil
        @current = nil
        @outstanding = nil
        @outbox = Async::Queue.new
        @broken = false
      end

      def run
        @writer = Async { write_all }
        @grant = authenticate
        return unless @grant

        self.class.claim(@grant.tab, self)
        while (message = read_message)
          case message['type']
          when 'subscribe' then start_stream(message['browser'])
          when 'unsubscribe' then stop_stream(notify: 'idle')
          when 'frame-consumed' then consumed(message)
          else break # a second auth
          end
        end
      ensure
        stop_stream
        self.class.leave(@grant.tab, self) if @grant
        @writer&.stop
      end

      # Ends this socket (a newer one took the tab, or the page does not read).
      def close
        @broken = true
        @socket.close
      end

      private

      def authenticate
        message = Async::Task.current.with_timeout(AUTH_LIMIT) { read_message }
        message && message['type'] == 'auth' ? Tokens.redeem(message['token']) : nil
      rescue Async::TimeoutError
        nil
      end

      # The next message the page sent, or nil when the socket closed or the
      # page sent something that is not one of its messages.
      def read_message
        text = @socket.read
        return nil if text.nil? || text.bytesize > INBOUND_LIMIT

        message = JSON.parse(text)
        return nil unless message.is_a?(Hash) && valid?(message)

        message
      rescue JSON::ParserError
        nil
      end

      FIELDS = {
        'auth' => %w[token],
        'subscribe' => %w[browser],
        'unsubscribe' => [],
        'frame-consumed' => %w[stream n]
      }.freeze

      # Only the page's messages, each with exactly its own fields.
      def valid?(message)
        fields = FIELDS[message['type']]
        return false unless fields && message.keys.sort == (['type'] + fields).sort

        case message['type']
        when 'auth' then message['token'].is_a?(String)
        when 'subscribe' then message['browser'].is_a?(Integer) && message['browser'].between?(1, 2**31)
        when 'frame-consumed'
          message.values_at('stream', 'n').all? { |v| v.is_a?(Integer) && v.between?(0, 2**31) }
        else true
        end
      end

      def consumed(message)
        return unless @outstanding && message['stream'] == @stream && message['n'] == @outstanding

        @outstanding = nil
      end

      # instance: the browser the page selected.
      def start_stream(instance)
        stop_stream
        unless WorkScreen.available?
          send_state('ended', reason: 'unavailable')
          return
        end
        binding = bind
        return send_state('waiting', reason: 'no_browser') unless binding
        # The chat's browser is another one now: the one selected closed.
        return send_state('ended', reason: 'browser_closed', browser: instance) unless binding.instance == instance

        @task = Async { watch(binding) }
      end

      # Stops the stream and waits (STOP_LIMIT at most) until its CDP
      # connection is closed, so the next one does not overlap it.
      def stop_stream(notify: nil)
        task = @task
        @task = nil
        @outstanding = nil
        if task
          task.stop
          begin
            Async::Task.current.with_timeout(STOP_LIMIT) { task.wait }
          rescue StandardError
            nil
          end
        end
        send_state(notify) if notify
      end

      # The chat's browser as the tab's live connection sees it now, or nil.
      # Its window may not be known yet.
      def bind
        return nil unless WebSocketHelper.live_generation(@grant.tab) == @grant.generation

        session = WebSocketHelper.live_session(@grant.tab)
        chat = session && session[Monadic::Workspace::Chats::SESSION_KEY]
        view = chat && MonadicSharedTools::BrowserOwner.view(chat)
        return nil unless view

        Binding.new(@grant.tab, @grant.generation, chat, view.epoch, view.instance, view.session, view.window)
      end

      # Why binding no longer holds (:connection, :chat, :replaced,
      # :browser_closed, or :window when only the window changed), or nil.
      def check(binding, view = MonadicSharedTools::BrowserOwner.view(binding.chat))
        binding.broken(view)
      end

      # Shows the browser while the binding holds. When only the window
      # changed, the same browser is shown on its new window.
      def watch(binding)
        loop do
          reason = binding.window ? stream_once(binding) : await_window(binding)
          if reason == :window
            view = MonadicSharedTools::BrowserOwner.view(binding.chat)
            reason = check(binding, view)
            if reason == :window
              binding = binding.dup
              binding.window = view.window
              next
            end
          end

          send_state('ended', reason: reason.to_s, binding: binding)
          # The browser may have closed without a close here (Selenium was
          # restarted): the chat stops holding it once Selenium says so.
          MonadicSharedTools::BrowserOwner.confirm_gone_later(binding.chat, binding.session) if reason == :browser_gone
          break
        end
      end

      # The browser is the chat's, but the window its tools act on is not
      # known: nothing is shown until it is.
      def await_window(binding)
        send_state('waiting', reason: 'no_window', binding: binding)
        loop do
          reason = check(binding)
          return reason if reason

          sleep CHECK
        end
      end

      def stream_once(binding)
        @stream += 1
        stream = @current = @stream
        @outstanding = nil
        cdp = @connector.call(@cdp_url.call(binding.session))
        target = cdp.command('Target.attachToTarget', { targetId: binding.window, flatten: true })['sessionId']
        reason = check(binding)
        return reason if reason

        send_state('live', binding: binding, stream: stream)
        latest = first_frame(cdp, target)
        cdp.command('Page.startScreencast',
                    { format: 'jpeg', quality: 60, maxWidth: MAX_WIDTH, maxHeight: MAX_HEIGHT },
                    session_id: target)
        frames(cdp, target, binding, stream, latest)
      rescue Cdp::Error
        check(binding) || :browser_gone
      ensure
        @current = nil if @current == stream
        # A stop arriving meanwhile waits until the connection is closed.
        Async::Task.current.defer_stop do
          if cdp
            cdp.notify('Page.stopScreencast', {}, session_id: target) if target
            cdp.close
          end
        end
      end

      def frames(cdp, target, binding, stream, latest)
        checked = sent = clock
        loop do
          event = cdp.next_event(INTERVAL)
          return :browser_gone if event.nil? && cdp.closed?

          if event == :frame
            frame = cdp.latest_frame
            latest = image(frame[:data]) || latest if frame && frame[:session] == target
          elsif event && gone?(event, target)
            return :browser_gone
          end

          now = clock
          if now - checked >= CHECK
            checked = now
            reason = check(binding)
            return reason if reason
          end
          return :slow if @outstanding && now - sent > CONSUME_LIMIT
          next unless latest && @outstanding.nil? && now - sent >= INTERVAL

          reason = check(binding)
          return reason if reason

          @frame += 1
          @outstanding = @frame
          sent = now
          write({ type: 'frame', browser: binding.instance, stream: stream, n: @frame, data: latest },
                stream: stream, binding: binding)
          latest = nil
        end
      end

      def image(data)
        data.is_a?(String) && data.bytesize <= FRAME_LIMIT ? data : nil
      end

      def gone?(event, target)
        case event['method']
        when 'Target.detachedFromTarget' then event.dig('params', 'sessionId') == target
        when 'Inspector.detached', 'Inspector.targetCrashed' then event['sessionId'] == target
        else false
        end
      end

      # A still of the page as it is, at the screencast's size: a page that
      # does not repaint sends no screencast frame.
      # No still when the viewport is not known: the screencast's frames
      # come instead.
      def first_frame(cdp, target)
        view = Viewport.read(cdp.command('Page.getLayoutMetrics', {}, session_id: target, timeout: 5))
        return nil unless view

        # No larger than the screencast's frames.
        scale = Viewport.scale(view, max_width: MAX_WIDTH, max_height: MAX_HEIGHT).clamp(0.1, 1.0)
        shot = cdp.command('Page.captureScreenshot',
                           { format: 'jpeg', quality: 60,
                             clip: { x: view[:x], y: view[:y], width: view[:width], height: view[:height], scale: scale } },
                           session_id: target, timeout: 5)
        image(shot['data'])
      rescue Cdp::Error
        nil
      end

      # stream: given for a live state, which is then sent only while that
      # stream holds (as a frame is).
      def send_state(state, reason: nil, binding: nil, stream: nil, browser: nil)
        message = { type: 'state', state: state }
        message[:reason] = reason if reason
        message[:browser] = binding ? binding.instance : browser if binding || browser
        message[:stream] = @stream if binding
        write(message, stream: stream, binding: stream && binding)
      end

      Outgoing = Struct.new(:text, :stream, :binding)

      # Queued for the writer; a page that has let OUTBOX_LIMIT pile up is
      # not reading, and its socket is closed.
      def write(message, stream: nil, binding: nil)
        return if @broken
        return close if @outbox.size >= OUTBOX_LIMIT

        @outbox.enqueue(Outgoing.new(JSON.generate(message), stream, binding))
      end

      def write_all
        while (outgoing = @outbox.dequeue)
          next unless current?(outgoing)

          Async::Task.current.with_timeout(WRITE_LIMIT) { @socket.write(outgoing.text) }
        end
      rescue StandardError
        close
      end

      # Whether what was queued may still be sent: a frame or live state
      # only while its stream runs and its binding holds.
      def current?(outgoing)
        return true unless outgoing.stream

        outgoing.stream == @current && check(outgoing.binding).nil?
      end

      def clock
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
