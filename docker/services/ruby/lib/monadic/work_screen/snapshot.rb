# frozen_string_literal: true

require 'async'
require 'base64'
require_relative 'cdp'
require_relative 'browser_binding'
require_relative 'viewport'
require_relative '../workbench/image_check'
require_relative '../work_screen'

module Monadic
  module WorkScreen
    # One picture of what a chat's browser shows now, for a look: a CDP
    # connection of its own (not the work screen's stream, whose screencast
    # it does not touch) attaches to the window the tools act on, takes the
    # viewport as a PNG no larger than the limits, and closes. It runs in a
    # reactor of its own in the calling thread (a reply's), and checks the
    # binding before it attaches, once attached, and once taken.
    module Snapshot
      MAX_SIDE = 2048
      MAX_PIXELS = 4_194_304
      MAX_BASE64 = Monadic::Workbench::ImageCheck::MAX_BASE64
      # Pictures being taken at once.
      SLOTS = 2
      # Seconds kept for detaching and closing, and a command's limit.
      CLEANUP = 3
      COMMAND_LIMIT = 5

      class Failed < StandardError
        attr_reader :reason

        def initialize(reason, message)
          @reason = reason
          super(message)
        end
      end

      @running = 0
      @lock = Mutex.new

      module_function

      # { png:, crop: { x, y, width, height, sent_width, sent_height },
      #   url:, title: } of binding's window, taken before deadline
      # (monotonic seconds). connector: (url, connect_limit, close_by) → a
      # Cdp that closes, however it ends, by close_by.
      # Raises Failed (busy, capture_timeout, too_large, selection_changed,
      # browser_unavailable).
      def take(binding, deadline:,
               connector: ->(url, limit, close_by) { Cdp.open(url, connect_limit: limit, close_by: close_by) })
        taken = false
        Thread.handle_interrupt(Object => :never) do
          taken = enter
          raise Failed.new('busy', 'the browser is being captured by too many replies now') unless taken

          Thread.handle_interrupt(Object => :immediate) { Sync { capture(binding, deadline, connector) } }
        ensure
          leave if taken
        end
      end

      def running
        @lock.synchronize { @running }
      end

      def enter
        @lock.synchronize do
          next false if @running >= SLOTS

          @running += 1
          true
        end
      end

      def leave
        @lock.synchronize { @running -= 1 }
      end

      def clock
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      # Seconds a step may take: what is left before deadline, less the
      # time kept for cleaning up, at most limit. Refused when none is left.
      def step_limit(deadline, limit)
        left = deadline - CLEANUP - clock
        raise Failed.new('capture_timeout', 'the browser could not be captured in time') unless left.positive?

        [left, limit].min
      end

      def capture(binding, deadline, connector)
        cdp = nil
        target = nil
        holds!(binding)
        cdp = connect(connector, binding, deadline)
        target = command(cdp, deadline, 'Target.attachToTarget', { targetId: binding.window, flatten: true })['sessionId']
        raise Failed.new('browser_unavailable', 'the browser window could not be reached') unless target.is_a?(String)

        holds!(binding)
        info = command(cdp, deadline, 'Target.getTargetInfo', { targetId: binding.window })['targetInfo'] || {}
        view = Viewport.read(command(cdp, deadline, 'Page.getLayoutMetrics', {}, target))
        raise Failed.new('browser_unavailable', 'the browser did not say what it shows') unless view

        scale = Viewport.scale(view, max_width: MAX_SIDE, max_height: MAX_SIDE, max_pixels: MAX_PIXELS)
        raise Failed.new('too_large', 'the browser window is too large to capture') if scale < 0.05

        shot = command(cdp, deadline, 'Page.captureScreenshot',
                       { format: 'png', captureBeyondViewport: false,
                         clip: { x: view[:x], y: view[:y], width: view[:width], height: view[:height], scale: scale } },
                       target)
        png, width, height = checked_png(shot['data'])
        holds!(binding)
        { png: png, url: info['url'].to_s, title: info['title'].to_s,
          crop: { 'x' => view[:x], 'y' => view[:y], 'width' => view[:width], 'height' => view[:height],
                  'sent_width' => width, 'sent_height' => height } }
      ensure
        cleanup(cdp, target, deadline)
      end

      # Raises Failed when binding no longer holds now.
      def holds!(binding)
        broken = binding.broken
        return unless broken

        raise Failed.new('selection_changed', "the browser is not the one selected now (#{broken})")
      end

      # A CDP connection to binding's browser, within what is left.
      def connect(connector, binding, deadline)
        connector.call(WorkScreen.cdp_url(binding.session), step_limit(deadline, Cdp::CONNECT_LIMIT), deadline)
      rescue Cdp::Timeout
        raise Failed.new('capture_timeout', 'the browser could not be reached in time')
      rescue Cdp::Error
        raise Failed.new('browser_unavailable', 'the browser could not be reached')
      end

      def command(cdp, deadline, method, params, session_id = nil)
        cdp.command(method, params, session_id: session_id, timeout: step_limit(deadline, COMMAND_LIMIT))
      rescue Cdp::Timeout
        raise Failed.new('capture_timeout', "#{method} took too long")
      rescue Cdp::Error
        raise Failed.new('browser_unavailable', "#{method} failed")
      end

      # The PNG the browser gave, checked: base64 of at most MAX_BASE64, a
      # PNG no larger than the limits. [bytes, width, height].
      def checked_png(data)
        raise Failed.new('browser_unavailable', 'the browser gave no picture') unless data.is_a?(String) && !data.empty?
        raise Failed.new('too_large', 'the picture of the browser is too large to send') if data.bytesize > MAX_BASE64

        bytes = Base64.strict_decode64(data)
        info = begin
          Monadic::Workbench::ImageCheck.check!(bytes)
        rescue Monadic::Workbench::ImageCheck::Refused => e
          raise Failed.new('too_large', 'the picture of the browser is larger than asked for') if e.message == 'image too large'

          raise
        end
        raise Failed.new('browser_unavailable', 'the browser gave no PNG') unless info[:content_type] == 'image/png'

        width = info[:width]
        height = info[:height]
        if width > MAX_SIDE || height > MAX_SIDE || width * height > MAX_PIXELS
          raise Failed.new('too_large', 'the picture of the browser is larger than asked for')
        end

        [bytes, width, height]
      rescue ArgumentError, Monadic::Workbench::ImageCheck::Refused
        raise Failed.new('browser_unavailable', 'the browser gave a picture that could not be read')
      end

      # Detaches this connection's own attachment and closes the
      # connection, within what is left before deadline: with no time left
      # the attachment is left to the closing connection, and the
      # connection is closed at once (Cdp#close with no time).
      def cleanup(cdp, target, deadline)
        return unless cdp

        begin
          left = [deadline - clock, CLEANUP].min
          cdp.command('Target.detachFromTarget', { sessionId: target }, timeout: left / 2) if target && left.positive?
        rescue Cdp::Error
          nil
        ensure
          cdp.close(limit: [deadline - clock, CLEANUP].min)
        end
      end
    end
  end
end
