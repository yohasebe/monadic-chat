# frozen_string_literal: true

require "spec_helper"
require "active_support/core_ext/hash/indifferent_access"
require_relative "../../../../lib/monadic/adapters/vendors/openai_helper"

# The prompt suffix goes on the user's message. The request that returns tool
# results ends with the tool's result instead, whatever kind of Hash holds the
# parameters (the page sends a plain one; a headless caller may pass the app's
# HashWithIndifferentAccess settings).
RSpec.describe "OpenAI prompt suffix and tool results" do
  let(:helper) { Class.new(MonadicApp) { include OpenAIHelper }.new }
  let(:suffix) { "Answer in the language of the prompt." }
  let(:context) do
    [{ "role" => "system", "text" => "S" },
     { "role" => "user", "text" => "Read draft.txt" }]
  end
  let(:tool_returns) do
    [{ "role" => "assistant", "content" => nil, "tool_calls" => [{ "id" => "c1", "type" => "function",
                                                                   "function" => { "name" => "read", "arguments" => "{}" } }] },
     { tool_call_id: "c1", role: "tool", name: "read", content: "the draft text" }]
  end

  def build(role, obj)
    body = {}
    helper.send(:build_openai_messages, body, context, {}, obj, role,
                false, [], true, false, nil, nil, suffix, nil)
    body["messages"]
  end

  it "adds the suffix to the user's message" do
    messages = build("user", { "model" => "gpt-6.1-sol", "function_returns" => [] })
    expect(messages.last["content"].first["text"]).to include(suffix)
  end

  [["plain Hash", ->(h) { h }],
   ["HashWithIndifferentAccess", ->(h) { ActiveSupport::HashWithIndifferentAccess.new(h) }]].each do |kind, wrap|
    it "leaves the tool's result as it is with #{kind} parameters" do
      obj = wrap.call({ "model" => "gpt-6.1-sol", "function_returns" => tool_returns })
      messages = nil
      expect { messages = build("tool", obj) }.not_to raise_error
      expect(messages.last[:content] || messages.last["content"]).to eq("the draft text")
    end
  end
end

# The names of the images to edit go into what is sent with the user's
# message, with or without a suffix and with or without text, and never into
# the session's message.
RSpec.describe "OpenAI image references for image generation" do
  let(:helper) { Class.new(MonadicApp) { include OpenAIHelper }.new }

  def build(text, suffix)
    turn = { "role" => "user", "text" => text }
    context = [{ "role" => "system", "text" => "S" }, turn]
    body = {}
    helper.send(:build_openai_messages, body, context, {}, { "model" => "gpt-6.1-sol" }, "user",
                true, ["/data/img_1.png"], true, false, nil, nil, suffix, nil)
    [body["messages"].last["content"].first["text"], turn]
  end

  [["with text", "Make it blue", nil], ["with text and a suffix", "Make it blue", "Be brief."],
   ["with no text", "", nil]].each do |name, text, suffix|
    it "sends the references #{name}, leaving the session's message as it was" do
      sent, turn = build(+text, suffix)
      expect(sent).to include("Attached images:", "img_1.png")
      expect(sent).to start_with(text) unless text.empty?
      expect(sent).to include(suffix) if suffix
      expect(turn["text"]).to eq(text)
    end
  end
end
