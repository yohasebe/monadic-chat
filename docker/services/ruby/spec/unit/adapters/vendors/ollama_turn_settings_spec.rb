# frozen_string_literal: true

require "spec_helper"
require "json"
require_relative "../../../support/stream_contract"
require_relative "../../../../lib/monadic/adapters/vendors/ollama_helper"

# An Ollama turn is sent with the settings of its message: in every request
# of the turn, whatever the chat's kept parameters say meanwhile.
RSpec.describe "The settings of an Ollama turn" do
  TOOL = { "type" => "function",
           "function" => { "name" => "first_tool", "description" => "t",
                           "parameters" => { "type" => "object", "properties" => {} } } }.freeze

  # The app whose tool changes the chat's kept parameters while the turn
  # runs, as a change made on the page would.
  class ChangingApp
    def initialize(session, change) = (@session, @change = session, change)

    def settings = { "tools" => [TOOL] }

    def first_tool(**)
      @session[:parameters].merge!(@change)
      "done"
    end
  end

  def lines(objects) = objects.map { |o| "#{JSON.generate(o)}\n" }.join

  # The bodies of the requests of one turn: the model calls the tool, then
  # answers. message: what the message brought; kept: the chat's parameters;
  # change: what the tool changes in them; capabilities: by model.
  def bodies_of_turn(message:, kept: {}, change: {}, capabilities: {}, history: [])
    helper = Class.new(MonadicApp) { include OllamaHelper }.new
    allow(helper).to receive(:sleep)
    session = { parameters: { "app_name" => "SpecApp", "message" => "What is the weather?", "tools" => [TOOL] }
                            .merge(kept).merge(message),
                messages: [{ "role" => "system", "text" => "S", "active" => true }] + history }
    stub_const("APPS", { "SpecApp" => ChangingApp.new(session, change) })
    allow(OllamaHelper).to receive(:find_endpoint).and_return("http://localhost:11434/api")
    allow(OllamaHelper).to receive(:fetch_model_capabilities) do |model|
      names = capabilities.fetch(model, %w[completion tools])
      names.is_a?(Array) ? { capabilities: names } : names
    end
    answers = [lines(StreamContract::Ollama.calls([["first_tool", {}]])), lines(StreamContract::Ollama.text(["Done."]))]
    bodies = []
    chain = double("http")
    %i[timeout headers].each { |m| allow(chain).to receive(m).and_return(chain) }
    allow(chain).to receive(:post) do |_uri, json:|
      bodies << JSON.parse(JSON.generate(json))
      answer = answers.length > 1 ? answers.shift : answers.first
      body = Object.new.tap { |o| o.define_singleton_method(:each) { |&blk| blk.call(answer.dup) } }
      double("res", status: HTTP::Response::Status.new(200), body: body)
    end
    allow(chain).to receive(:get) do
      names = (capabilities.keys + [message["model"], kept["model"], change["model"]]).compact.uniq
      double("res", status: HTTP::Response::Status.new(200), body: JSON.generate({ "models" => names.map { |n| { "name" => n } } }))
    end
    allow(HTTP).to receive(:headers).and_return(chain)
    allow(HTTP).to receive(:timeout).and_return(chain)
    chat = Monadic::Workspace::Ids.generate(:chat)
    session[Monadic::Workspace::Chats::SESSION_KEY] = chat
    context = Monadic::Workspace::RequestContext.new(chat_id: chat,
                                                     settings: Monadic::TurnSettings.accepted(message, kept))
    Monadic::Workspace::RequestContext.with(context) { helper.api_request("user", session) { |_| } }
    bodies
  end

  let(:thinker) { { "thinker" => %w[completion tools thinking], "other" => %w[completion tools thinking] } }

  it "keeps the message's settings in the request that sends the tool's result back" do
    bodies = bodies_of_turn(
      message: { "model" => "thinker", "show_thinking" => false, "temperature" => "0.2", "max_tokens" => "300" },
      change: { "model" => "other", "show_thinking" => true, "temperature" => "1.4", "max_tokens" => "9000" },
      capabilities: thinker
    )
    expect(bodies.size).to eq(2)
    bodies.each do |body|
      expect(body.slice("model", "think", "options")).to eq(
        "model" => "thinker", "think" => false, "options" => { "temperature" => 0.2, "num_predict" => 300 }
      )
    end
  end

  it "does not take a setting the message leaves out from an earlier message of the chat" do
    bodies = bodies_of_turn(message: { "model" => "thinker" },
                            kept: { "show_thinking" => true, "max_tokens" => "9000" }, capabilities: thinker)
    bodies.each do |body|
      expect(body["think"]).to be(false)
      expect(body["options"]).not_to have_key("num_predict")
    end
  end

  it "sends the question of a message that names no model or history size, with the chat's" do
    bodies = bodies_of_turn(message: { "temperature" => "0.4" }, kept: { "model" => "thinker", "context_size" => "5" },
                            capabilities: thinker)
    expect(bodies.size).to eq(2)
    bodies.each do |body|
      expect(body["model"]).to eq("thinker")
      expect(body["messages"].map { |m| m["content"].to_s }.join).to include("What is the weather?")
    end
  end

  it "offers web search in every request of a message sent with it, and in none of one sent without" do
    stub_const("CONFIG", CONFIG.to_h.merge("TAVILY_API_KEY" => "k"))
    searching = lambda do |message, change|
      bodies_of_turn(message: { "model" => "thinker", "context_size" => "5" }.merge(message), change: change,
                     capabilities: thinker)
        .map { |body| JSON.generate(body["tools"]).include?("tavily_search") }
    end
    expect(searching.call({ "websearch" => true }, { "websearch" => false })).to eq([true, true])
    expect(searching.call({ "websearch" => false }, { "websearch" => true })).to eq([false, false])
    expect(searching.call({}, { "websearch" => true })).to eq([false, false])
  end

  describe "the images of the chat's messages" do
    let(:history) do
      [{ "role" => "user", "text" => "Look.", "active" => true,
         "images" => [{ "data" => "data:image/png;base64,iVBORw0KGgo=", "type" => "image/png", "title" => "a.png" }] },
       { "role" => "assistant", "text" => "Seen.", "active" => true }]
    end

    def images_sent(model)
      bodies = bodies_of_turn(message: { "model" => model, "context_size" => "10" }, history: history,
                              capabilities: { "seeing" => %w[completion tools vision], "blind" => %w[completion tools] })
      expect(bodies.size).to eq(2)
      bodies.map { |body| body["messages"].count { |m| m["images"] } }
    end

    it "go to a model that takes images, in both requests" do
      expect(images_sent("seeing")).to eq([1, 1])
    end

    it "do not go to a model that takes none, while their messages' text does" do
      expect(images_sent("blind")).to eq([0, 0])
      bodies = bodies_of_turn(message: { "model" => "blind", "context_size" => "10" }, history: history,
                              capabilities: { "blind" => %w[completion tools] })
      expect(bodies.map { |body| body["messages"].any? { |m| m["content"].to_s.include?("Look.") } }).to eq([true, true])
    end

    it "go to a model the local server could not be asked about, or reports no capabilities of" do
      [nil, { capabilities: [], reported: false }].each do |answer|
        bodies = bodies_of_turn(message: { "model" => "unasked", "context_size" => "10" }, history: history,
                                capabilities: { "unasked" => answer })
        expect(bodies.map { |body| body["messages"].count { |m| m["images"] } }).to eq([1, 1]), answer.inspect
      end
    end

    it "reports that a server's answer names no capabilities" do
      allow(OllamaHelper).to receive(:fetch_model_capabilities).and_call_original
      allow(OllamaHelper).to receive(:find_endpoint).and_return("http://localhost:11434/api")
      client = double("http")
      allow(HTTP).to receive(:timeout).and_return(client)
      allow(client).to receive(:post).and_return(
        double("res", status: HTTP::Response::Status.new(200), body: JSON.generate({ "model_info" => {} })),
        double("res", status: HTTP::Response::Status.new(200), body: JSON.generate({ "capabilities" => ["completion"] }))
      )
      expect(OllamaHelper.fetch_model_capabilities("silent-spec-model")).to include(capabilities: [], reported: false)
      expect(OllamaHelper.fetch_model_capabilities("plain-spec-model")).to include(capabilities: ["completion"], reported: true)
    end
  end
end
