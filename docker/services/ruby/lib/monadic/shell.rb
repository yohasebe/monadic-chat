# frozen_string_literal: true

require 'open3'
require 'shellwords'
require 'securerandom'
require_relative 'utils/secret_redactor'

module Monadic
  # Single point of coupling between Ruby code and the docker CLI.
  #
  # The codebase has roughly a dozen callsites that build `docker exec`
  # / `docker cp` strings by hand. Most of them are safe today, but the
  # *form* — string interpolation in a shell heredoc — has produced
  # real defects (the `fetch_webpage` URL injection and the
  # `extract_frames.py` filename injection were both this pattern). The
  # `lint:shell_escape` rule blocks new occurrences; this module is the
  # canonical replacement for existing ones.
  #
  # Three design choices keep the surface narrow:
  #
  #   1. Container names are symbols. The `CONTAINERS` map is the
  #      single source of truth; renaming a container in compose.yml
  #      means changing one Ruby line, not 12.
  #
  #   2. The argv-form (`exec`) takes an array of program + args. No
  #      shell is involved at any level, so `Shellwords.escape` is not
  #      needed and impossible to forget.
  #
  #   3. The shell-form (`bash`) takes a *body* string. Because the
  #      whole body is a single argv element to docker exec, the docker
  #      layer cannot mis-quote it. Callers that want to splice values
  #      into the body must escape them with `Monadic::Shell.escape`;
  #      the rule is local and visible.
  #
  # The module returns Open3.capture3-style tuples so existing callers
  # that already destructure `(stdout, stderr, status)` work unchanged.
  module Shell
    # Container symbol → docker container name. Add new entries here as
    # services are introduced; never hard-code a container name in
    # callers.
    CONTAINERS = {
      ruby:       'monadic-chat-ruby-container',
      python:     'monadic-chat-python-container',
      qdrant:     'monadic-chat-qdrant-container',
      embeddings: 'monadic-chat-embeddings-container',
      extractor:  'monadic-chat-extractor-container',
      privacy:    'monadic-chat-privacy-container',
      selenium:   'monadic-chat-selenium-container'
    }.freeze

    # The shared-volume path *as seen from inside any container*. Always
    # the same regardless of dev / production mode. Ruby code that
    # needs the equivalent host-side path uses
    # `Monadic::Utils::Environment.data_path`.
    SHARED_VOLUME = '/monadic/data'

    class UnknownContainerError < ArgumentError; end
    class TimedOut < StandardError; end

    module_function

    # Run an argv array inside a container, with no shell. Safest form;
    # no interpolation can break out of an argument boundary because
    # `Open3.capture3` passes the array directly to execve.
    #
    # @param container [Symbol] container key from CONTAINERS
    # @param argv [Array<String>] program followed by arguments
    # @param workdir [String] working directory inside the container
    # @param env [Hash{String=>String}] additional env vars (rare;
    #   normally callers configure env via the compose file)
    # @param timeout [Numeric, nil] passed through to Open3.capture3
    # @return [Array(String, String, Process::Status)]
    def exec(container:, argv:, workdir: SHARED_VOLUME, env: {}, timeout: nil)
      raise ArgumentError, 'argv must be a non-empty array' unless argv.is_a?(Array) && !argv.empty?
      name = resolve_container(container)
      options = ['-w', workdir]
      env.each_pair { |k, v| options.concat(['-e', "#{k}=#{v}"]) }
      # A run with a time limit is marked, so that stopping it also stops
      # what it started in the container (see stop_in_container). The log
      # shows the command as asked, without the mark.
      run_id = SecureRandom.hex(16) if timeout
      mark = run_id ? ['-e', "#{RUN_ID_VAR}=#{run_id}"] : []
      command = argv.map(&:to_s)
      on_stop = run_id && -> { stop_in_container(name, run_id) }
      capture(['docker', 'exec', *options, *mark, name, *command], timeout: timeout, on_stop: on_stop,
                                                                     log_as: ['docker', 'exec', *options, name, *command])
    end

    # Runs argv on this side (not in a container), with env and chdir, the
    # same way: with a timeout it is stopped once it runs over (TimedOut),
    # and stopped with its whole process group when the calling thread is.
    def run(argv:, env: {}, chdir: nil, timeout: nil)
      raise ArgumentError, 'argv must be a non-empty array' unless argv.is_a?(Array) && !argv.empty?

      capture(argv.map(&:to_s), timeout: timeout, env: env, chdir: chdir)
    end

    RUN_ID_VAR = 'MONADIC_RUN_ID'

    # Stopping `docker exec` ends the client on this side; the process it
    # started in the container, and that process's own children (ffmpeg
    # started by a Python script), go on. They all carry the run's mark in
    # their environment, so they are found by it there and stopped. Only sh
    # and tr are used: the Python image has no pgrep or pkill.
    # The mark must be a whole entry of the environment, not part of another.
    STOP_MARKED = <<~'SH'
      mark="MONADIC_RUN_ID=$1"
      nl='
      '
      signal_marked() {
        for d in /proc/[0-9]*; do
          case "$nl$(tr '\000' '\n' < "$d/environ" 2>/dev/null)$nl" in
            *"$nl$mark$nl"*) kill -s "$1" "${d#/proc/}" 2>/dev/null ;;
          esac
        done
      }
      signal_marked TERM
      sleep 0.5
      signal_marked KILL
      exit 0
    SH

    def stop_in_container(name, run_id)
      return unless run_id.to_s.match?(/\A\h{32}\z/)

      capture_with_timeout(['docker', 'exec', name, 'sh', '-c', STOP_MARKED, 'sh', run_id], STOP_TIMEOUT)
    rescue StandardError
      nil # best effort: the container may be gone
    end

    STOP_TIMEOUT = 5 # seconds; the reply waits a little longer (REPLY_STOP_WAIT)

    # As STOP_MARKED, then says how many marked processes are left.
    STOP_AND_COUNT = <<~'SH'
      mark="MONADIC_RUN_ID=$1"
      nl='
      '
      signal_marked() {
        n=0
        for d in /proc/[0-9]*; do
          case "$nl$(tr '\000' '\n' < "$d/environ" 2>/dev/null)$nl" in
            *"$nl$mark$nl"*) n=$((n + 1)); [ -n "$1" ] && kill -s "$1" "${d#/proc/}" 2>/dev/null ;;
          esac
        done
      }
      signal_marked TERM
      sleep 0.5
      signal_marked KILL
      sleep 0.2
      signal_marked ''
      echo "left=$n"
    SH

    # Stops what run_id started in the container name and says whether it
    # is known to be gone: the count of marked processes left came back as
    # 0, or the container is not running (nothing runs in it). false when
    # that could not be told within timeout (the container did not answer,
    # or answered something else).
    def stop_and_confirm(name, run_id, timeout: STOP_TIMEOUT)
      return false unless run_id.to_s.match?(/\A\h{32}\z/) && timeout.positive?

      done = run_until(['docker', 'exec', name, 'sh', '-c', STOP_AND_COUNT, 'sh', run_id], clock + timeout)
      return false unless done

      out, err, status = done
      return true if status.success? && out.strip == 'left=0'

      !status.success? && not_running?(err, name)
    rescue StandardError
      false
    end

    # Whether docker's daemon said that the container name is not running
    # or not there (nothing runs in it). Anything else (the daemon not
    # answering, a refused socket, another container) is not that.
    def not_running?(err, name)
      container = /(?:#{Regexp.escape(name)}|\h{12,64})/
      err.to_s.each_line.any? do |line|
        line.match?(/\AError response from daemon: (?:container #{container} is not running|No such container: #{Regexp.escape(name)})\s*\z/)
      end
    end

    # Runs argv until deadline (monotonic seconds), all of it: the command,
    # reading its output and stopping it (also when this thread is stopped:
    # popen3 waits for the command before it returns). [stdout, stderr,
    # status] when it ended in time; nil when it was stopped.
    def run_until(argv, deadline)
      Open3.popen3(*argv, pgroup: true) do |input, out, err, wait|
        ended = false
        begin
          input.close
          readers = [out, err].map { |io| Thread.new { read_all(io) } }
          if wait.join([deadline - clock, 0].max) && readers.all? { |t| t.join([deadline - clock, 0].max) }
            ended = true
            next [readers[0].value, readers[1].value, wait.value]
          end

          nil
        ensure
          unless ended
            begin
              Process.kill('KILL', -wait.pid)
            rescue Errno::ESRCH, Errno::EPERM
              nil
            end
            [out, err].each { |io| io.close unless io.closed? }
            readers&.each(&:kill)
          end
        end
      end
    end

    # What exec_stream gives back. stdout and stderr hold at most their
    # limits; failure is nil, :deadline (it did not end in time) or
    # :too_large (it wrote more than a limit).
    Streamed = Struct.new(:stdout, :stderr, :status, :failure, keyword_init: true)

    # Runs argv in the container with bytes on its stdin, writing them and
    # reading its stdout and stderr at the same time, each up to its limit,
    # until deadline (monotonic seconds). Nothing of it is logged (it may
    # carry a chat's file). The run is marked (run_id): when it does not
    # end by itself (too late, too much output, an error, the thread
    # stopped), the local process group is stopped and so is what it
    # started in the container, and stopped (a lambda) is told once whether
    # that is known to be gone. A run that ends by itself with status 0 is
    # gone; any other is stopped and checked (within STOP_TIMEOUT for all
    # of the stopping: the threads, the pipes and the check).
    def exec_stream(container:, argv:, stdin:, deadline:, stdout_limit:, stderr_limit:, run_id:, stopped:)
      raise ArgumentError, 'argv must be a non-empty array' unless argv.is_a?(Array) && !argv.empty?
      raise ArgumentError, 'run_id must be 32 hex digits' unless run_id.to_s.match?(/\A\h{32}\z/)

      name = resolve_container(container)
      docker_argv = ['docker', 'exec', '-i', '-w', SHARED_VOLUME, '-e', "#{RUN_ID_VAR}=#{run_id}", name, *argv.map(&:to_s)]
      ended = false
      Open3.popen3(*docker_argv, pgroup: true) do |input, out, err, wait|
        threads = []
        begin
          threads << Thread.new { write_all(input, stdin) }
          stdout = Bounded.new(stdout_limit)
          stderr = Bounded.new(stderr_limit)
          threads << Thread.new { stdout.read_from(out) }
          threads << Thread.new { stderr.read_from(err) }
          failure = nil
          until wait.join([[deadline - clock, 0].max, 0.05].min)
            failure = :too_large if stdout.over? || stderr.over?
            failure ||= :deadline if clock >= deadline
            break if failure
          end
          # Ended by itself: what it wrote is read to its end (the pipes close).
          if failure.nil?
            failure = :deadline unless threads[1..].all? { |t| t.join([deadline - clock, 0].max) }
            failure ||= :too_large if stdout.over? || stderr.over?
          end
          ended = failure.nil?
          Streamed.new(stdout: stdout.text, stderr: stderr.text, status: ended ? wait.value : nil, failure: failure)
        ensure
          ended &&= wait.value.success?
          gone = Thread.handle_interrupt(Object => :never) { stop_run(name, run_id, wait, [input, out, err], threads, ended) }
          stopped.call(gone)
        end
      end
    end

    # After exec_stream: a run that did not end well is stopped here and in
    # the container, its pipes closed and its threads ended, within
    # STOP_TIMEOUT. Whether it is known to be gone.
    def stop_run(name, run_id, wait, pipes, threads, ended)
      until_at = clock + STOP_TIMEOUT
      stop_group(wait.pid) unless ended
      pipes.each { |io| io.close unless io.closed? }
      threads.each do |t|
        next if t.join([[until_at - clock, 0].max, READ_GRACE].min)

        t.kill
        t.join([[until_at - clock, 0].max, READ_GRACE].min)
      end
      return false if threads.any?(&:alive?)
      return true if ended

      stop_and_confirm(name, run_id, timeout: until_at - clock)
    end

    # Bytes read from a pipe, up to a limit (more is noted, not kept).
    class Bounded
      def initialize(limit)
        @limit = limit
        @data = +''.b
        @over = false
        @lock = Mutex.new
      end

      def read_from(io)
        loop do
          chunk = io.readpartial(65_536)
          @lock.synchronize do
            room = @limit - @data.bytesize
            @over = true if chunk.bytesize > room
            @data << chunk.byteslice(0, [room, 0].max)
          end
          break if over?
        end
      rescue IOError
        nil
      end

      def over?
        @lock.synchronize { @over }
      end

      def text
        @lock.synchronize { @data.dup.force_encoding(Encoding::UTF_8) }
      end
    end

    def write_all(io, bytes)
      io.write(bytes)
    rescue IOError, SystemCallError
      nil # the run ended or was stopped; that is told by its end
    ensure
      io.close unless io.closed?
    end

    def clock
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    # Run a `bash -c BODY` inside a container. The body is passed as a
    # single argv element, so the docker / outer-shell layer cannot
    # mis-quote it; the only escaping concern is *inside* the body, and
    # is the caller's responsibility.
    #
    # When the body is built by interpolating user-controlled values,
    # the caller must wrap each value in `Monadic::Shell.escape`. The
    # `lint:shell_escape` rule enforces this for new code.
    def bash(container:, body:, workdir: SHARED_VOLUME, env: {}, timeout: nil)
      raise ArgumentError, 'body must be a String' unless body.is_a?(String)
      exec(container: container, argv: ['bash', '-c', body],
           workdir: workdir, env: env, timeout: timeout)
    end

    # Copy a host file into the container at the given path. host_path
    # and container_path are passed straight to `docker cp`; both are
    # quoted by Open3 and never reach a shell.
    def cp_to_container(container:, host_path:, container_path:)
      capture(['docker', 'cp', host_path.to_s,
               "#{resolve_container(container)}:#{container_path}"])
    end

    # Copy a file out of the container onto the host.
    def cp_from_container(container:, container_path:, host_path:)
      capture(['docker', 'cp',
               "#{resolve_container(container)}:#{container_path}",
               host_path.to_s])
    end

    # Convenience re-export so callers do not need to require shellwords
    # separately. `Monadic::Shell.escape(value)` is the canonical way
    # to make a string safe for interpolation into a `bash` body.
    def escape(value)
      Shellwords.escape(value.to_s)
    end

    # Resolve a container symbol to its full docker name. Public so
    # callers that still need to construct shell strings by hand (e.g.
    # legacy code awaiting migration) can stay aligned with the map.
    def resolve_container(name)
      CONTAINERS.fetch(name) do
        raise UnknownContainerError, "Unknown container: #{name.inspect} (allowed: #{CONTAINERS.keys.inspect})"
      end
    end

    # Mirror capture_command's command-log entry format so operators
    # can still grep /monadic/log/command.log when debugging Shell-routed
    # invocations. Failures during logging are intentionally swallowed —
    # logging is a diagnostic aid, never a correctness gate.
    def log_invocation(argv, stdout, stderr)
      log_path = command_log_file
      return unless log_path
      Monadic::Utils::Environment.rotate_log(log_path) if defined?(Monadic::Utils::Environment) &&
                                                         Monadic::Utils::Environment.respond_to?(:rotate_log)
      File.open(log_path, 'a') do |f|
        f.puts "Time: #{Time.now}"
        redact = Monadic::Utils::SecretRedactor.method(:redact)
        f.puts "Command: #{redact.call(Shellwords.join(argv.map(&:to_s)))}"
        f.puts "Error: #{redact.call(stderr)}" if stderr.to_s.strip.length.positive?
        f.puts "Output: #{redact.call(stdout)}"
        f.puts '-----------------------------------'
      end
    rescue StandardError
      # best-effort
    end

    def command_log_file
      return @command_log_file if defined?(@command_log_file)
      @command_log_file = if defined?(Monadic::Utils::Environment) &&
                            Monadic::Utils::Environment.respond_to?(:command_log_file)
                            Monadic::Utils::Environment.command_log_file
                          end
    end

    # @!visibility private
    # With a timeout the command is stopped once it runs over and TimedOut
    # is raised. (Open3.capture3 has no timeout option: passing one raised
    # ArgumentError.) The command runs in a process group of its own and the
    # whole group is stopped, so a child it started cannot keep the output
    # open and hold the caller past the limit. Stopping `docker exec` ends the
    # client, not necessarily the process it started in the container.
    # env and chdir apply to the command on this side; log_as is what the
    # command log shows (argv when not given).
    def capture(argv, timeout: nil, on_stop: nil, env: {}, chdir: nil, log_as: nil)
      options = chdir ? { chdir: chdir } : {}
      # An environment is passed only when there is one (Open3 takes it first).
      leading = env.empty? ? [] : [env]
      stdout, stderr, status = if timeout
                                 capture_with_timeout(argv, timeout, on_stop: on_stop, leading: leading, options: options)
                               else
                                 Open3.capture3(*leading, *argv, **options)
                               end
      log_invocation(log_as || argv, stdout, stderr)
      [stdout, stderr, status]
    end

    READ_GRACE = 2 # seconds to collect output once the command has ended or been stopped

    def capture_with_timeout(argv, timeout, on_stop: nil, leading: [], options: {})
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      Open3.popen3(*leading, *argv, pgroup: true, **options) do |stdin, out, err, wait|
        result = run_to_end_or_stop(argv, timeout, deadline, stdin, out, err, wait)
        done = true
        result
      ensure
        # Run over, or interrupted (the calling thread killed, as Cancel
        # does): the group is stopped rather than left running to its end,
        # including a child still holding the output after the command
        # itself has ended, and so is what it started in a container.
        unless done
          stop_group(wait.pid) if wait
          [out, err].each { |io| io.close if io && !io.closed? }
          on_stop&.call
        end
      end
    end

    def run_to_end_or_stop(argv, timeout, deadline, stdin, out, err, wait)
      stdin.close
      readers = [out, err].map { |io| Thread.new { read_all(io) } }
      finished = wait.join(timeout)
      # A child left running can hold the pipes open after the command
      # itself ends; output is read until the deadline, not until EOF.
      remaining = [deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC), 0].max
      drained = finished && readers.all? { |t| t.join(remaining) }
      unless finished && drained
        stop_group(wait.pid)
        wait.join(READ_GRACE)
        readers.each { |t| t.join(READ_GRACE) }
        [out, err].each { |io| io.close unless io.closed? }
        raise TimedOut, "#{File.basename(argv.first.to_s)} did not finish within #{timeout} seconds"
      end
      [readers[0].value, readers[1].value, wait.value]
    end

    def read_all(io)
      io.read
    rescue IOError
      ''
    end

    def stop_group(pgid)
      Process.kill('TERM', -pgid)
      sleep 0.5
      Process.kill('KILL', -pgid)
    rescue Errno::ESRCH, Errno::EPERM
      nil
    end
  end
end
