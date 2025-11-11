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
  end
end
