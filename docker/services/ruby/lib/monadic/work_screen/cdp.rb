# frozen_string_literal: true

require 'json'
require 'async'
require 'async/queue'
require 'async/semaphore'
require 'async/http/endpoint'
require 'async/websocket/client'

module Monadic
  module WorkScreen
    # A Chrome DevTools Protocol connection to one browser session, through
    # Selenium Grid's se/cdp endpoint. Runs inside the server's reactor.
    #
    # One reader task hands each reply to the command waiting for its id.
    # A screencast frame is acknowledged by the reader as it arrives and only
    # the newest is kept (latest_frame); next_event returns :frame when one
    # is there. Other events are queued; a reader that falls EVENT_LIMIT
    # events behind ends the connection rather than drop one. Connecting,
    # each command (sent and answered) and closing have time limits; a
    # connection that ends for any reason is released once.
    class Cdp
      class Error < StandardError; end
      # A connection or a command that did not answer in its time.
      class Timeout < Error; end

      EVENT_LIMIT = 16
      # A message larger than this ends the connection.
      MESSAGE_LIMIT = 8 * 1024 * 1024
      CONNECT_LIMIT = 10
      SEND_LIMIT = 2
      CLOSE_LIMIT = 2
      # Seconds a close may take once the socket is closed (abort_transport).
      ABORT_LIMIT = 0.1
      FRAME = 'Page.screencastFrame'

      # connect_limit: seconds the connection may take to open. close_by:
      # the monotonic time by which the connection, however it ends, is
      # closed (nil: CLOSE_LIMIT from when it ends).
      def self.open(url, connect_limit: CONNECT_LIMIT, close_by: nil)
        cdp = new(close_by: close_by)
        cdp.connect(url, limit: connect_limit)
        cdp
      end

      def initialize(close_by: nil)
        @close_by = close_by
        @next_id = 0
        @waiting = {}
        @events = Async::Queue.new
        @frame = nil
        @closed = false
        @sending = Async::Semaphore.new(1)
      end

      def connect(url, limit: CONNECT_LIMIT)
        Async::Task.current.with_timeout(limit) do
          @connection = Async::WebSocket::Client.connect(Async::HTTP::Endpoint.parse(url))
        end
        @reader = Async { read_all }
      rescue Async::TimeoutError
        close
        raise Timeout, 'connect timed out'
      rescue StandardError => e
        close
        raise Error, "connect failed (#{e.class})"
      end

      # The result of method, or raises Error (a CDP error, a timeout, a
      # closed connection).
      def command(method, params = {}, session_id: nil, timeout: 10)
        raise Error, 'closed' if @closed

        id = (@next_id += 1)
        reply = Async::Queue.new
        @waiting[id] = reply
        answer = Async::Task.current.with_timeout(timeout) do
          deliver(id, method, params, session_id)
          reply.dequeue
        end
        raise Error, 'closed' if answer.nil?
        raise Error, answer['error']['message'].to_s if answer['error']

        answer['result'] || {}
      rescue Async::TimeoutError
        raise Timeout, "#{method} timed out"
      ensure
        @waiting.delete(id) if id
      end

      # Sends method without waiting for its reply.
      def notify(method, params = {}, session_id: nil)
        return if @closed

        Async::Task.current.with_timeout(SEND_LIMIT) { deliver(@next_id += 1, method, params, session_id) }
      rescue Async::TimeoutError, Error
        nil
      end

      # :frame when a screencast frame is waiting (latest_frame), an event,
      # or nil when none came within timeout or the connection closed.
      def next_event(timeout)
        return nil if @closed && @events.empty?

        Async::Task.current.with_timeout(timeout) { @events.dequeue }
      rescue Async::TimeoutError
        nil
      end

      # The newest screencast frame ({session:, data:}), taken, or nil.
      def latest_frame
        frame = @frame
        @frame = nil
        frame
      end

      def closed?
        @closed
      end

      # limit: seconds the close may take; past them (or with none) the
      # transport is closed without the closing handshake.
      def close(limit: nil)
        release(limit)
      end

      private

      # Writes one message; a write cut off half way leaves the connection
      # unusable, so it is released.
      def deliver(id, method, params, session_id)
        message = { id: id, method: method, params: params }
        message[:sessionId] = session_id if session_id
        written = false
        @sending.acquire do
          @connection.write(Protocol::WebSocket::TextMessage.generate(message))
          @connection.flush
          written = true
        end
      rescue Async::TimeoutError
        raise
      rescue StandardError => e
        raise Error, "send failed (#{e.class})"
      ensure
        release unless written
      end

      def read_all
        while (message = @connection.read)
          text = message.to_str
          break if text.bytesize > MESSAGE_LIMIT

          data = JSON.parse(text)
          next unless data.is_a?(Hash)

          if data['id']
            @waiting[data['id']]&.enqueue(data)
          elsif data['method'] == FRAME
            take_frame(data)
          elsif data['method']
            break if @events.size >= EVENT_LIMIT

            @events.enqueue(data)
          end
        end
      rescue StandardError
        nil
      ensure
        release
      end

      # Acknowledged at once, so the browser sends the next; the newest is kept.
      def take_frame(data)
        params = data['params'] || {}
        notify('Page.screencastFrameAck', { sessionId: params['sessionId'] }, session_id: data['sessionId'])
        fresh = @frame.nil?
        @frame = { session: data['sessionId'], data: params['data'] }
        @events.enqueue(:frame) if fresh
      end

      # Closes the transport and wakes every waiter, once, however the
      # connection ended.
      # limit: seconds the closing may take (nil: CLOSE_LIMIT); never past
      # close_by.
      def release(limit = nil)
        return if @closed

        @closed = true
        limit ||= CLOSE_LIMIT
        limit = [limit, @close_by - Process.clock_gettime(Process::CLOCK_MONOTONIC)].min if @close_by
        begin
          raise Async::TimeoutError unless limit.positive?

          Async::Task.current.with_timeout(limit) { @connection&.close }
        rescue StandardError
          abort_transport
        ensure
          @reader&.stop unless @reader.equal?(Async::Task.current)
          wake_all
        end
      end

      # Closes the connection's socket at once: no closing frame and no
      # flush of what is still to be written (either may be what does not
      # finish). Client.connect gives the connection inside a decorator that
      # also owns its HTTP client; the connection's framer holds the stream
      # (the one value read from a gem's insides: Framer has no reader for
      # it), whose io is the socket. Once the socket is closed, nothing is
      # waited on to be sent; what the decorator's close still does (the
      # connection, then its client) is given ABORT_LIMIT at most.
      def abort_transport
        return unless @connection

        raw = @connection.respond_to?(:__getobj__) ? @connection.__getobj__ : @connection
        framer = raw.respond_to?(:framer) ? raw.framer : nil
        stream = framer&.instance_variable_get(:@stream)
        socket = stream.respond_to?(:io) ? stream.io : nil
        socket&.close
        Async::Task.current.with_timeout(ABORT_LIMIT) { @connection.close } if socket
      rescue StandardError
        nil
      end


      # Nothing waits for a reply or an event that will not come.
      def wake_all
        @waiting.each_value { |queue| queue.enqueue(nil) }
        @events.enqueue(nil)
      end
    end
  end
end
