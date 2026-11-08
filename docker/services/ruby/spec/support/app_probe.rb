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
# line, and whether anything of the group was left afterwards.
module AppProbe
  APP_ROOT = File.expand_path("../..", __dir__)

  def run_app_probe(script, limit: 180)
    Dir.mktmpdir("app-probe-home") do |home|
      tmp = File.join(home, "tmp")
      Dir.mkdir(tmp)
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
          Timeout.timeout(limit) { out << io.read }
        rescue Timeout::Error
          Process.kill("TERM", -pgid) rescue nil
          sleep 1
          Process.kill("KILL", -pgid) rescue nil
          raise "probe timed out:\n#{out.lines.last(25).join}"
        ensure
          status = wait.value
        end
      end
      group_left = begin
        Process.kill(0, -pgid)
        true
      rescue Errno::ESRCH
        false
      end
      line = out.lines.find { |l| l.start_with?("PROBE ") }
      raise "probe failed (#{status.exitstatus}):\n#{out.lines.last(25).join}" unless line

      [JSON.parse(line.delete_prefix("PROBE ")), group_left]
    end
  end
end
