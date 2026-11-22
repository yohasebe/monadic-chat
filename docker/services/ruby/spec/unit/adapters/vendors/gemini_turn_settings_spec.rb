# frozen_string_literal: true

require "spec_helper"
require_relative "../../../support/turn_settings_turn"
require_relative "../../../../lib/monadic/adapters/vendors/gemini_helper"

# A Gemini turn is sent with the settings of its message: in every request
# of the turn, whatever the chat's kept parameters say meanwhile.
RSpec.describe "The settings of a Gemini turn" do
  include TurnSettingsTurn

  let(:models) { Monadic::Utils::ModelSpec.get_provider_models("gemini", "chat") }
  let(:model) { models.find { |m| Monadic::Utils::ModelSpec.get_thinking_level_options(m) } }
  let(:helper) { Class.new { include GeminiHelper }.new }

  def bodies(message, kept: {}, change: {})
    turn_bodies(GeminiHelper, format: StreamContract::Gemini, kind: :sse, key: "GEMINI_API_KEY",
                message: { "model" => model, "context_size" => "5" }.merge(message), kept: kept, change: change)
  end

  def thinking(body) = body.dig("generationConfig", "thinkingConfig")

  it "keeps the message's settings in the request that sends the tool's result back" do
    first = bodies({ "reasoning_effort" => "high", "show_thinking" => false, "max_tokens" => "300" })
    sent = bodies({ "reasoning_effort" => "high", "show_thinking" => false, "max_tokens" => "300" },
                  change: { "reasoning_effort" => "low", "show_thinking" => true, "max_tokens" => "9000",
                            "model" => models.find { |m| m != model } })
    expect(sent.size).to eq(2)
    expect(@turn_uris).to all(include("/models/#{model}:"))
    sent.each do |body|
      expect(thinking(body)).to eq(thinking(first.first))
      expect(thinking(body)["includeThoughts"]).to be(false)
      expect(body.dig("generationConfig", "maxOutputTokens")).to eq(300)
    end
  end

  it "does not take hidden thinking, an effort or an output limit from an earlier message" do
    unasked = bodies({})
    sent = bodies({}, kept: { "show_thinking" => false, "reasoning_effort" => "high", "max_tokens" => "9000" })
    sent.each do |body|
      expect(thinking(body)).to eq(thinking(unasked.first))
      expect(thinking(body)["includeThoughts"]).to be(true)
      expect(body["generationConfig"]).not_to have_key("maxOutputTokens")
    end
  end

  it "sends no output limit of zero" do
    bodies({ "max_tokens" => "0" }).each { |body| expect(body["generationConfig"]).not_to have_key("maxOutputTokens") }
  end

  it "does not ask a model to think that the catalog gives neither levels nor a budget" do
    allow(Monadic::Utils::ModelSpec).to receive(:get_thinking_level_options).and_return(nil)
    allow(Monadic::Utils::ModelSpec).to receive(:get_thinking_budget).and_return(nil)
    %w[high low none].each do |effort|
      bodies({ "reasoning_effort" => effort }).each { |body| expect(thinking(body)).to be_nil, effort }
    end
  end

  it "asks a model with a budget and no levels to think by the effort the message names" do
    allow(Monadic::Utils::ModelSpec).to receive(:get_thinking_level_options).and_return(nil)
    allow(Monadic::Utils::ModelSpec).to receive(:get_thinking_budget)
      .and_return({ "min" => 128, "max" => 32_768, "can_disable" => false, "presets" => { "high" => 24_000 } })
    bodies({ "reasoning_effort" => "high" }).each { |body| expect(thinking(body)).to include("thinkingBudget" => 24_000) }
    bodies({}).each { |body| expect(thinking(body)).to be_nil }
  end

  it "searches the web in every request of a message sent with it, and in none of one sent without" do
    searching = ->(message, change) { bodies(message, change: change).map { |b| JSON.generate(b["tools"]).include?("gemini_web_search") } }
    expect(searching.call({ "websearch" => true }, { "websearch" => false })).to eq([true, true])
    expect(searching.call({ "websearch" => false }, { "websearch" => true })).to eq([false, false])
    expect(searching.call({}, { "websearch" => true })).to eq([false, false])
  end
end
