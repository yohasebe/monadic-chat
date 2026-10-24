# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/monadic/adapters/vendors/openai_helper"
require_relative "../../../../lib/monadic/adapters/vendors/grok_helper"

# When the model calls a tool first, its answer is written by the request that
# returns the tool results. That request carries the user's images too, or the
# answer says no image was attached.
RSpec.describe "Images in the request after tool calls" do
  let(:image) { { "title" => "photo.webp", "type" => "image/webp", "data" => "data:image/webp;base64,UklGRg==" } }
  let(:context) do
    [{ "role" => "system", "text" => "S" },
     { "role" => "user", "text" => "What is in this photo?", "images" => [image] },
     { "role" => "assistant", "text" => "" }]
  end

  def image_parts(messages)
    messages.flat_map { |m| Array(m["content"]) }.count { |c| c.is_a?(Hash) && c["type"] == "image_url" }
  end

  describe "OpenAI" do
    let(:helper) { Class.new(MonadicApp) { include OpenAIHelper }.new }

    def build(role)
      body = {}
      obj = { "model" => "gpt-6.1-sol", "function_returns" => [] }
      helper.send(:build_openai_messages, body, context, {}, obj, role,
                  false, [], true, false, nil, nil, nil, nil)
      body["messages"]
    end

    it "sends the user's image with the user's message" do
      expect(image_parts(build("user"))).to eq(1)
    end

    it "sends the user's image again with the tool results" do
      expect(image_parts(build("tool"))).to eq(1)
    end
  end

  describe "xAI Grok" do
    let(:helper) { Class.new(MonadicApp) { include GrokHelper }.new }

    def build(role)
      body = {}
      obj = { "model" => Monadic::Utils::ModelSpec.get_provider_models("xai", "chat")&.first, "function_returns" => [] }
      messages, _containing_image = helper.send(:build_grok_messages, context, role, obj, {}, body, nil, nil, nil)
      messages
    end

    it "sends the user's image with the user's message" do
      expect(image_parts(build("user"))).to eq(1)
    end

    it "sends the user's image again with the tool results" do
      expect(image_parts(build("tool"))).to eq(1)
    end
  end
end
