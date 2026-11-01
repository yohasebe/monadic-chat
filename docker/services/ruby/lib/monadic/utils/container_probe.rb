# frozen_string_literal: true

require_relative "../shell"

module Monadic
  module Utils
    # Whether a container can run a command now, found without starting it.
    # Asks docker whether the container runs, then runs `true` in it through
    # the same `docker exec` a tool uses. Both steps have a short limit and
    # are not written to the command log.
    #
    # Returns { state: :ready }, { state: :stopped }, or
    # { state: :unknown, reason: "..." } when docker gives no clear answer.
    # :ready means the container took a command, not that the work will
    # succeed.
    module ContainerProbe
      TIMEOUT = 2 # seconds for each step

      module_function

      def check(service, timeout: TIMEOUT)
        name = Monadic::Shell::CONTAINERS[service]
        return unknown("#{service} is not a known service") unless name

        running = ask(["docker", "inspect", "-f", "{{.State.Running}}", name], timeout)
        return { state: :stopped } if running[:missing]
        return running if running[:state] == :unknown
        return { state: :stopped } unless running[:stdout].strip == "true"

        answered = ask(["docker", "exec", "-w", Monadic::Shell::SHARED_VOLUME, name, "true"], timeout)
        answered[:state] == :unknown ? answered : { state: :ready }
      end

      def ask(argv, timeout)
        stdout, stderr, status = Monadic::Shell.capture_with_timeout(argv, timeout)
        return { stdout: stdout.to_s } if status&.success?
        return { missing: true } if stderr.to_s.match?(/no such (object|container)/i)

        unknown("docker did not answer")
      rescue Monadic::Shell::TimedOut
        unknown("docker did not answer within #{timeout} seconds")
      rescue SystemCallError
        unknown("docker could not be run")
      end

      def unknown(reason)
        { state: :unknown, reason: reason }
      end
      private_class_method :ask, :unknown
    end
  end
end
