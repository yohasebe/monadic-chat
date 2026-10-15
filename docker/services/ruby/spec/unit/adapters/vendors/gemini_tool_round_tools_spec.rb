# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/monadic/adapters/vendors/gemini_helper"

# A tool-result request offers only the tools the user turn offered: the
# conditional ones stay hidden until they are unlocked.
RSpec.describe "GeminiHelper tool-result rounds" do
  let(:helper) { Class.new { include GeminiHelper }.new }
  let(:declarations) do
    %w[run_task hidden_tool request_tool].map { |n| { "name" => n, "description" => n } }
  end
  let(:progressive) do
    {
      provider: :gemini,
      all_tool_names: %w[run_task hidden_tool request_tool],
      always_visible: %w[run_task request_tool],
      conditional: [
        { name: "hidden_tool", visibility: :conditional,
          unlock_conditions: [{ tool_request: "hidden_skill" }], unlock_hint: "use the hidden tool" }
      ]
    }
  end

  before do
    stub_const("CONFIG", {})
    settings = { tools: { "function_declarations" => declarations }, progressive_tools: progressive }
    stub_const("APPS", { "SpecGeminiApp" => double("app", settings: settings) })
  end

  def tool_round_names(session)
    body = { "tools" => [{ "function_declarations" => declarations }] }
    app_tools = helper.send(:configure_gemini_tools, app: "SpecGeminiApp", role: "tool", body: body, obj: {},
                                                     session: session, tool_capable: true, use_native_websearch: false)
    helper.send(:apply_tool_round_tools!, body, app_tools)
    Array(body.dig("tools", 0, "function_declarations")).map { |t| t["name"] }
  end

  it "leaves a locked conditional tool out of the follow-up request" do
    expect(tool_round_names({ parameters: {} })).to contain_exactly("run_task", "request_tool")
  end

  it "includes the tool once it is unlocked" do
    session = { parameters: {} }
    Monadic::Utils::ProgressiveToolManager.unlock_tool(session: session, app_name: "SpecGeminiApp", tool_name: "hidden_tool")
    expect(tool_round_names(session)).to include("hidden_tool")
  end

  it "does not add tools to a request that had none" do
    body = {}
    helper.send(:apply_tool_round_tools!, body, declarations)
    expect(body).not_to have_key("tools")
  end

  it "adds gemini_web_search on a tool round when web search is on, as a user turn does" do
    body = { "tools" => [{ "function_declarations" => declarations }] }
    app_tools = helper.send(:configure_gemini_tools, app: "SpecGeminiApp", role: "tool", body: body, obj: {},
                                                     session: { parameters: {} }, tool_capable: true, use_native_websearch: true)
    helper.send(:apply_tool_round_tools!, body, app_tools, true)
    names = Array(body.dig("tools", 0, "function_declarations")).map { |t| t["name"] }
    expect(names).to include("run_task", "gemini_web_search")
    expect(names).not_to include("hidden_tool")
  end

  it "keeps native entries when there are no declarations" do
    body = { "tools" => [{ "function_declarations" => declarations }, { "google_search" => {} }] }
    helper.send(:apply_tool_round_tools!, body, [], true)
    expect(body["tools"]).to eq([{ "google_search" => {} }])
  end

  it "drops native search entries when web search is off" do
    body = { "tools" => [{ "google_search" => {} }, { "url_context" => {} }], "toolConfig" => { "x" => 1 } }
    helper.send(:apply_tool_round_tools!, body, [], false)
    expect(body).not_to have_key("tools")
    expect(body).not_to have_key("toolConfig")
  end

  it "does not combine native google_search with declarations" do
    body = { "tools" => [{ "function_declarations" => declarations }, { "google_search" => {} }] }
    helper.send(:apply_tool_round_tools!, body, [{ "name" => "run_task" }], true)
    expect(body["tools"].size).to eq(1)
    expect(body["tools"][0].keys).to eq(["function_declarations"])
  end

  it "drops tools and toolConfig when nothing is left" do
    body = { "tools" => [{ "function_declarations" => declarations }], "toolConfig" => { "x" => 1 } }
    helper.send(:apply_tool_round_tools!, body, [])
    expect(body).not_to have_key("tools")
    expect(body).not_to have_key("toolConfig")
  end
end

# The same rule through api_request: the body of a tool-result request.
RSpec.describe "GeminiHelper#api_request tool-result body" do
  let(:helper) { Class.new { include GeminiHelper }.new }
  let(:declarations) { %w[run_task hidden_tool request_tool].map { |n| { "name" => n, "description" => n } } }

  before do
    stub_const("CONFIG", { "GEMINI_API_KEY" => "test-key" })
    progressive = {
      provider: :gemini, all_tool_names: %w[run_task hidden_tool request_tool],
      always_visible: %w[run_task request_tool],
      conditional: [{ name: "hidden_tool", visibility: :conditional,
                      unlock_conditions: [{ tool_request: "hidden_skill" }], unlock_hint: "use the hidden tool" }]
    }
    settings = { tools: { "function_declarations" => declarations }, progressive_tools: progressive }
    stub_const("APPS", { "SpecGeminiApp" => double("app", settings: settings, api_key: nil).as_null_object })
  end

  it "sends only the unlocked tools" do
    sent = nil
    allow(helper).to receive(:execute_gemini_api_call) { |**kw| sent = kw[:body]; raise "stop" }
    session = {
      parameters: {
        "app_name" => "SpecGeminiApp", "model" => "gemini-test", "context_size" => "5", "max_tokens" => "100",
        "tools" => { "function_declarations" => declarations }.to_json,
        "tool_results" => [{ "functionResponse" => { "name" => "run_task", "response" => { "content" => "done" } } }]
      },
      messages: [{ "role" => "user", "text" => "hi", "active" => true }]
    }
    begin
      helper.api_request("tool", session, call_depth: 1) { |_| }
    rescue StandardError
      nil
    end
    names = Array(sent && sent["tools"]).flat_map { |t| Array(t["function_declarations"]) }.map { |t| t["name"] }
    expect(sent).not_to be_nil
    expect(names).to include("run_task")
    expect(names).not_to include("hidden_tool")
  end
end
