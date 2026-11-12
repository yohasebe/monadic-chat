# frozen_string_literal: true

require_relative 'shown'
require_relative '../workspace/folders'

module Monadic
  module Workbench
    # What a reply made in its chat's folder (a run folder of
    # Workbench::ChatOutput, a file of Workbench::Put), for its message: one
    # path per thing made, kept in memory while the reply runs, given to
    # its message once (seal) and dropped when the reply ends without one
    # (close). Deleting the message moves what it made to the chat's trash
    # (Workbench::TurnTrash); nothing else in the shared folder is touched.
    module Made
      LIMIT = 100
      # Replies ended, oldest first: a late add for one of them is dropped.
      CLOSED_LIMIT = 1000

      @open = {}
      @closed = {}
      @lock = Mutex.new

      module_function

      # Records that the reply request_id made path (relative to the shared
      # folder), while the reply runs.
      def add(request_id, path)
        return unless request_id && Shown.path?(path)

        @lock.synchronize do
          next if @closed.key?(request_id) || !Shown.running?(request_id)

          list = (@open[request_id] ||= [])
          list << path if list.size < LIMIT && !list.include?(path)
        end
        nil
      end

      # The reply's paths, once: its message takes them. Later adds for it
      # are dropped.
      def seal(request_id)
        @lock.synchronize do
          next [] if @closed.key?(request_id)

          @closed[request_id] = true
          @closed.shift while @closed.size > CLOSED_LIMIT
          @open.delete(request_id) || []
        end
      end

      # The reply ended (with or without a message): nothing is kept.
      def close(request_id)
        seal(request_id)
        nil
      end

      # Paths as a message keeps them (from a reply, or from history or an
      # imported file): relative paths of the chat folders only, at most
      # LIMIT; nil when none is left. A path names what was made; it gives
      # no right to read it, and the trash moves only what is inside the
      # chat's own folder.
      def clean(paths)
        return nil unless paths.is_a?(Array)

        prefix = "#{Monadic::Workspace::Folders::ROOT_DIRNAME}/"
        kept = paths.first(LIMIT).select { |path| Shown.path?(path) && path.start_with?(prefix) }.uniq
        kept.empty? ? nil : kept
      end

      # For tests.
      def reset!
        @lock.synchronize do
          @open.clear
          @closed.clear
        end
      end
    end
  end
end
