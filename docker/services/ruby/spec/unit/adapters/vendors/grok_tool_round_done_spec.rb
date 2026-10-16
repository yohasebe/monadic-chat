# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/monadic/adapters/vendors/grok_helper"

# A non-streaming Grok reply that calls tools ends with DONE "tool_calls", so
# the browser keeps its "processing tools" state until the final answer.
RSpec.describe "Grok non-streaming reply with tool calls" do
  def run_with(output)
    model = Monadic::Utils::ModelSpec.get_provider_models("xai", "chat")&.first
    tools = [{ "type" => "function", "function" => { "name" => "some_tool", "description" => "d",
                                                     "parameters" => { "type" => "object", "properties" => {} } } }]
    app = Struct.new(:settings).new({ "tools" => tools, tools: tools })
    stub_const("APPS", { "SpecApp" => app })
    stub_const("CONFIG", { "XAI_API_KEY" => "k" })
    h = Class.new(MonadicApp) { include GrokHelper }.new
    res = double("res", status: HTTP::Response::Status.new(200), body: JSON.generate("output" => output))
    allow(h).to receive(:post_json_with_retries).and_return(res)
    allow(h).to receive(:process_functions).and_return([])
    s = { parameters: { "app_name" => "SpecApp", "model" => model, "context_size" => "5", "max_tokens" => "100",
                        "message" => "hi", "temperature" => "0.5", "tools" => tools.to_json },
          messages: [{ "role" => "system", "text" => "S", "active" => true }] }
    sent = []
    h.api_request("user", s, disable_streaming: true) { |r| sent << r }
    sent.select { |r| r["type"] == "message" && r["content"] == "DONE" }.map { |r| r["finish_reason"] }
  end

  it "ends a reply that calls a tool with DONE tool_calls" do
    output = [{ "type" => "function_call", "call_id" => "c1", "name" => "some_tool", "arguments" => "{}" }]
    expect(run_with(output)).to eq(["tool_calls"])
  end

  it "ends a reply without tool calls with DONE stop" do
    output = [{ "type" => "message", "content" => [{ "type" => "output_text", "text" => "hello" }] }]
    expect(run_with(output)).to eq(["stop"])
  end
end
