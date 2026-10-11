# frozen_string_literal: true

require "spec_helper"
require "securerandom"
require_relative "../../lib/monadic/shell"

# Cancel kills the thread running a command in the Python container. The
# docker client on this side ends with it; this checks that what the command
# started inside the container (a child of a child) ends too.
RSpec.describe "Stopping a command run in the Python container", type: :integration do
  CONTAINER = Monadic::Shell::CONTAINERS[:python]

  def running(marker)
    out, = Open3.capture2("docker", "exec", CONTAINER, "sh", "-c",
                          'for d in /proc/[0-9]*; do tr "\000" " " < "$d/cmdline" 2>/dev/null; echo; done')
    out.lines.count { |line| line.include?(marker) }
  end

  before(:all) do
    skip "Python container is not running" unless system("docker", "inspect", "-f", "{{.State.Running}}", CONTAINER,
                                                         out: File::NULL, err: File::NULL)
  end

  it "stops the processes the command started in the container when its thread is killed" do
    marker = "monadic-stop-spec-#{Process.pid}-#{rand(1_000_000)}"
    runner = Thread.new do
      Monadic::Shell.exec(container: :python, argv: ["sh", "-c", "sh -c 'sleep 60; :' #{marker} & sleep 60"],
                          workdir: "/tmp", timeout: 120)
    end
    deadline = Time.now + 15
    sleep 0.2 until running(marker).positive? || !runner.alive? || Time.now > deadline
    expect(running(marker)).to be_positive

    runner.kill
    runner.join(15)
    expect(running(marker)).to eq(0)
  ensure
    system("docker", "exec", CONTAINER, "sh", "-c",
           "for d in /proc/[0-9]*; do case \"$(tr '\\000' ' ' < $d/cmdline 2>/dev/null)\" in *#{marker}*) kill -9 ${d#/proc/};; esac; done",
           out: File::NULL, err: File::NULL)
  end

  it "stops only processes whose environment has the mark as a whole entry" do
    id = SecureRandom.hex(16)
    # The decoy carries the id under another name, and a mark of its own to
    # be cleaned up by (with the sleep it starts).
    cleanup = SecureRandom.hex(16)
    target = "monadic-stop-target-#{id[0, 8]}"
    decoy = "monadic-stop-decoy-#{id[0, 8]}"
    system("docker", "exec", "-d", "-e", "MONADIC_RUN_ID=#{id}", CONTAINER, "sh", "-c", "sleep 60; : #{target}")
    system("docker", "exec", "-d", "-e", "MONADIC_RUN_ID=#{cleanup}", "-e", "OTHER_MONADIC_RUN_ID=#{id}",
           "-e", "NOTE=x#{id}", CONTAINER, "sh", "-c", "sleep 60; : #{decoy}")
    deadline = Time.now + 10
    sleep 0.2 until (running(target).positive? && running(decoy).positive?) || Time.now > deadline

    Monadic::Shell.stop_in_container(CONTAINER, id)

    expect(running(target)).to eq(0)
    expect(running(decoy)).to eq(1)
  ensure
    [id, cleanup].compact.each { |run| Monadic::Shell.stop_in_container(CONTAINER, run) }
  end
end
