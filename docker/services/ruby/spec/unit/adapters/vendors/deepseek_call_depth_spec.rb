# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/monadic/adapters/vendors/deepseek_helper"

# DeepSeek counts the tool rounds of a turn in the session, as the other
# helpers do, so the request after MAX_FUNC_CALLS rounds goes without tools.
RSpec.describe "DeepSeek tool rounds in one turn" do
  let(:helper) { Class.new { include DeepSeekHelper }.new }
  let(:tools) do
    { "call_0" => { "choices" => [{ "message" => { "tool_calls" => [
      { "id" => "c1", "type" => "function", "function" => { "name" => "some_tool", "arguments" => "{}" } }
    ] } }] } }
  end
  let(:session) { { parameters: { "app_name" => "SpecApp" }, messages: [], call_depth_per_turn: 0 } }

  it "counts each round in the session and stops with a formatted error after MAX_FUNC_CALLS" do
    allow(helper).to receive(:process_functions).and_return([:next_round])
    DeepSeekHelper::MAX_FUNC_CALLS.times do
      expect(helper.send(:dispatch_deepseek_tool_results, tools, nil, "tool_calls", {}, session, "SpecApp", 0)).to eq([:next_round])
    end
    expect(session[:call_depth_per_turn]).to eq(DeepSeekHelper::MAX_FUNC_CALLS)

    result = helper.send(:dispatch_deepseek_tool_results, tools, nil, "tool_calls", {}, session, "SpecApp", 0)
    expect(result.first["type"]).to eq("error")
    expect(result.first["content"]).to include("Maximum function call depth exceeded")
    expect(helper).to have_received(:process_functions).exactly(DeepSeekHelper::MAX_FUNC_CALLS).times
  end
end
