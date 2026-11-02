# frozen_string_literal: true

require "open3"
require "rbconfig"

module CapabilityAgreement
  # Starts a check in a process of its own: only the variables it is given
  # (Ruby and Bundler's, a HOME of its own, a short PATH), Ruby's network
  # connections stopped once its gems are set up (no_network.rb), a process
  # group of its own and a time limit for the run and its output.
  module IsolatedRun
    SUPPORT = __dir__
    # Set outside, before a start: the check's process must not see it.
    OUTER_MARKER = "MONADIC_TEST_OUTER_MARKER"

    module_function

    # What the check's process needs to find its gems. It reads no Bundler
    # config file (BUNDLE_IGNORE_CONFIG): the settings that place and select
    # the gems are passed as they stand in this process.
    def bundler_env
      env = ENV.to_h.slice("BUNDLE_GEMFILE", "GEM_HOME", "GEM_PATH")
      if defined?(Bundler)
        { path: "BUNDLE_PATH", without: "BUNDLE_WITHOUT", with: "BUNDLE_WITH", deployment: "BUNDLE_DEPLOYMENT" }
          .each do |setting, name|
            value = Bundler.settings[setting]
            value = File.expand_path(value, Bundler.root) if setting == :path && value
            value = Array(value).join(":") if value.is_a?(Array)
            env[name] = value.to_s unless value.nil? || value.to_s.empty?
          end
      end
      env.merge("BUNDLE_IGNORE_CONFIG" => "1")
    end

    def env(home:, bin:, events:, preload: [])
      bundler_env.merge(
        "HOME" => home,
        "PATH" => [bin, RbConfig::CONFIG["bindir"], "/usr/bin", "/bin"].join(":"),
        "LANG" => "C.UTF-8",
        "IN_CONTAINER" => "false",
        "RUBYLIB" => File.dirname(SUPPORT),
        "RUBYOPT" => (["-rbundler/setup", "-rcapability_agreement/no_network"] +
                      preload.map { |name| "-rcapability_agreement/#{name}" }).join(" "),
        "MONADIC_TEST_NET_EVENTS" => events
      )
    end

    # Runs argv with env and returns its stdout. Raises when it does not
    # finish in time (its process group is killed) or fails.
    def run(env, argv, chdir:, time_limit:)
      marker_before = ENV[OUTER_MARKER]
      ENV[OUTER_MARKER] = "outside"
      clock = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
      deadline = clock.call + time_limit
      Open3.popen3(env, *argv, unsetenv_others: true, pgroup: true, chdir: chdir) do |stdin, out, err, wait|
        stdin.close
        output = [out, err].map { |io| Thread.new { io.read } }
        stop = lambda do
          Process.kill("KILL", -wait.pid)
        rescue Errno::ESRCH
          nil
        end
        finished = wait.join(time_limit)
        stop.call && wait.join(5) unless finished
        # The output is read until the same deadline, then a short grace: a
        # process the check started can hold it open after the check ends.
        # Output still open then counts as not finished.
        read = output.map { |t| t.join([deadline - clock.call, 5].max) ? t.value.to_s : nil }
        unless read.all?
          finished = false
          stop.call
          output.each(&:kill)
        end
        error = read.last.to_s
        error = error[-3000..] || error
        raise "the check did not finish within #{time_limit} seconds:\n#{error}" unless finished
        raise "the check failed (exit #{wait.value.exitstatus}):\n#{error}" unless wait.value.success?

        read.first
      end
    ensure
      ENV[OUTER_MARKER] = marker_before
    end
  end
end
