# frozen_string_literal: true

require 'rack/session/abstract/id'

module Rack
  module Session
    # In-memory session store that does not grow without bound (config.ru).
    # A session nobody has used over HTTP for a while is removed: one idle
    # longer than expire_after, and, when there are more than max_sessions,
    # the least recently used among those idle for at least MIN_IDLE. Its
    # content is never cleared while it is kept; a session over
    # max_session_bytes is only reported. Chats do not live here (each tab's
    # WebSocket connection and the tab's saved state keep its chat), so a
    # removed session loses no conversation.
    #
    # Sessions are kept under the session id's private id, as Rack's own
    # Pool keeps them: the id object differs on every request, and only an id
    # this store issued resumes a session.
    class CappedPool < Abstract::PersistedSecure
      attr_reader :mutex, :pool

      MIN_IDLE = 3600 # seconds; a session used within this is never evicted

      DEFAULT_OPTIONS = Abstract::ID::DEFAULT_OPTIONS.merge(
        drop: false,
        max_sessions: 100,
        max_session_bytes: 16 * 1024 * 1024 # 16MB per session payload
      ).freeze

      def initialize(app, options = {})
        super
        @mutex = Mutex.new
        @pool = {}
        @used = {} # private id => last use, oldest first
        @reported_size = {}
      end

      def generate_sid(*args, use_mutex: true)
        loop do
          sid = super(*args)
          taken = use_mutex ? @mutex.synchronize { @pool.key?(sid.private_id) } : @pool.key?(sid.private_id)
          break sid unless taken
        end
      end

      def find_session(req, sid)
        @mutex.synchronize do
          session = sid && @pool[sid.private_id]
          unless session
            sid = generate_sid(use_mutex: false)
            session = {}
            @pool[sid.private_id] = session
          end
          touch(sid.private_id)
          [sid, session]
        end
      end

      def write_session(req, sid, session, options)
        @mutex.synchronize do
          # A session removed meanwhile is not brought back.
          return false unless @pool.key?(sid.private_id)

          @pool[sid.private_id] = session
          touch(sid.private_id)
          enforce_limits(sid.private_id)
          sid
        end
      end

      def delete_session(req, sid, options)
        @mutex.synchronize do
          remove(sid.private_id)
          unless options[:drop]
            fresh = generate_sid(use_mutex: false)
            @pool[fresh.private_id] = {}
            touch(fresh.private_id)
            fresh
          end
        end
      end

      private

      def now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def touch(key)
        @used.delete(key)
        @used[key] = now
      end

      def remove(key)
        @pool.delete(key)
        @used.delete(key)
        @reported_size.delete(key)
      end

      def enforce_limits(current)
        t = now
        expire = @default_options[:expire_after]
        if expire && expire > 0
          @used.select { |key, at| key != current && t - at > expire }.each_key { |key| remove(key) }
        end

        max_sessions = @default_options[:max_sessions]
        if max_sessions && max_sessions > 0 && @used.length > max_sessions
          idle = @used.select { |key, at| key != current && t - at >= MIN_IDLE }.keys
          idle.first(@used.length - max_sessions).each do |key|
            remove(key)
            warn "[Session] Evicted an idle session to keep max_sessions=#{max_sessions}"
          end
        end

        report_size(current)
      end

      def report_size(key)
        max_bytes = @default_options[:max_session_bytes]
        return unless max_bytes && max_bytes > 0 && !@reported_size[key]

        size = Marshal.dump(@pool[key]).bytesize
        return unless size > max_bytes

        @reported_size[key] = true
        warn "[Session] A session holds #{size} bytes (over #{max_bytes}); it is kept as it is"
      rescue StandardError
        # A session holding objects Marshal cannot dump is not measured.
      end
    end
  end
end
