# frozen_string_literal: true

require "spec_helper"
require_relative "../../../support/turn_settings_turn"
require_relative "../../../../lib/monadic/adapters/vendors/deepseek_helper"

# A DeepSeek turn is sent with the settings of its message: in every request
# of the turn, whatever the chat's kept parameters say meanwhile.
RSpec.describe "The settings of a DeepSeek turn" do
  include TurnSettingsTurn

  # A model whose thinking can be switched, and a level of effort it takes.
  let(:model) do
    Monadic::Utils::ModelSpec.get_provider_models("deepseek", "chat").find do |m|
      Array(Monadic::Utils::ModelSpec.get_model_property(m, "reasoning_content")).map(&:to_s).include?("enabled")
    end
  end
  let(:effort) do
    (Array(Monadic::Utils::ModelSpec.get_reasoning_effort_options(model)&.dig(:options)).map(&:to_s) - ["none"]).last
  end

  def bodies(message, kept: {}, change: {})
    turn_bodies(DeepSeekHelper, format: StreamContract::ChatCompletions, kind: :sse, key: "DEEPSEEK_API_KEY",
                message: { "model" => model, "context_size" => "5" }.merge(message), kept: kept, change: change)
  end

  it "keeps the message's settings in the request that sends the tool's result back" do
    sent = bodies({ "reasoning_effort" => effort, "max_tokens" => "300" },
                  change: { "reasoning_effort" => "none", "max_tokens" => "9000", "model" => "another-model" })
    expect(sent.size).to eq(2)
    sent.each do |body|
      expect(body.slice("model", "thinking", "reasoning_effort", "max_tokens")).to eq(
        { "model" => model, "thinking" => { "type" => "enabled" }, "reasoning_effort" => effort, "max_tokens" => 300 }.compact
      )
    end
  end

  it "keeps thinking off through a turn sent with it off, and on through one sent with it on" do
    off = bodies({ "reasoning_content" => "disabled" }, change: { "reasoning_content" => "enabled" })
    expect(off.map { |body| body.dig("thinking", "type") }).to eq(%w[disabled disabled])
    on = bodies({}, change: { "reasoning_effort" => "none" })
    expect(on.map { |body| body.dig("thinking", "type") }).to eq(%w[enabled enabled])
  end

  it "does not take thinking off, an effort or an output limit from an earlier message" do
    sent = bodies({}, kept: { "reasoning_effort" => "none", "reasoning_content" => "disabled", "max_tokens" => "9000" })
    sent.each do |body|
      expect(body.dig("thinking", "type")).to eq("enabled")
      expect(body.keys).not_to include("reasoning_effort", "max_tokens")
    end
  end

  it "sends no output limit of zero" do
    bodies({ "max_tokens" => "0" }).each { |body| expect(body).not_to have_key("max_tokens") }
  end

  def offered(body)
    Array(body["tools"]).map { |t| t.dig("function", "name") }
  end

  it "offers web search in every request of a message sent with it, and in none of one sent without" do
    searching = ->(message, change) { bodies(message, change: change).map { |b| offered(b).include?("deepseek_search") } }
    expect(searching.call({ "websearch" => true }, { "websearch" => false })).to eq([true, true])
    expect(searching.call({ "websearch" => false }, { "websearch" => true })).to eq([false, false])
    expect(searching.call({}, { "websearch" => true })).to eq([false, false])
  end

  it "searches through DeepSeek's own tools, with or without a Tavily key, and offers no Tavily tool" do
    [nil, "tavily-key"].each do |tavily|
      allow(CONFIG).to receive(:[]).and_call_original
      allow(CONFIG).to receive(:[]).with("TAVILY_API_KEY").and_return(tavily)
      sent = bodies({ "websearch" => true })
      expect(sent).not_to be_empty
      sent.each do |body|
        expect(offered(body)).to include("deepseek_search", "deepseek_fetch")
        expect(offered(body)).not_to include("tavily_search", "tavily_fetch")
        expect(body.dig("messages", 0, "content")).to include(Monadic::SharedTools::DeepSeekSearch::PROMPT.strip)
        expect(JSON.generate(body)).not_to include("tavily")
      end
    end
  end

  it "does not offer the Tavily tools an app imports" do
    stub_const("CONFIG", CONFIG.to_h.merge("TAVILY_API_KEY" => "tavily-key"))
    tavily_tools = JSON.parse(JSON.generate(Monadic::SharedTools::TavilyDefinitions::TOOLS))
    allow_any_instance_of(TurnSettingsTurn::ChangingApp).to receive(:settings)
      .and_return({ "tools" => [TurnSettingsTurn::TOOL] + tavily_tools })
    bodies({ "websearch" => true }).each do |body|
      expect(offered(body)).to include("first_tool", "deepseek_search")
      expect(offered(body)).not_to include("tavily_search", "tavily_fetch")
    end
  end

  it "sends nothing to Tavily when the model calls tavily_search, though a Tavily key is set" do
    stub_const("CONFIG", CONFIG.to_h.merge("TAVILY_API_KEY" => "tavily-key"))
    format = StreamContract::ChatCompletions
    sent = turn_bodies(DeepSeekHelper, format: format, kind: :sse, key: "DEEPSEEK_API_KEY",
                       message: { "model" => model, "context_size" => "5", "websearch" => true },
                       answers: [format.calls([["tavily_search", { "query" => "news" }]]), format.text(["Done."])])
    expect(@turn_uris).not_to be_empty
    expect(@turn_uris.grep(/tavily/)).to be_empty
    tool_result = sent.last["messages"].find { |m| m["role"] == "tool" }
    expect(tool_result["content"]).to start_with("❌")
  end

  it "takes a deepseek_search call written as JSON text as a call, and leaves a Tavily one as text" do
    format = StreamContract::ChatCompletions
    written = ->(name) { "```json\n{\"name\": \"#{name}\", \"arguments\": {\"query\": \"news\"}}\n```" }
    message = { "model" => model, "context_size" => "5", "websearch" => true }
    sent = turn_bodies(DeepSeekHelper, format: format, kind: :sse, key: "DEEPSEEK_API_KEY", message: message,
                       answers: [format.text([written.call("deepseek_search")]), format.text(["Done."])])
    expect(sent.size).to eq(2)
    expect(sent.last["messages"].map { |m| m["role"] }).to include("tool")
    sent = turn_bodies(DeepSeekHelper, format: format, kind: :sse, key: "DEEPSEEK_API_KEY", message: message,
                       answers: [format.text([written.call("tavily_search")])])
    expect(sent.size).to eq(1)
    expect(@turn_uris.grep(/tavily/)).to be_empty
  end

  it "does not give the search tools to a model the catalog says takes no tools" do
    allow(Monadic::Utils::ModelSpec).to receive(:get_model_property).and_call_original
    allow(Monadic::Utils::ModelSpec).to receive(:get_model_property).with(model, "tool_capability").and_return(false)
    sent = bodies({ "websearch" => true })
    expect(sent).not_to be_empty
    expect(JSON.generate(sent.first)).not_to include("deepseek_search")
  end

  describe "running a web search call" do
    let(:helper) { Class.new(MonadicApp) { include DeepSeekHelper }.new }
    let(:posted) { [] }

    before do
      stub_const("CONFIG", CONFIG.to_h.merge("DEEPSEEK_API_KEY" => "ds-key", "TAVILY_API_KEY" => "tavily-key"))
      stub_const("APPS", { "SpecApp" => helper })
      helper.settings = { "tools" => [] }
      chain = double("http")
      %i[timeout headers].each { |m| allow(chain).to receive(m).and_return(chain) }
      allow(HTTP).to receive(:timeout).and_return(chain)
      allow(HTTP).to receive(:headers).and_return(chain)
      allow(chain).to receive(:post) do |url, json:|
        posted << [url.to_s, json]
        reply = { "results" => [{ "title" => "T", "url" => "https://example.com/", "summary" => "S" }] }
        double("res", status: HTTP::Response::Status.new(200), body: double(to_s: JSON.generate(reply)))
      end
    end

    # The result of a call of name, when every web search tool was offered
    # (so what is asked is the helper's own gate).
    def run(name, args, websearch:)
      session = { parameters: { "app_name" => "SpecApp", "model" => model, "websearch" => websearch }, messages: [] }
      Monadic::Utils::ToolDispatchGuard.record!(
        session, "SpecApp", DeepSeekHelper::WEBSEARCH_TOOLS + Monadic::SharedTools::TavilyDefinitions::TOOLS
      )
      call = { "id" => "call_1", "function" => { "name" => name, "arguments" => JSON.generate(args) } }
      entry, = helper.send(:invoke_deepseek_tool_function, "SpecApp", session, call, name) { |_| }
      entry["content"]
    end

    it "runs deepseek_search on DeepSeek's Search API when the message may search" do
      content = run("deepseek_search", { "query" => "news" }, websearch: true)
      expect(posted.map(&:first)).to eq([Monadic::SharedTools::DeepSeekSearch::SEARCH_ENDPOINT])
      expect(JSON.parse(content)["websearch_agent"]).to eq("deepseek")
    end

    it "refuses a Tavily call when the message may search, and sends nothing" do
      %w[tavily_search tavily_fetch].each do |name|
        args = name == "tavily_search" ? { "query" => "news" } : { "url" => "https://example.com/" }
        expect(run(name, args, websearch: true)).to include("is not available in this conversation")
      end
      expect(posted).to be_empty
    end

    it "refuses every web search call when the message may not search, and sends nothing" do
      { "deepseek_search" => { "query" => "news" }, "deepseek_fetch" => { "url" => "https://example.com/" },
        "tavily_search" => { "query" => "news" }, "tavily_fetch" => { "url" => "https://example.com/" } }.each do |name, args|
        expect(run(name, args, websearch: false)).to include("Web search is turned off")
      end
      expect(posted).to be_empty
    end

    it "refuses every web search call when the setting turns web search off" do
      stub_const("CONFIG", CONFIG.to_h.merge("WEB_SEARCH_IN_CHATS" => "false"))
      expect(run("deepseek_search", { "query" => "news" }, websearch: true)).to include("Web search is turned off")
      expect(posted).to be_empty
    end
  end
end
