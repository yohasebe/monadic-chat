# frozen_string_literal: true

require 'pstore'
require 'fileutils'
require 'thread'
require 'rack/session/abstract/id'

module Monadic
  module Utils
    # Minimal session store that persists Rack sessions to a PStore-backed file.
    # Keeps behaviour close to Rack::Session::Pool while surviving process restarts.
    class FileSessionStore < Rack::Session::Abstract::ID
      DEFAULTS = {
        file: File.expand_path('tmp/sessions.pstore', Dir.pwd),
        expire_after: 60 * 60 * 24 * 7 # one week
      }.freeze

      def initialize(app, options = {})
        opts = DEFAULTS.merge(options)
        @file_path = opts.delete(:file)
        @expire_after = opts[:expire_after]
        @mutex = Mutex.new

        FileUtils.mkdir_p(File.dirname(@file_path))
        @store = PStore.new(@file_path, true)
        @store.ultra_safe = true
        @store.transaction { @store[:sessions] ||= {} }

        super(app, opts)
      end

      def find_session(_env, sid)
        @mutex.synchronize do
          sessions = read_sessions
          sid &&= sid.to_s
          data = nil

          if sid && sessions.key?(sid)
            record = sessions[sid]
            if expired?(record)
              sessions.delete(sid)
            else
              data = deep_dup(record[:data])
            end
          end

          sid ||= generate_sid
          data ||= {}

          write_sessions(sessions)
          [sid, data]
        end
      end

      def write_session(_env, sid, session_data, _options)
        return false unless sid

        @mutex.synchronize do
          sessions = read_sessions
          sessions[sid.to_s] = { data: deep_dup(session_data), updated_at: current_timestamp }
          prune_expired!(sessions)
          write_sessions(sessions)
        end

        sid
      end

      def delete_session(_env, sid, _options)
        return generate_sid unless sid

        @mutex.synchronize do
          sessions = read_sessions
          sessions.delete(sid.to_s)
          write_sessions(sessions)
        end

        generate_sid
      end

      private

      def read_sessions
        @store.transaction(true) { deep_dup(@store[:sessions] || {}) }
      end

      def write_sessions(sessions)
        @store.transaction { @store[:sessions] = sessions }
      end

      def prune_expired!(sessions)
        return unless @expire_after && @expire_after.positive?

        cutoff = current_timestamp - @expire_after
        sessions.delete_if { |_, record| record[:updated_at].to_i < cutoff }
      end

      def expired?(record)
        return false unless @expire_after && @expire_after.positive?

        record[:updated_at].to_i < (current_timestamp - @expire_after)
      end

      def current_timestamp
        Time.now.to_i
      end

      def deep_dup(obj)
        Marshal.load(Marshal.dump(obj))
      rescue TypeError
        obj
      end
    end
  end
end
