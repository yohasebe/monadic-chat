# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../../../lib/monadic/utils/trial_log"
require_relative "../../../lib/monadic/history/store"

RSpec.describe Monadic::Utils::TrialLog do
  around do |example|
    Dir.mktmpdir { |dir| @dir = dir; example.run }
  end

  let(:env) { { described_class::FLAG => @dir } }
  let(:calls) do
    [
      { "id" => "call_1", "function" => { "name" => "fetch_text_from_pdf", "arguments" => '{"pdf":"draft.pdf"}' } },
      { "id" => "call_2", "function" => { "name" => "fetch_text_from_pdf", "arguments" => '{"pdf":"draft.pdf"}' } }
    ]
  end

  def events
    path = File.join(@dir, described_class::FILE_NAME)
    File.exist?(path) ? File.readlines(path).map { |l| JSON.parse(l) } : []
  end

  it "writes nothing without the flag" do
    described_class.tool_calls(calls, app: "A", depth: 0, env: {})
    described_class.usage({ "input_tokens" => 1 }, app: "A", env: {})
    expect(Dir.children(@dir)).to be_empty
  end

  it "keeps every call the model sent, duplicates included" do
    described_class.tool_calls(calls, app: "A", depth: 1, env: env)
    expect(events.map { |e| [e["event"], e["tool"], e["call_id"], e["depth"]] })
      .to eq([["tool_requested", "fetch_text_from_pdf", "call_1", 1], ["tool_requested", "fetch_text_from_pdf", "call_2", 1]])
    expect(events.map { |e| e["arguments_digest"] }.uniq.size).to eq(1)
  end

  it "makes the file the owner's only" do
    described_class.usage({ "input_tokens" => 1 }, app: "A", env: env)
    expect(File.stat(File.join(@dir, described_class::FILE_NAME)).mode & 0o777).to eq(0o600)
  end

  it "keeps no argument text" do
    described_class.tool_calls(calls, app: "A", depth: 0, env: env)
    expect(File.read(File.join(@dir, described_class::FILE_NAME))).not_to include("draft.pdf")
  end

  it "records token counts, cached ones included" do
    described_class.usage({ "input_tokens" => 120, "output_tokens" => 30,
                            "input_tokens_details" => { "cached_tokens" => 100 } }, app: "A", env: env)
    expect(events.last).to include("event" => "usage", "input_tokens" => 120, "cached_tokens" => 100, "output_tokens" => 30)
  end

  it "writes nothing when the folder does not exist" do
    missing = File.join(@dir, "missing")
    described_class.usage({ "input_tokens" => 1 }, app: "A", env: { described_class::FLAG => missing })
    expect(File.exist?(missing)).to be false
  end

  it "writes nothing in the shared folder" do
    allow(Monadic::Utils::Environment).to receive(:shared_volume).and_return(@dir)
    inside = File.join(@dir, "logs")
    Dir.mkdir(inside)
    described_class.usage({ "input_tokens" => 1 }, app: "A", env: { described_class::FLAG => inside })
    expect(Dir.children(inside)).to be_empty
  end

  it "never raises when the folder cannot be written" do
    blocked = File.join(@dir, "file")
    File.write(blocked, "")
    expect { described_class.usage({ "input_tokens" => 1 }, app: "A", env: { described_class::FLAG => File.join(blocked, "sub") }) }
      .not_to raise_error
  end
end
