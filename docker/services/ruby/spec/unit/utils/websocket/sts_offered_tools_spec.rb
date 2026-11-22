# frozen_string_literal: true

require "spec_helper"
require "json"
require "monadic/utils/extra_logger"
require "monadic/utils/model_spec"
require_relative "../../../../lib/monadic/utils/websocket"
require "monadic/utils/websocket/sts_stream_handler"
require "monadic/utils/container_dependencies"

# Live Conversation runs a returned tool call only if its name was among the
# tools sent to the bridge, not merely in the STS_TOOLS table.
RSpec.describe "Live Conversation offered tools" do
  let(:host) do
    Class.new do
      include WebSocketHelper
      attr_accessor :session
    end.new.tap { |h| h.session = { parameters: {} } }
  end
  let(:ran) { [] }
  let(:entry) do
    calls = ran
    { description: "probe", parameters: { type: "object", properties: {} },
      available?: ->(_provider, _session) { false },
      call: ->(_args, _sess) { calls << :ran; "executed" } }
  end

  before do
    stub_const("WebSocketHelper::STS_TOOLS", { "probe_tool" => entry })
  end

  it "does not run a tool that was not sent to the bridge" do
    state = { tools_enabled: true, provider: "openai" }
    expect(host.send(:sts_ga_tools, state)).to eq([])
    out = host.send(:sts_execute_tool_safely, { name: "probe_tool", parsed_arguments: {} }, state, nil, {})
    expect(out).to include("Unknown tool")
    expect(ran).to be_empty
  end

  it "runs a tool that was sent to the bridge" do
    allow(entry[:available?]).to receive(:call).and_return(true)
    state = { tools_enabled: true, provider: "openai" }
    expect(host.send(:sts_ga_tools, state).map { |t| t[:name] }).to eq(["probe_tool"])
    out = host.send(:sts_execute_tool_safely, { name: "probe_tool", parsed_arguments: {} }, state, nil, {})
    expect(out).to eq("executed")
    expect(ran).to eq([:ran])
  end

  it "records the Gemini declarations the same way" do
    allow(entry[:available?]).to receive(:call).and_return(true)
    state = { tools_enabled: true, provider: "gemini" }
    host.send(:sts_gemini_tools, state)
    expect(state[:offered_tool_names]).to eq(["probe_tool"])
  end
end

# The tool calls one utterance leads to are limited as a typed turn's are.
RSpec.describe "Live Conversation tool rounds of an utterance" do
  let(:host) do
    Class.new do
      include WebSocketHelper
      attr_accessor :session
    end.new.tap { |h| h.session = { parameters: {} } }
  end
  let(:turn) { {} }

  def refusal(rid, name = "probe_tool", arguments = { "q" => rid })
    host.send(:sts_tool_refusal, turn, rid, name, arguments)
  end

  it "runs the calls of the first ten responses and refuses those of a later one" do
    expect((1..10).map { |i| refusal("r#{i}") }).to all(be_nil)
    expect(refusal("r11")).to match(/\A❌ `probe_tool` was not run: this reply has reached its limit of 10 rounds/)
    expect(turn[:tool_rounds_over]).to eq(1)
  end

  it "counts several calls of one response as one round" do
    10.times { |i| refusal("r1", "probe_tool", { "q" => i }) }
    expect(refusal("r2")).to be_nil
  end

  it "refuses the same call made a third time with nothing new in between" do
    expect(refusal("r1", "probe_tool", { "q" => "same" })).to be_nil
    expect(refusal("r2", "probe_tool", { "q" => "same" })).to be_nil
    expect(refusal("r3", "probe_tool", { "q" => "same" })).to start_with("❌ `probe_tool` was already called 2 times")
  end

  it "starts each utterance's count anew, and takes a call with no turn" do
    11.times { |i| refusal("r#{i}") }
    expect(host.send(:sts_tool_refusal, {}, "r1", "probe_tool", {})).to be_nil
    expect(host.send(:sts_tool_refusal, nil, "r1", "probe_tool", {})).to be_nil
  end

  it "answers a refused call without running its tool" do
    ran = []
    stub_const("WebSocketHelper::STS_TOOLS", { "probe_tool" => { call: ->(_args, _sess) { ran << :ran; "executed" } } })
    state = { offered_tool_names: ["probe_tool"] }
    out = host.send(:sts_execute_tool_safely, { name: "probe_tool", parsed_arguments: {}, refusal: "❌ not run" }, state, nil, {})
    expect(out).to eq("❌ not run")
    expect(ran).to be_empty
  end

  it "asks for no further response once refused rounds go on past the grace" do
    conn = double("conn")
    state = { pending_tool_calls: { "r" => {} }, response_open: false, turn: turn, tool_batch_turns: { "r" => turn } }
    turn[:tool_rounds_over] = WebSocketHelper::STS_TOOL_ROUNDS_GRACE + 1
    expect(host).not_to receive(:sts_create_tool_continuation)
    host.send(:sts_maybe_create_tool_response, conn, state, "r")
  end

  it "asks for the next response while the rounds are within the limit or the grace" do
    conn = double("conn")
    state = { pending_tool_calls: { "r" => {} }, response_open: false, turn: turn, tool_batch_turns: { "r" => turn } }
    turn[:tool_rounds_over] = WebSocketHelper::STS_TOOL_ROUNDS_GRACE
    expect(host).to receive(:sts_create_tool_continuation).with(conn, state)
    host.send(:sts_maybe_create_tool_response, conn, state, "r")
  end
end
