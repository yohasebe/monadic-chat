# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/monadic/mcp/job_store"

RSpec.describe Monadic::MCP::JobStore do
  after { described_class.reset! }

  it "runs work on a background thread and records the result" do
    job = described_class.submit(tool: "t", arguments: {}) { 21 * 2 }
    expect(job.status).to eq("running")

    job.thread.join # deterministic wait, no sleeps
    stored = described_class.fetch(job.id)
    expect(stored.status).to eq("done")
    expect(stored.result).to eq(42)
  end

  it "records an error when the work raises" do
    job = described_class.submit(tool: "t", arguments: {}) { raise "boom" }
    job.thread.join
    stored = described_class.fetch(job.id)
    expect(stored.status).to eq("error")
    expect(stored.error).to eq("boom")
  end

  it "caps concurrent running jobs" do
    gate = Queue.new
    cap = described_class::MAX_CONCURRENT
    jobs = Array.new(cap) { described_class.submit(tool: "t", arguments: {}) { gate.pop } }

    expect { described_class.submit(tool: "t", arguments: {}) { 1 } }
      .to raise_error(described_class::ConcurrencyLimit, /Too many concurrent jobs/)

    cap.times { gate.push(:go) }
    jobs.each { |j| j.thread.join }
  end

  it "cancels a running job and stops it from flipping to done" do
    gate = Queue.new
    job = described_class.submit(tool: "t", arguments: {}) { gate.pop }
    described_class.cancel(job.id)

    expect(described_class.fetch(job.id).status).to eq("cancelled")
    # Releasing the gate must not resurrect a cancelled job.
    gate.push(:go)
    expect(described_class.fetch(job.id).status).to eq("cancelled")
  end

  it "returns nil when cancelling an unknown job" do
    expect(described_class.cancel("nope")).to be_nil
  end

  it "summarizes jobs without leaking the full result payload" do
    job = described_class.submit(tool: "t", arguments: {}) { "secret" }
    job.thread.join
    summary = described_class.list.find { |j| j[:job_id] == job.id }
    expect(summary).to include(:job_id, :tool, :status)
    expect(summary).not_to have_key(:result)
  end
end
