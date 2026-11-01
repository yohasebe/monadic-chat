# frozen_string_literal: true

require_relative "../shell"

module Monadic
  module Utils
    # Whether a container takes a command now, found without starting it.
    # Asks docker whether the container runs, then runs `true` in it through
    # the same `docker exec` a tool uses. Both steps share one time limit and
    # are not written to the command log.
    #
    # Returns { state: :ready } (the container ran the command), { state:
    # :stopped }, or { state: :unknown, reason: "..." } when docker gives no
    # clear answer. :ready says nothing about the programs or files a tool
    # needs inside the container.
    module ContainerProbe
      TIMEOUT = 1.0 # seconds for both steps together

      module_function

      def check(service, timeout: TIMEOUT)
        name = Monadic::Shell::CONTAINERS[service]
        return unknown("#{service} is not a known service") unless name

        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
        running = ask(["docker", "inspect", "-f", "{{.State.Running}}", name], deadline, timeout)
        return { state: :stopped } if running[:missing]
        return running if running[:state] == :unknown

        case running[:stdout].strip
        when "false" then return { state: :stopped }
        when "true" then nil
        else return unknown("docker gave no running state")
        end

        answered = ask(["docker", "exec", "-w", Monadic::Shell::SHARED_VOLUME, name, "true"], deadline, timeout)
        return { state: :stopped } if answered[:missing]
        return answered if answered[:state] == :unknown

        answered.key?(:stdout) ? { state: :ready } : unknown("docker did not answer")
      end

      def ask(argv, deadline, timeout)
        left = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        return unknown("docker did not answer within #{timeout} seconds") unless left.positive?

        stdout, stderr, status = Monadic::Shell.capture_with_timeout(argv, left)
        return { stdout: stdout.to_s } if status&.success?
        return { missing: true } if stderr.to_s.match?(/no such (object|container)|is not running/i)

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
