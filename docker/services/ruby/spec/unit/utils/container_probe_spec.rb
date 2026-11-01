# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/monadic/utils/container_probe"

RSpec.describe Monadic::Utils::ContainerProbe do
  let(:name) { Monadic::Shell::CONTAINERS[:python] }
  let(:calls) { [] }

  def status(code)
    double("status", success?: code.zero?, exitstatus: code)
  end

  # Answers each docker command by its subcommand.
  def docker(inspect:, exec: nil)
    allow(Monadic::Shell).to receive(:capture_with_timeout) do |argv, _timeout|
      calls << argv
      answer = argv[1] == "inspect" ? inspect : exec
      answer.respond_to?(:call) ? answer.call : answer
    end
  end

  it "is ready when the container runs and takes a command" do
    docker(inspect: ["true\n", "", status(0)], exec: ["", "", status(0)])
    expect(described_class.check(:python)).to eq(state: :ready)
    expect(calls).to eq([
      ["docker", "inspect", "-f", "{{.State.Running}}", name],
      ["docker", "exec", "-w", "/monadic/data", name, "true"]
    ])
  end

  it "is stopped when the container exists but does not run" do
    docker(inspect: ["false\n", "", status(0)])
    expect(described_class.check(:python)).to eq(state: :stopped)
    expect(calls.map { |argv| argv[1] }).to eq(["inspect"])
  end

  it "is stopped when there is no such container" do
    docker(inspect: ["", "Error: No such object: #{name}\n", status(1)])
    expect(described_class.check(:python)).to eq(state: :stopped)
  end

  it "is unknown when docker fails for another reason" do
    docker(inspect: ["", "Cannot connect to the Docker daemon\n", status(1)])
    expect(described_class.check(:python)).to eq(state: :unknown, reason: "docker did not answer")
  end

  it "is unknown when the running container does not take the command" do
    docker(inspect: ["true\n", "", status(0)], exec: ["", "Error response from daemon: container is restarting\n", status(1)])
    expect(described_class.check(:python)).to eq(state: :unknown, reason: "docker did not answer")
  end

  it "is unknown when docker does not answer in time" do
    docker(inspect: -> { raise Monadic::Shell::TimedOut, "late" })
    expect(described_class.check(:python, timeout: 1)).to eq(state: :unknown, reason: "docker did not answer within 1 seconds")
  end

  it "is unknown when docker cannot be run" do
    docker(inspect: -> { raise Errno::ENOENT, "docker" })
    expect(described_class.check(:python)).to eq(state: :unknown, reason: "docker could not be run")
  end

  it "is unknown for a service it does not know" do
    expect(described_class.check(:nothing)).to eq(state: :unknown, reason: "nothing is not a known service")
  end

  it "never starts a container or writes the command log" do
    docker(inspect: ["false\n", "", status(0)])
    expect(Monadic::Shell).not_to receive(:capture)
    described_class.check(:python)
    expect(calls.flatten).not_to include("start", "up", "ensure-service")
  end
end
