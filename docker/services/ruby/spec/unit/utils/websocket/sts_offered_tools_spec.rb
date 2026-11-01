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
