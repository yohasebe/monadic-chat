# frozen_string_literal: true

require "json"
require "open3"
require "timeout"
require "tmpdir"
require "fileutils"
require "rbconfig"

# Runs the app with a probe script (a Ruby program that loads config.ru,
# serves it and drives it) in a child process of its own group, with its own
# HOME and a time limit. Returns what the script printed on its "PROBE "
# line, and whether anything of the group was left afterwards. With home:
# that HOME is used (and kept), so that a second run finds what the first
# left there, as the app does after a restart.
module AppProbe
  APP_ROOT = File.expand_path("../..", __dir__)

  def run_app_probe(script, limit: 180, home: nil)
    return probe_in(script, limit, home) if home

    Dir.mktmpdir("app-probe-home") { |made| probe_in(script, limit, made) }
  end

  # Whether a process of the probe's group is still there, after the time it
  # takes the system to end those its leader left: false, or what is left
  # (for the failure to say).
  def group_left(pgid, wait: 2.0)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + wait
    loop do
      begin
        Process.kill(0, -pgid)
      rescue Errno::ESRCH
        return false
      end
      break if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.1
    end
    left = IO.popen(%w[ps -eo pid=,pgid=,stat=,args=], &:read).lines.select { |l| l.split[1].to_i == pgid }
    "processes left in group #{pgid}:\n#{left.join}"
  end

  def probe_in(script, limit, home)
    begin
      tmp = File.join(home, "tmp")
      FileUtils.mkdir_p(tmp)
      FileUtils.mkdir_p(File.join(home, "monadic", "data"))
      FileUtils.mkdir_p(File.join(home, "monadic", "config"))
      File.write(File.join(home, "monadic", "config", "env"), "OPENAI_API_KEY=sk-test-not-used\n")
      kept = ENV.to_h.select { |k, _| k == "PATH" || k == "LANG" || k.start_with?("BUNDLE", "GEM_", "RUBY", "RBENV") }
      env = kept.merge("HOME" => home, "IN_CONTAINER" => "false", "TMPDIR" => tmp)
      out = +""
      status = nil
      pgid = nil
      Open3.popen2e(env, RbConfig.ruby, "-e", script, chdir: APP_ROOT, unsetenv_others: true, pgroup: true) do |stdin, io, wait|
        stdin.close
        pgid = Process.getpgid(wait.pid)
        begin
          # Line by line, so that a run that stops partway shows how far it got.
          Timeout.timeout(limit) { io.each_line { |line| out << line } }
        rescue Timeout::Error
          Process.kill("TERM", -pgid) rescue nil
          sleep 1
          Process.kill("KILL", -pgid) rescue nil
          raise "probe timed out:\n#{out.lines.last(25).join}"
        ensure
          status = wait.value
        end
      end
      group_left = group_left(pgid)
      line = out.lines.find { |l| l.start_with?("PROBE ") }
      raise "probe failed (#{status.exitstatus}):\n#{out.lines.last(25).join}" unless line

      [JSON.parse(line.delete_prefix("PROBE ")), group_left]
    end
  end
end
