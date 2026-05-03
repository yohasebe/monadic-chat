# frozen_string_literal: true

require 'open3'
require 'shellwords'

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
      pgvector:   'monadic-chat-pgvector-container',
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
      docker_argv = ['docker', 'exec', '-w', workdir]
      env.each_pair { |k, v| docker_argv.concat(['-e', "#{k}=#{v}"]) }
      docker_argv << resolve_container(container)
      docker_argv.concat(argv.map(&:to_s))
      capture(docker_argv, timeout: timeout)
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

    # @!visibility private
    def capture(argv, timeout: nil)
      if timeout
        Open3.capture3(*argv, timeout: timeout)
      else
        Open3.capture3(*argv)
      end
    end
  end
end
