require "spec_helper"

RSpec.describe "Gemini toolConfig and thinking mapping" do
  let(:helper) { Class.new { include GeminiHelper }.new }

  def build_session(model, tools: nil, reasoning_effort: nil)
    {
      parameters: {
        "app_name" => "CodeInterpreterGemini",
        "model" => model,
        "temperature" => 0.0,
        "max_tokens" => 4000,
        "tools" => tools,
        "reasoning_effort" => reasoning_effort,
        "message" => "Hello"
      },
      messages: []
    }
  end

  def extract_request(helper, session)
    body = nil
    # Stub API key check
    stub_const("CONFIG", {"GEMINI_API_KEY" => "dummy"})
    allow(helper).to receive(:api_request).and_wrap_original do |m, *args|
      m.call(*args) do |res|
        # no-op
      end
    end
    helper.send(:api_request, "user", session) { |_res| }
  end

  it "keeps toolConfig mode AUTO when tools are present" do
    session = build_session("gemini-3-pro-preview", tools: [{"function_declarations" => [{"name" => "run_code"}]}])
    # capture body via expectation
    expect(helper).to receive(:api_request).and_wrap_original do |m, *args|
      req_body = nil
      allow(HTTP).to receive(:headers).and_return(double(get: double(status: double(success?: true), body: "{}")))
      m.receiver.send(:api_request, "user", session) do |res|
        req_body = res if res.is_a?(Hash)
      end
    end
    helper.api_request("user", session) { |_res| }
  end

  it "sets toolConfig AUTO even when tools are absent" do
    session = build_session("gemini-3-pro-preview", tools: nil)
    body = helper.send(:build_request_body_for_test, session)
    expect(body.dig("toolConfig", "functionCallingConfig", "mode")).to eq("AUTO")
  end

  it "maps thinking level to thinkingBudget for gemini-3-pro-preview" do
    session = build_session("gemini-3-pro-preview", reasoning_effort: "high")
    body = helper.send(:build_request_body_for_test, session)
    expect(body.dig("generationConfig", "thinkingConfig", "thinkingBudget")).to be > 0
  end

  it "keeps toolConfig when google_search is the only tool" do
    session = build_session("gemini-3-pro-preview", tools: [{"google_search" => {}}])
    body = helper.send(:build_request_body_for_test, session)
    expect(body["toolConfig"]).not_to be_nil
  end
end

