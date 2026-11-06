# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/monadic/adapters/vendors/grok_helper"

# The prompt suffix goes on the user's message only. The request that
# returns a tool's results may end with a screenshot taken after them: that
# message keeps its own text, and the user's message is not written into it.
RSpec.describe "Grok prompt suffix and a screenshot after a tool" do
  let(:helper) { Class.new(MonadicApp) { include GrokHelper }.new }
  let(:suffix) { "Answer briefly." }
  let(:context) do
    [{ "role" => "system", "text" => "S" }, { "role" => "user", "text" => "Open the page" }]
  end

  def build(role, obj, session)
    helper.send(:build_grok_messages, context, role, obj, session, {}, nil, suffix, nil).first
  end

  it "adds the suffix to the user's message" do
    messages = build("user", { "model" => "grok-4" }, { messages: context })
    expect(messages.last["content"].first["text"]).to eq("Open the page\n\n#{suffix}")
  end

  it "leaves the screenshot's own text after a tool, and adds no suffix there" do
    allow(Monadic::Utils::ToolImageUtils).to receive(:encode_image_for_api)
      .and_return({ media_type: "image/png", base64_data: "AAAA" })
    obj = { "model" => "grok-4", "function_returns" => [{ "call_id" => "c1", "content" => "clicked" }] }
    session = { messages: context, pending_tool_images: ["shot.png"] }
    messages = build("tool", obj, session)
    shot = messages.last
    expect(shot["role"]).to eq("user")
    expect(shot["content"].first["text"]).to start_with("[Screenshot of the browser")
    expect(JSON.generate(messages)).not_to include(suffix)
  end
end
