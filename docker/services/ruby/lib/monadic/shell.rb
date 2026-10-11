# frozen_string_literal: true

require 'open3'
require 'shellwords'
require 'securerandom'

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
      docker_argv = ['docker', 'exec', '-w', workdir]
      env.each_pair { |k, v| docker_argv.concat(['-e', "#{k}=#{v}"]) }
      # A run with a time limit is marked, so that stopping it also stops
      # what it started in the container (see stop_in_container).
      run_id = SecureRandom.hex(16) if timeout
      docker_argv.concat(['-e', "#{RUN_ID_VAR}=#{run_id}"]) if run_id
      docker_argv << name
      docker_argv.concat(argv.map(&:to_s))
      on_stop = run_id && -> { stop_in_container(name, run_id) }
      capture(docker_argv, timeout: timeout, on_stop: on_stop)
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
      File.open(log_path, 'a') do |f|
        f.puts "Time: #{Time.now}"
        f.puts "Command: #{argv.join(' ')}"
        f.puts "Error: #{stderr}" if stderr.to_s.strip.length.positive?
        f.puts "Output: #{stdout}"
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
    def capture(argv, timeout: nil, on_stop: nil)
      stdout, stderr, status = timeout ? capture_with_timeout(argv, timeout, on_stop: on_stop) : Open3.capture3(*argv)
      log_invocation(argv, stdout, stderr)
      [stdout, stderr, status]
    end

    READ_GRACE = 2 # seconds to collect output once the command has ended or been stopped

    def capture_with_timeout(argv, timeout, on_stop: nil)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      Open3.popen3(*argv, pgroup: true) do |stdin, out, err, wait|
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
