# frozen_string_literal: true

require "spec_helper"
require_relative "../../../support/turn_settings_turn"
require_relative "../../../../lib/monadic/adapters/vendors/mistral_helper"

# A Mistral turn is sent with the settings of its message: in every request
# of the turn, whatever the chat's kept parameters say meanwhile.
RSpec.describe "The settings of a Mistral turn" do
  include TurnSettingsTurn

  # A model that takes levels of effort, and its lowest and highest.
  let(:model) do
    Monadic::Utils::ModelSpec.get_provider_models("mistral", "chat").find do |m|
      levels(m).size > 1
    end
  end
  let(:helper) { Class.new { include MistralHelper }.new }

  def levels(name)
    Array(Monadic::Utils::ModelSpec.get_reasoning_effort_options(name)&.dig(:options)).map(&:to_s) - ["none"]
  end

  # keep: gives back the chat's messages after the turn; session: a chat's
  # messages to go on from.
  def bodies(message, kept: {}, change: {}, keep: false, session: nil)
    sent = turn_bodies(MistralHelper, format: StreamContract::ChatCompletions, kind: :sse, key: "MISTRAL_API_KEY",
                       message: { "model" => model, "context_size" => "5" }.merge(message), kept: kept, change: change,
                       messages: session)
    keep ? @turn_messages : sent
  end

  it "keeps the message's settings in the request that sends the tool's result back" do
    highest = helper.mistral_effort_for(model, levels(model).last)
    sent = bodies({ "reasoning_effort" => levels(model).last, "max_tokens" => "300" },
                  change: { "reasoning_effort" => "none", "max_tokens" => "9000", "model" => "another-model" })
    expect(sent.size).to eq(2)
    sent.each do |body|
      expect(body.slice("model", "reasoning_effort", "max_tokens")).to eq(
        "model" => model, "reasoning_effort" => highest, "max_tokens" => 300
      )
    end
  end

  it "does not take an effort or an output limit the message leaves out from an earlier message" do
    unasked = helper.mistral_effort_for(model, nil)
    sent = bodies({ "temperature" => "0.4" }, kept: { "reasoning_effort" => levels(model).last, "max_tokens" => "9000" })
    sent.each do |body|
      expect(body["reasoning_effort"]).to eq(unasked)
      expect(body["max_tokens"]).to eq(4096)
    end
  end

  it "sends no output limit of zero" do
    bodies({ "max_tokens" => "0" }).each { |body| expect(body["max_tokens"]).to eq(4096) }
  end

  def offered(body)
    Array(body["tools"]).map { |t| t.dig("function", "name") }
  end

  it "offers web search in every request of a message sent with it, and in none of one sent without" do
    searching = ->(message, change) { bodies(message, change: change).map { |b| offered(b).include?("mistral_web_search") } }
    expect(searching.call({ "websearch" => true }, { "websearch" => false })).to eq([true, true])
    expect(searching.call({ "websearch" => false }, { "websearch" => true })).to eq([false, false])
    expect(searching.call({}, { "websearch" => true })).to eq([false, false])
  end

  it "searches through Mistral's own tool, with or without a Tavily key, and offers no Tavily tool" do
    [nil, "tavily-key"].each do |tavily|
      allow(CONFIG).to receive(:[]).and_call_original
      allow(CONFIG).to receive(:[]).with("TAVILY_API_KEY").and_return(tavily)
      sent = bodies({ "websearch" => true })
      expect(sent).not_to be_empty
      sent.each do |body|
        expect(offered(body)).to include("mistral_web_search")
        expect(offered(body)).not_to include("tavily_search", "tavily_fetch")
        expect(body.dig("messages", 0, "content")).to include(Monadic::SharedTools::MistralSearch::PROMPT.strip)
        expect(JSON.generate(body)).not_to include("tavily")
      end
    end
  end

  it "does not offer the Tavily tools an app or a request names" do
    stub_const("CONFIG", CONFIG.to_h.merge("TAVILY_API_KEY" => "tavily-key"))
    tavily_tools = JSON.parse(JSON.generate(Monadic::SharedTools::TavilyDefinitions::TOOLS))
    allow_any_instance_of(TurnSettingsTurn::ChangingApp).to receive(:settings)
      .and_return({ "tools" => [TurnSettingsTurn::TOOL] + tavily_tools })
    [true, false].each do |websearch|
      bodies({ "websearch" => websearch, "tools" => [TurnSettingsTurn::TOOL] + tavily_tools }).each do |body|
        expect(offered(body)).to include("first_tool")
        expect(offered(body).include?("mistral_web_search")).to be(websearch)
        expect(offered(body)).not_to include("tavily_search", "tavily_fetch")
      end
    end
  end

  it "sends nothing to Tavily when the model calls tavily_search, though a Tavily key is set" do
    stub_const("CONFIG", CONFIG.to_h.merge("TAVILY_API_KEY" => "tavily-key"))
    format = StreamContract::ChatCompletions
    sent = turn_bodies(MistralHelper, format: format, kind: :sse, key: "MISTRAL_API_KEY",
                       message: { "model" => model, "context_size" => "5", "websearch" => true },
                       answers: [format.calls([["tavily_search", { "query" => "news" }]]), format.text(["Done."])])
    expect(@turn_uris).not_to be_empty
    expect(@turn_uris.grep(/tavily/)).to be_empty
    tool_result = sent.last["messages"].find { |m| m["role"] == "tool" }
    expect(tool_result["content"]).to start_with("❌")
  end

  it "does not give the search tool to a model the catalog says takes no tools" do
    allow(Monadic::Utils::ModelSpec).to receive(:get_model_property).and_call_original
    allow(Monadic::Utils::ModelSpec).to receive(:get_model_property).with(model, "tool_capability").and_return(false)
    sent = bodies({ "websearch" => true })
    expect(sent).not_to be_empty
    expect(JSON.generate(sent.first)).not_to include("mistral_web_search")
  end

  describe "in an app that unlocks its tools on request" do
    # The app's tools: first_tool and request_tool, and with tavily the
    # Tavily tools too, shown only once asked for.
    def progressive_app(tavily: false)
      search = tavily ? JSON.parse(JSON.generate(Monadic::SharedTools::TavilyDefinitions::TOOLS)) : []
      names = %w[first_tool request_tool] + search.map { |t| t.dig("function", "name") }
      conditional = search.map { |t| { name: t.dig("function", "name"), unlock_conditions: [] } }
      Class.new(TurnSettingsTurn::ChangingApp) do
        define_method(:settings) do
          request_tool = { "type" => "function",
                           "function" => { "name" => "request_tool", "description" => "t",
                                           "parameters" => { "type" => "object", "properties" => {} } } }
          { "tools" => [TurnSettingsTurn::TOOL, request_tool] + search,
            "progressive_tools" => { all_tool_names: names, always_visible: %w[first_tool request_tool],
                                     conditional: conditional } }
        end
      end
    end

    def names_of(body) = Array(body["tools"]).map { |t| t.dig("function", "name") }

    def told?(body) = body["messages"].first["content"].include?(MistralHelper::WEBSEARCH_PROMPT)

    it "offers the search tool as it is, and tells the model of it, in both requests" do
      stub_const("TurnSettingsTurn::ChangingApp", progressive_app)
      sent = bodies({ "websearch" => true })
      expect(sent.map { |b| names_of(b).include?("mistral_web_search") }).to eq([true, true])
      expect(sent.map { |b| told?(b) }).to eq([true, true])
    end

    it "neither offers it nor tells of it with Web Search off, also after a message sent with it on" do
      stub_const("TurnSettingsTurn::ChangingApp", progressive_app)
      history = bodies({ "websearch" => true }, keep: true)
      sent = bodies({ "websearch" => false }, session: history)
      expect(sent).not_to be_empty
      sent.each do |body|
        expect(names_of(body)).not_to include("mistral_web_search")
        expect(told?(body)).to be(false)
      end
    end

    it "offers Mistral's search tool, not the Tavily tools, in an app that imports them" do
      stub_const("CONFIG", CONFIG.to_h.merge("TAVILY_API_KEY" => "tavily-key"))
      stub_const("TurnSettingsTurn::ChangingApp", progressive_app(tavily: true))
      names = names_of(bodies({ "websearch" => true }).first)
      expect(names).to include("mistral_web_search")
      expect(names).not_to include("tavily_search", "tavily_fetch")
    end
  end

  describe "running a web search call" do
    let(:helper) { Class.new(MonadicApp) { include MistralHelper }.new }
    let(:posted) { [] }

    before do
      stub_const("CONFIG", CONFIG.to_h.merge("MISTRAL_API_KEY" => "ms-key", "TAVILY_API_KEY" => "tavily-key"))
      stub_const("APPS", { "SpecApp" => helper })
      helper.settings = { "tools" => [] }
      chain = double("http")
      %i[timeout headers].each { |m| allow(chain).to receive(m).and_return(chain) }
      allow(HTTP).to receive(:timeout).and_return(chain)
      allow(HTTP).to receive(:headers).and_return(chain)
      allow(chain).to receive(:post) do |url, json:|
        posted << [url.to_s, json]
        reply = { "outputs" => [{ "type" => "tool.execution", "name" => "web_search" },
                                { "type" => "message.output", "content" => "Found it." }] }
        double("res", status: HTTP::Response::Status.new(200), body: double(to_s: JSON.generate(reply)))
      end
    end

    # The result of a call of name, when every web search tool was offered
    # (so what is asked is the helper's own gate).
    def run(name, args, websearch:)
      session = { parameters: { "app_name" => "SpecApp", "model" => model, "websearch" => websearch }, messages: [] }
      Monadic::Utils::ToolDispatchGuard.record!(
        session, "SpecApp", MistralHelper::WEBSEARCH_TOOLS + Monadic::SharedTools::TavilyDefinitions::TOOLS +
                            [{ "type" => "function", "function" => { "name" => "search_web" } }]
      )
      call = { "id" => "call_1", "function" => { "name" => name, "arguments" => JSON.generate(args) } }
      entry, = helper.send(:invoke_mistral_tool_function, "SpecApp", session, call, name) { |_| }
      entry[:content]
    end

    it "runs mistral_web_search on Mistral's Conversations API when the message may search" do
      content = run("mistral_web_search", { "query" => "news" }, websearch: true)
      expect(posted.map(&:first)).to eq([Monadic::SharedTools::MistralSearch::ENDPOINT])
      expect(JSON.parse(content)).to include("answer" => "Found it.", "websearch_agent" => "mistral")
    end

    it "refuses a Tavily call when the message may search, and sends nothing" do
      %w[tavily_search tavily_fetch].each do |name|
        args = name == "tavily_search" ? { "query" => "news" } : { "url" => "https://example.com/" }
        expect(run(name, args, websearch: true)).to include("is not available in this conversation")
      end
      expect(posted).to be_empty
    end

    it "refuses every web search call when the message may not search, and sends nothing" do
      { "mistral_web_search" => { "query" => "news" }, "search_web" => { "query" => "news" },
        "tavily_search" => { "query" => "news" }, "tavily_fetch" => { "url" => "https://example.com/" } }.each do |name, args|
        expect(run(name, args, websearch: false)).to include("Web search is turned off")
      end
      expect(posted).to be_empty
    end

    it "refuses every web search call when the setting turns web search off" do
      stub_const("CONFIG", CONFIG.to_h.merge("WEB_SEARCH_IN_CHATS" => "false"))
      expect(run("mistral_web_search", { "query" => "news" }, websearch: true)).to include("Web search is turned off")
      expect(posted).to be_empty
    end
  end
end
