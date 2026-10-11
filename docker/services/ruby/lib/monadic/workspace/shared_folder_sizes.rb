# frozen_string_literal: true

require 'time'

module Monadic
  module Workspace
    module SharedFolder
      # The sizes of folders in the shared folder, counted in the background
      # so that listing a folder never waits on a large tree. One worker
      # counts the folders asked for, one after another, within one budget of
      # entries and time for the whole run (not one per folder). A count cut
      # short says so: its bytes are what was counted, not the total.
      #
      # Bytes are the files' logical sizes. Links and other special entries
      # are counted as entries but neither followed nor sized. Every folder
      # is checked to be reached from the shared folder with no link before
      # it is read, so one replaced by a link while waiting is not followed.
      class Sizes
        MAX_ENTRIES = 300_000
        MAX_SECONDS = 20
        FRESH_FOR = 300 # seconds a count is reused before it is redone
        MAX_KNOWN = 5_000

        def self.default
          @default ||= new
        end

        def initialize(root_proc: -> { SharedFolder.data_root }, max_entries: MAX_ENTRIES, max_seconds: MAX_SECONDS,
                       clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
          @root_proc = root_proc
          @max_entries = max_entries
          @max_seconds = max_seconds
          @clock = clock
          @mutex = Mutex.new
          @known = {}   # relative => { bytes:, files:, status:, at:, counted_at: }
          @queue = []
          @running = nil
          @worker = nil
        end

        # What is known of relative's size, or nil (then a count is asked
        # for). A count older than FRESH_FOR is returned and redone.
        def lookup(relative)
          @mutex.synchronize do
            known = @known[relative]
            enqueue(relative) if known.nil? || @clock.call - known[:counted_at] > FRESH_FOR
            known&.slice(:bytes, :files, :status, :at)
          end
        end

        # Counts what is queued now, in the calling thread (the worker's own
        # loop, and tests). One folder that cannot be counted does not stop
        # the others.
        def drain!
          budget = { entries: @max_entries, deadline: @clock.call + @max_seconds }
          loop do
            relative = @mutex.synchronize do
              item = @queue.shift
              if item
                @running = item
              elsif owner?
                # The worker gives up its place in the same step that finds
                # the queue empty, so a folder queued after that starts a new
                # one, whose state this one no longer touches.
                @running = nil
                @worker = nil
              end
              item
            end
            break unless relative

            result = begin
              count(relative, budget)
            rescue StandardError
              { bytes: 0, files: 0, status: 'failed' }
            end
            store(relative, result)
          end
        ensure
          @mutex.synchronize do
            if owner?
              @running = nil
              @worker = nil
            end
          end
        end

        private

        # Whether the calling thread counts for this object: its worker, or a
        # caller draining it directly while it has no worker (tests).
        def owner?
          @worker.nil? || Thread.current.equal?(@worker)
        end

        def enqueue(relative)
          return if @queue.include?(relative) || @running == relative

          @queue << relative
          return if @worker # it takes this one before it gives up its place

          @worker = Thread.new do
            Thread.current.report_on_exception = false
            drain!
          end
        end

        # A recount cut short by the budget does not replace a full count;
        # the full one stays (still old, so it is counted again later).
        def store(relative, result)
          @mutex.synchronize do
            previous = @known[relative]
            next if result[:status] == 'partial' && previous && previous[:status] == 'complete'

            @known.delete(@known.keys.first) while @known.size >= MAX_KNOWN && !@known.key?(relative)
            @known[relative] = result.merge(at: Time.now.utc.iso8601, counted_at: @clock.call)
          end
        end

        def count(relative, budget)
          root = @root_proc.call
          start = File.join(root, relative)
          File.lstat(start) # missing: vanished; not reachable: permission_denied (below)
          return { bytes: 0, files: 0, status: 'changed' } unless plain_folder?(start)

          bytes = 0
          files = 0
          status = 'complete'
          stack = [start]
          until stack.empty?
            if spent?(budget)
              status = 'partial'
              break
            end
            dir = stack.pop
            unless plain_folder?(dir)
              status = 'changed' # replaced while counting: not read
              next
            end
            begin
              Dir.each_child(dir) do |name|
                if spent?(budget)
                  status = 'partial'
                  break
                end
                budget[:entries] -= 1
                path = File.join(dir, name)
                begin
                  entry = File.lstat(path)
                rescue Errno::ENOENT
                  next # gone while counting
                end
                if entry.directory?
                  stack << path
                elsif entry.file?
                  bytes += entry.size
                  files += 1
                end
              end
            rescue Errno::EACCES, Errno::EPERM
              status = 'permission_denied'
            rescue Errno::ENOENT, Errno::ENOTDIR
              status = dir == start ? 'vanished' : 'changed'
            end
          end
          { bytes: bytes, files: files, status: status }
        rescue Errno::ENOENT
          { bytes: 0, files: 0, status: 'vanished' }
        rescue Errno::EACCES, Errno::EPERM
          { bytes: 0, files: 0, status: 'permission_denied' }
        end

        # A folder reached from the shared folder with no link at any level
        # (the path it is reached by is the path it really has).
        def plain_folder?(path)
          File.lstat(path).directory? && File.realpath(path) == path
        rescue Errno::ENOENT, Errno::ENOTDIR
          false
        end

        def spent?(budget)
          budget[:entries] <= 0 || @clock.call > budget[:deadline]
        end
      end
    end
  end
end
