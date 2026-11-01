# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/monadic/adapters/vendors/deepseek_helper"

# DeepSeek follows the same rules as the other providers: capabilities come
# from model_spec.js, the user message is recorded the same way, and an
# unknown tool name does not add a message to the conversation.
RSpec.describe DeepSeekHelper do
  let(:helper) { Class.new { include DeepSeekHelper }.new }
  let(:switch_model) { "spec-deepseek-thinker" }
  let(:plain_model) { "spec-deepseek-plain" }

  before do
    allow(Monadic::Utils::ModelSpec).to receive(:get_model_property).and_call_original
    allow(Monadic::Utils::ModelSpec).to receive(:get_model_property)
      .with(switch_model, "reasoning_content").and_return(%w[disabled enabled])
    allow(Monadic::Utils::ModelSpec).to receive(:get_model_property)
      .with(switch_model, "reasoning_effort").and_return(%w[high max])
    allow(Monadic::Utils::ModelSpec).to receive(:get_model_property)
      .with(plain_model, "reasoning_content").and_return(nil)
  end

  describe "#configure_deepseek_reasoning" do
    def configured(obj, is_json: false, role: "user")
      body = { "messages" => [] }
      helper.send(:configure_deepseek_reasoning, body, obj, is_json, role)
      body
    end

    it "turns thinking on with an effort the spec lists" do
      body = configured({ "model" => switch_model, "reasoning_effort" => "max" })
      expect(body["thinking"]).to eq({ "type" => "enabled", "reasoning_effort" => "max" })
    end

    it "leaves out an effort the spec does not list" do
      body = configured({ "model" => switch_model, "reasoning_effort" => "low" })
      expect(body["thinking"]).to eq({ "type" => "enabled" })
    end

    it "turns thinking off when reasoning_content is disabled" do
      body = configured({ "model" => switch_model, "reasoning_content" => "disabled", "reasoning_effort" => "max" })
      expect(body["thinking"]).to eq({ "type" => "disabled" })
    end

    it "sends no thinking setting for a model without the switch, by name or otherwise" do
      expect(configured({ "model" => plain_model })).not_to have_key("thinking")
      expect(configured({ "model" => "spec-reasoner-r1" })).not_to have_key("thinking")
    end

    it "asks for JSON on user turns of JSON apps, for every model" do
      expect(configured({ "model" => plain_model }, is_json: true)["response_format"]).to eq({ "type" => "json_object" })
      expect(configured({ "model" => switch_model }, is_json: true, role: "tool")).not_to have_key("response_format")
    end
  end

  describe "#api_request user message" do
    before do
      stub_const("APPS", { "SpecApp" => Struct.new(:settings).new({}) })
      stub_const("CONFIG", { "DEEPSEEK_API_KEY" => "test-key" })
      allow(app_helper).to receive(:post_json_with_retries).and_raise("stop")
    end

    let(:app_helper) { Class.new(MonadicApp) { include DeepSeekHelper }.new }

    it "records app_name and images like the other providers, and keeps the text as typed" do
      images = [{ "title" => "a.png", "data" => "data:image/png;base64,AAAA", "type" => "image/png" }]
      session = {
        parameters: { "app_name" => "SpecApp", "model" => plain_model, "context_size" => "5", "max_tokens" => "100",
                      "message" => "hello", "monadic" => "true", "images" => images },
        messages: [{ "role" => "system", "text" => "BASE", "active" => true }]
      }
      begin
        app_helper.api_request("user", session) { |_| }
      rescue StandardError
        nil
      end
      user = session[:messages].find { |m| m["role"] == "user" }
      expect(user["text"]).to eq("hello")
      expect(user["app_name"]).to eq("SpecApp")
      expect(user["images"]).to eq(images)
    end
  end

  describe "#validate_deepseek_dsml_tool_calls" do
    before do
      stub_const("APPS", { "SpecApp" => Struct.new(:settings).new({ "tools" => [{ "function" => { "name" => "known_tool" } }] }) })
      stub_const("CONFIG", {})
    end

    it "does not add a correction message to the conversation for an unknown name" do
      session = { parameters: { "app_name" => "SpecApp" }, messages: [] }
      text_result = { "choices" => [{ "message" => { "content" => "" } }] }
      calls = [{ "id" => "c1", "function" => { "name" => "made_up_tool", "arguments" => "{}" } }]
      tools = {}
      expect(helper).not_to receive(:api_request)
      helper.send(:validate_deepseek_dsml_tool_calls, calls, text_result, tools, {}, "SpecApp", session, 0)
      expect(session[:messages]).to be_empty
      expect(tools["c1"]).to eq(text_result)
    end
  end
end
