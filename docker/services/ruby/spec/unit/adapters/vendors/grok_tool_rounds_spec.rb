# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/monadic/adapters/vendors/grok_helper"

# A turn that calls tools more than once: every round of the turn goes back
# with the next request, in order.
RSpec.describe "Grok tool rounds of a turn" do
  let(:helper) do
    Class.new { include GrokHelper }.new.tap do |h|
      allow(h).to receive(:with_workbench_looks) { |returns, *_rest, **_kw| returns }
    end
  end

  def call(id)
    { "type" => "function_call", "id" => id, "call_id" => id, "name" => "t", "arguments" => "{}" }
  end

  def sent(obj)
    session = { parameters: obj, messages: [] }
    context = [{ "role" => "system", "text" => "S" }, { "role" => "user", "text" => "Go" }]
    messages, = helper.send(:build_grok_messages, context, "tool", obj, session, {}, nil, nil, nil)
    helper.convert_messages_to_input(messages).filter_map do |item|
      case item["type"]
      when "function_call" then [:call, item["call_id"]]
      when "function_call_output" then [:result, item["call_id"]]
      end
    end
  end

  it "sends the earlier rounds before the latest one, each call before its result" do
    obj = { "earlier_tool_rounds" => [[[call("c1")], [{ "call_id" => "c1", "content" => "one" }]]],
            "assistant_function_calls" => [call("c2")],
            "function_returns" => [{ "call_id" => "c2", "content" => "two" }] }
    expect(sent(obj)).to eq([[:call, "c1"], [:result, "c1"], [:call, "c2"], [:result, "c2"]])
  end

  it "keeps a round when the next one begins" do
    obj = { "assistant_function_calls" => [call("c1")], "function_returns" => [{ "call_id" => "c1", "content" => "one" }] }
    helper.send(:start_grok_tool_round, obj, [call("c2")])
    expect(obj["earlier_tool_rounds"].map { |calls, results| [calls.map { |c| c["id"] }, results.map { |r| r["call_id"] }] })
      .to eq([[["c1"], ["c1"]]])
    expect(obj["function_returns"]).to eq([])
  end
end
