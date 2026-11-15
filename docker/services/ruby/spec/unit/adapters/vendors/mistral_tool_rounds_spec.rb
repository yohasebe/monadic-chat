# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/monadic/adapters/vendors/mistral_helper"

# A turn that calls tools more than once: every round of the turn goes back
# with the next request, in order.
RSpec.describe "Mistral tool rounds of a turn" do
  let(:helper) do
    Class.new { include MistralHelper }.new.tap do |h|
      allow(h).to receive(:with_workbench_looks) { |returns, *_rest, **_kw| returns }
    end
  end

  def calls(id)
    { "role" => "assistant", "content" => "", "tool_calls" => [{ "id" => id, "type" => "function", "function" => { "name" => "t", "arguments" => "{}" } }] }
  end

  it "sends the earlier rounds before the latest one" do
    obj = { "earlier_tool_rounds" => [[calls("c1"), [{ role: "tool", content: "one", tool_call_id: "c1", name: "t" }]]],
            "tool_calls_message" => calls("c2"),
            "function_returns" => [{ role: "tool", content: "two", tool_call_id: "c2", name: "t" }] }
    body = { "messages" => [{ "role" => "system", "content" => "S" }, { "role" => "user", "content" => "Go" }] }
    helper.send(:build_mistral_messages, body, [], obj, { messages: [], parameters: obj }, "tool")
    tail = body["messages"].last(4)
    expect(tail.map { |m| [m["role"], m["tool_call_id"] || m["tool_calls"].first["id"], m["content"]] })
      .to eq([["assistant", "c1", ""], %w[tool c1 one], ["assistant", "c2", ""], %w[tool c2 two]])
  end
end
