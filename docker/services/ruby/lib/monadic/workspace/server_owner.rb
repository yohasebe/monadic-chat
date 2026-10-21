# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'securerandom'
require 'socket'
require 'time'
require_relative '../utils/environment'

module Monadic
  module Workspace
    # Which server writes the records in the state folder. The server in the
    # container and the one run from the host (development) see the same
    # folder, and a file lock is not known to hold between them, so a server
    # takes this mark when it starts and keeps it until it stops; a second
    # server does not start.
    #
    # The mark is a numbered generation, server.owner/g<n>, each put in place
    # whole by renaming a folder written beforehand (a rename does not replace
    # a folder that has something in it, so only one server makes a given
    # number). The server of the highest number holds the folder. A new
    # generation is made only when the server of the highest one is known to
    # have stopped (no time limit makes a server count as gone), and a server
    # that finds a higher number than its own after making it gives way. No
    # mark is ever moved or removed by anyone but its own server, apart from
    # lower generations the holder clears; a stopping server only notes in
    # its own generation that it has stopped, so the numbers never start
    # again from 1.
    class ServerOwner
      DIR = 'server.owner'
      FILE = 'owner.json'
      STOPPED = 'stopped'
      GENERATION = /\Ag(\d{1,18})\z/
      MODES = %w[container host].freeze

      class Refused < StandardError; end

      @current = nil
      @current_mutex = Mutex.new

      class << self
        # The mark this process holds, once taken at start.
        def current
          @current_mutex.synchronize { @current }
        end

        # Takes the mark for this server, or raises Refused (the server must
        # then not start).
        def acquire!(**options)
          owner = new(**options)
          owner.acquire!
          @current_mutex.synchronize { @current = owner }
          at_exit { owner.release! if Process.pid == owner.pid }
          owner
        end

        # Runs a change to the state folder. For a server that took the mark
        # at start, the whole change runs while the mark is its own and the
        # server is not stopping, and stopping waits for it; Refused
        # otherwise. Where no mark was taken (a program or a test that does
        # not start a server) the block just runs.
        def writing(&block)
          owner = current
          owner ? owner.writing(&block) : yield
        end

        def reset!
          @current_mutex.synchronize { @current = nil }
        end

        # Stops the whole server, not only this worker: Falcon starts a
        # worker again when one fails, and a worker that is refused would be
        # started again and again. Only a Falcon parent is stopped.
        def stop_server!
          parent = Process.ppid
          Process.kill('TERM', parent) if falcon_process?(parent)
        rescue SystemCallError
          nil
        end

        def falcon_process?(pid)
          command = if File.readable?("/proc/#{pid}/cmdline")
                      File.read("/proc/#{pid}/cmdline").tr("\0", ' ')
                    else
                      IO.popen(['ps', '-o', 'command=', '-p', pid.to_s], err: File::NULL, &:read).to_s
                    end
          command.include?('falcon')
        rescue SystemCallError, IOError
          false
        end

        def pid_alive?(pid)
          Process.kill(0, pid)
          true
        rescue Errno::ESRCH
          false
        rescue Errno::EPERM
          true
        end

        # The start of this container: the boot of the machine it runs on and
        # the start time of its first process. nil where that cannot be read.
        def container_instance
          boot = File.read('/proc/sys/kernel/random/boot_id').strip
          start = File.read('/proc/1/stat').split(') ').last.to_s.split[19]
          value = "#{boot}:#{start}"
          INSTANCE.match?(value) ? value : nil
        rescue SystemCallError
          nil
        end

        # Whether the Ruby container runs: false only when docker answers
        # that it has stopped; true when it runs; nil when that cannot be
        # told (no docker, no answer, no such container, an error).
        def ruby_container_running?
          require_relative '../shell'
          out, _err, status = Monadic::Shell.capture(
            ['docker', 'inspect', '-f', '{{.State.Running}}', Monadic::Shell.resolve_container(:ruby)], timeout: 15
          )
          return nil unless status.success?

          { 'true' => true, 'false' => false }[out.strip]
        rescue SystemCallError, Monadic::Shell::TimedOut
          nil
        end
      end

      INSTANCE = /\A[0-9a-f-]{36}:\d+\z/
      OWNER_ID = /\A[0-9a-f]{16}\z/

      attr_reader :owner_id, :pid, :generation

      # mode: 'container' or 'host'. instance: what tells one start of the
      # container from the next (a restarted container keeps its host name
      # and counts its process ids from 1 again). container_running: whether
      # the Ruby container runs (true/false), or nil when that cannot be told.
      def initialize(state_path: Monadic::Utils::Environment.state_path,
                     mode: Monadic::Utils::Environment.in_container? ? 'container' : 'host',
                     host_id: Socket.gethostname, pid: Process.pid,
                     instance: mode == 'container' ? self.class.container_instance : nil,
                     pid_alive: ->(id) { self.class.pid_alive?(id) },
                     container_running: -> { self.class.ruby_container_running? })
        @state_path = state_path
        @mode = mode
        @host_id = host_id
        @pid = pid
        @instance = instance
        @pid_alive = pid_alive
        @container_running = container_running
        @owner_id = SecureRandom.hex(8)
        @dir = File.join(state_path, DIR)
        @generation = nil
        @gate = Mutex.new
        @idle = ConditionVariable.new
        @writers = 0
        @stopping = false
      end

      def acquire!
        FileUtils.mkdir_p(@dir, mode: 0o700)
        3.times do
          top = generations.max
          if top
            previous = read(top)
            raise Refused, refusal(previous) unless previous && gone?(top, previous)
          end

          target = (top || 0) + 1
          next unless place(target)

          if generations.max != target
            # Another server made a higher one meanwhile: it holds the folder.
            FileUtils.rm_rf(path_of(target))
            raise Refused, 'Another Monadic Chat server is starting with the same data. Try again.'
          end

          @generation = target
          clear_below(target)
          return self
        end
        raise Refused, 'Another Monadic Chat server is starting with the same data. Try again.'
      end

      def check_held!
        top = generations.max
        mine = top && top == @generation ? read(top) : nil
        return if mine && mine['owner_id'] == @owner_id && !File.exist?(File.join(path_of(top), STOPPED))

        raise Refused, 'This server no longer holds its data folder; another server has taken it. Restart Monadic Chat.'
      end

      def writing
        @gate.synchronize do
          raise Refused, 'This server is stopping; nothing more is written.' if @stopping

          @writers += 1
        end
        begin
          check_held!
          yield
        ensure
          @gate.synchronize do
            @writers -= 1
            @idle.broadcast if @writers.zero?
          end
        end
      end

      RELEASE_WAIT = 30 # seconds for changes under way to finish

      # Notes in this server's own generation that it has stopped, once no
      # change to the state folder is under way and none can start. When the
      # changes do not finish in time nothing is noted: the next server then
      # follows only when this process is known to be gone. The generation
      # stays, so the next number follows it.
      def release!(wait: RELEASE_WAIT)
        return unless @generation
        return unless drained?(wait)

        mine = read(@generation)
        return unless mine && mine['owner_id'] == @owner_id

        File.open(File.join(path_of(@generation), STOPPED), File::WRONLY | File::CREAT, 0o600) do |f|
          f.write(Time.now.utc.iso8601)
          f.flush
          f.fsync
        end
      rescue SystemCallError
        nil
      end

      private

      def drained?(wait)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + wait
        @gate.synchronize do
          @stopping = true
          until @writers.zero?
            left = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
            return false if left <= 0

            @idle.wait(@gate, left)
          end
        end
        true
      end

      def path_of(number)
        File.join(@dir, "g#{number}")
      end

      def generations
        Dir.children(@dir).filter_map { |name| name[GENERATION, 1]&.to_i }
      rescue Errno::ENOENT
        []
      end

      def record
        { 'owner_id' => @owner_id, 'mode' => @mode, 'host_id' => @host_id, 'pid' => @pid,
          'instance' => @instance, 'started_at' => Time.now.utc.iso8601 }
      end

      # Writes generation `number` under another name and renames it into
      # place. False when that number is already there.
      def place(number)
        draft = File.join(@dir, "draft-#{@owner_id}-#{SecureRandom.hex(4)}")
        Dir.mkdir(draft, 0o700)
        File.open(File.join(draft, FILE), File::WRONLY | File::CREAT | File::EXCL, 0o600) do |f|
          f.write(JSON.generate(record))
          f.flush
          f.fsync
        end
        File.rename(draft, path_of(number))
        true
      rescue Errno::ENOTEMPTY, Errno::EEXIST
        false
      ensure
        FileUtils.rm_rf(draft) if draft && File.exist?(draft)
      end

      # A generation's record, when it is whole and well formed; nil
      # otherwise (which is never taken as a stopped server).
      def read(number)
        data = JSON.parse(File.read(File.join(path_of(number), FILE)))
        well_formed?(data) ? data : nil
      rescue Errno::ENOENT, Errno::ENOTDIR, JSON::ParserError
        nil
      end

      def well_formed?(data)
        data.is_a?(Hash) &&
          data['owner_id'].is_a?(String) && OWNER_ID.match?(data['owner_id']) &&
          MODES.include?(data['mode']) &&
          data['host_id'].is_a?(String) && !data['host_id'].empty? &&
          data['pid'].is_a?(Integer) && data['pid'].positive? &&
          (data['instance'].nil? || (data['instance'].is_a?(String) && INSTANCE.match?(data['instance'])))
      end

      # Whether the server of a generation is known to have stopped.
      def gone?(number, previous)
        return true if File.exist?(File.join(path_of(number), STOPPED))

        case [previous['mode'], @mode]
        when %w[container container]
          # The container has a fixed name, so there is one at a time: a mark
          # from another one, or from an earlier start of this one, is from a
          # server that has stopped.
          previous['host_id'] != @host_id || other_start?(previous) || stopped?(previous)
        when %w[host host]
          previous['host_id'] == @host_id && stopped?(previous)
        when %w[container host]
          @container_running.call == false
        else
          # A server on the host cannot be seen from the container.
          false
        end
      end

      def other_start?(previous)
        !@instance.nil? && !previous['instance'].nil? && previous['instance'] != @instance
      end

      # The process is gone, or its id is now this process's.
      def stopped?(previous)
        previous['pid'] == @pid || !@pid_alive.call(previous['pid'])
      end

      # The generations below this server's are of servers that have
      # stopped; a server that still acts on one of them finds this higher
      # number and gives way.
      def clear_below(number)
        generations.each { |n| FileUtils.rm_rf(path_of(n)) if n < number }
      rescue SystemCallError
        nil
      end

      def refusal(previous)
        return 'The data folder is marked as in use, but the mark cannot be read.' unless previous

        if previous['mode'] == 'host' && @mode == 'container'
          'A Monadic Chat server run from the host (development) may still be using the data folder. ' \
            'Stop it and start again. If it has stopped, remove the folder "server.owner" in ~/monadic/state.'
        elsif previous['mode'] == 'container' && @mode == 'host'
          'The Monadic Chat server in the container may still be using the data folder (Docker did not say it has ' \
            'stopped). Stop the container and start again.'
        else
          'Another Monadic Chat server is using the data folder. Stop it and start again.'
        end
      end
    end
  end
end
