# frozen_string_literal: true

require 'rack/session/abstract/id'

module Rack
  module Session
    # Unlimited in-memory session store without size restrictions
    # Unlike Rack::Session::Pool, this store doesn't drop sessions due to size
    class UnlimitedPool < Abstract::PersistedSecure
      attr_reader :mutex, :pool

      DEFAULT_OPTIONS = Abstract::ID::DEFAULT_OPTIONS.merge(
        drop: false  # Never drop sessions
      ).freeze

      def initialize(app, options = {})
        super
        @mutex = Mutex.new
        @pool = Hash.new { |h, k| h[k] = {} }
      end

      def find_session(req, sid)
        @mutex.synchronize do
          unless sid && (session = @pool[sid])
            sid = generate_sid
            @pool[sid] = {}
          end
          [sid, @pool[sid]]
        end
      end

      def write_session(req, sid, session, options)
        @mutex.synchronize do
          @pool[sid] = session
          sid
        end
      end

      def delete_session(req, sid, options)
        @mutex.synchronize do
          @pool.delete(sid)
          generate_sid unless options[:drop]
        end
      end

      private

      def generate_sid
        loop do
          sid = super
          break sid unless @pool.key?(sid)
        end
      end
    end

    # In-memory session store with caps to avoid unbounded growth
    # Maintains LRU eviction and guards against oversized session payloads
    class CappedPool < Abstract::PersistedSecure
      attr_reader :mutex, :pool

      DEFAULT_OPTIONS = Abstract::ID::DEFAULT_OPTIONS.merge(
        drop: false,
        max_sessions: 100,
        max_session_bytes: 16 * 1024 * 1024 # 16MB per session payload
      ).freeze

      def initialize(app, options = {})
        super
        @mutex = Mutex.new
        @pool = Hash.new { |h, k| h[k] = {} }
        @order = []
      end

      def find_session(req, sid)
        @mutex.synchronize do
          unless sid && (session = @pool[sid])
            sid = generate_sid
            @pool[sid] = {}
          end
          touch(sid)
          [sid, @pool[sid]]
        end
      end

      def write_session(req, sid, session, options)
        @mutex.synchronize do
          @pool[sid] = session
          touch(sid)
          enforce_limits(sid)
          sid
        end
      end

      def delete_session(req, sid, options)
        @mutex.synchronize do
          @pool.delete(sid)
          @order.delete(sid)
          generate_sid unless options[:drop]
        end
      end

      private

      def generate_sid
        loop do
          sid = super
          break sid unless @pool.key?(sid)
        end
      end

      def touch(sid)
        @order.delete(sid)
        @order << sid
      end

      def enforce_limits(sid)
        max_sessions = @default_options[:max_sessions]
        if max_sessions && max_sessions > 0
          while @order.length > max_sessions
            evicted = @order.shift
            @pool.delete(evicted)
            warn "[Session] Evicted session #{evicted} to maintain max_sessions=#{max_sessions}"
          end
        end

        max_session_bytes = @default_options[:max_session_bytes]
        return unless max_session_bytes && max_session_bytes > 0

        begin
          size = Marshal.dump(@pool[sid]).bytesize
          if size > max_session_bytes
            warn "[Session] Session #{sid} exceeded #{max_session_bytes} bytes (#{size}), clearing payload"
            @pool[sid] = {}
          end
        rescue StandardError
          # If serialization fails, skip size enforcement
        end
      end
    end
  end
end
