# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/monadic/adapters/vendors/deepseek_helper"

# DeepSeek builds its system message through SystemPromptInjector like the
# other providers, so session rules (language, suffixes, ...) reach it.
RSpec.describe DeepSeekHelper do
  let(:app_helper) { Class.new(MonadicApp) { include DeepSeekHelper }.new }

  before do
    stub_const("APPS", { "SpecApp" => Struct.new(:settings).new({}) })
    stub_const("CONFIG", { "DEEPSEEK_API_KEY" => "test-key" })
  end

  def sent_system_prompt(parameters)
    body = nil
    allow(app_helper).to receive(:post_json_with_retries) do |_http, _uri, b, **|
      body = b
      raise "stop"
    end
    session = {
      parameters: { "app_name" => "SpecApp", "model" => "deepseek-chat", "context_size" => "5",
                    "max_tokens" => "100", "message" => "hi" }.merge(parameters),
      messages: [{ "role" => "system", "text" => "BASE PROMPT", "active" => true }]
    }
    begin
      app_helper.api_request("user", session) { |_| }
    rescue StandardError
      nil
    end
    body && body["messages"].find { |m| m["role"] == "system" }&.dig("content")
  end

  it "passes the system prompt through SystemPromptInjector" do
    expect(Monadic::Utils::SystemPromptInjector).to receive(:augment)
      .with(hash_including(base_prompt: "BASE PROMPT")).and_call_original
    expect(sent_system_prompt({})).to start_with("BASE PROMPT")
  end

  it "includes the app's system_prompt_suffix" do
    expect(sent_system_prompt({ "system_prompt_suffix" => "SUFFIX RULE" })).to include("SUFFIX RULE")
  end
end
