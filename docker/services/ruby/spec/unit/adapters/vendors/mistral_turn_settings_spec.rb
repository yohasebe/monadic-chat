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

  def bodies(message, kept: {}, change: {})
    turn_bodies(MistralHelper, format: StreamContract::ChatCompletions, kind: :sse, key: "MISTRAL_API_KEY",
                message: { "model" => model, "context_size" => "5" }.merge(message), kept: kept, change: change)
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

  it "offers the search tools as they are in an app that unlocks its tools on request" do
    stub_const("CONFIG", CONFIG.to_h.merge("TAVILY_API_KEY" => "k"))
    progressive = Class.new(TurnSettingsTurn::ChangingApp) do
      def settings
        request_tool = { "type" => "function",
                         "function" => { "name" => "request_tool", "description" => "t",
                                         "parameters" => { "type" => "object", "properties" => {} } } }
        { "tools" => [TurnSettingsTurn::TOOL, request_tool],
          "progressive_tools" => { all_tool_names: %w[first_tool request_tool], always_visible: %w[first_tool request_tool],
                                   conditional: [] } }
      end
    end
    stub_const("TurnSettingsTurn::ChangingApp", progressive)
    names = ->(message) { bodies(message).first["tools"].map { |t| t.dig("function", "name") } }
    expect(names.call({ "websearch" => true })).to include("first_tool", "tavily_search")
    expect(names.call({ "websearch" => false })).not_to include("tavily_search")
  end
end
