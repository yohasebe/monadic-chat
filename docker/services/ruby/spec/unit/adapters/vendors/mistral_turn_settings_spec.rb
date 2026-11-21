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

  it "offers web search in every request of a message sent with it, and in none of one sent without" do
    stub_const("CONFIG", CONFIG.to_h.merge("TAVILY_API_KEY" => "k"))
    searching = ->(message, change) { bodies(message, change: change).map { |b| JSON.generate(b["tools"]).include?("tavily_search") } }
    expect(searching.call({ "websearch" => true }, { "websearch" => false })).to eq([true, true])
    expect(searching.call({ "websearch" => false }, { "websearch" => true })).to eq([false, false])
    expect(searching.call({}, { "websearch" => true })).to eq([false, false])
  end

  describe "in an app that unlocks its tools on request" do
    # The app's tools: first_tool and request_tool, and with own_search the
    # search tools too, shown only once asked for.
    def progressive_app(own_search: false)
      search = own_search ? MistralHelper::WEBSEARCH_TOOLS : []
      names = %w[first_tool request_tool] + search.map { |t| t.dig("function", "name") || t.dig(:function, :name) }
      conditional = search.map { |t| { name: t.dig("function", "name") || t.dig(:function, :name), unlock_conditions: [] } }
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

    before { stub_const("CONFIG", CONFIG.to_h.merge("TAVILY_API_KEY" => "k")) }

    def names_of(body) = Array(body["tools"]).map { |t| t.dig("function", "name") }

    def told?(body) = body["messages"].first["content"].include?(MistralHelper::WEBSEARCH_PROMPT)

    it "offers the search tools as they are, and tells the model of them, in both requests" do
      stub_const("TurnSettingsTurn::ChangingApp", progressive_app)
      sent = bodies({ "websearch" => true })
      expect(sent.map { |b| names_of(b).include?("tavily_search") }).to eq([true, true])
      expect(sent.map { |b| told?(b) }).to eq([true, true])
    end

    it "neither offers them nor tells of them with Web Search off, also after a message sent with it on" do
      stub_const("TurnSettingsTurn::ChangingApp", progressive_app)
      history = bodies({ "websearch" => true }, keep: true)
      sent = bodies({ "websearch" => false }, session: history)
      expect(sent).not_to be_empty
      sent.each do |body|
        expect(names_of(body)).not_to include("tavily_search")
        expect(told?(body)).to be(false)
      end
    end

    it "leaves the search tools of an app that has its own to that app's way of showing them" do
      stub_const("TurnSettingsTurn::ChangingApp", progressive_app(own_search: true))
      expect(names_of(bodies({ "websearch" => true }).first)).not_to include("tavily_search")
    end
  end
end
