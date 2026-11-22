# frozen_string_literal: true

# Stands in for the docker CLI in the capability agreement check. Knows three
# commands for the Python container: the running-state query, `exec ... true`
# and `exec ... bash -c BODY` (an exec may carry the run's mark,
# `-e MONADIC_RUN_ID=<32 hex>`, as a run with a time limit does). Anything
# else exits 99 whatever the state.
# Every call is logged (one JSON array per line) to MONADIC_TEST_DOCKER_LOG;
# the spec checks each BODY against the command the reader should send. BODY
# is never run.
#
# MONADIC_TEST_DOCKER_STATE (a JSON file) sets the answers:
#   "container": "running" | "stopped" | "missing" | "restarting" | "no_daemon"
#   "reader": { "status": 0, "stdout": "..." } for `bash -c`
require "json"

File.open(ENV.fetch("MONADIC_TEST_DOCKER_LOG"), "a") { |f| f.puts(JSON.generate(ARGV)) }
state = JSON.parse(File.read(ENV.fetch("MONADIC_TEST_DOCKER_STATE")))
container = state.fetch("container")
name = "monadic-chat-python-container"

# The run's mark is taken out before the command is matched.
args = ARGV.dup
mark = args.index { |a| a.match?(/\AMONADIC_RUN_ID=\h{32}\z/) }
args.slice!(mark - 1, 2) if mark && args[mark - 1] == "-e"

kind = case args
       in ["inspect", "-f", "{{.State.Running}}", ^name] then :inspect
       in ["exec", "-w", "/monadic/data", ^name, "true"] then :exec_true
       in ["exec", "-w", "/monadic/data", ^name, "bash", "-c", String] then :exec_bash
       else
         warn "fake docker: unexpected command #{ARGV.inspect}"
         exit 99
       end

if container == "no_daemon"
  warn "Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?"
  exit 1
end

if kind == :inspect
  if container == "missing"
    warn "Error: No such object: #{name}"
    exit 1
  end
  puts(container == "stopped" ? "false" : "true")
  exit 0
end

case container
when "missing"
  warn "Error response from daemon: No such container: #{name}"
  exit 1
when "stopped"
  warn "Error response from daemon: container #{name} is not running"
  exit 1
when "restarting"
  warn "Error response from daemon: Container #{name} is restarting, wait until the container is running"
  exit 1
end

exit 0 if kind == :exec_true

reader = state.fetch("reader")
print reader.fetch("stdout")
exit reader.fetch("status")
