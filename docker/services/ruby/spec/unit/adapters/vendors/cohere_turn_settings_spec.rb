# frozen_string_literal: true

require "spec_helper"
require_relative "../../../support/turn_settings_turn"
require_relative "../../../../lib/monadic/adapters/vendors/cohere_helper"

# A Cohere turn is sent with the settings of its message: in every request
# of the turn, whatever the chat's kept parameters say meanwhile.
RSpec.describe "The settings of a Cohere turn" do
  include TurnSettingsTurn

  let(:model) { Monadic::Utils::ModelSpec.get_provider_models("cohere", "chat").find { |m| CohereHelper.is_thinking_model?(m) } }

  # With tools, a model told not to reason is sent the least of it (it
  # refuses tools with thinking disabled); one that reasons has no budget.
  let(:not_reasoning) { { "type" => "enabled", "token_budget" => CohereHelper::LEAST_THINKING_BUDGET } }
  let(:reasoning) { { "type" => "enabled" } }

  def bodies(message, kept: {}, change: {})
    turn_bodies(CohereHelper, format: StreamContract::Cohere, kind: :ndjson, key: "COHERE_API_KEY",
                message: { "model" => model, "context_size" => "5" }.merge(message), kept: kept, change: change)
  end

  it "keeps the message's settings in the request that sends the tool's result back" do
    sent = bodies({ "reasoning_effort" => "disabled", "temperature" => "0.2", "max_tokens" => "300" },
                  change: { "reasoning_effort" => "enabled", "temperature" => "1.4", "max_tokens" => "9000",
                            "model" => "another-model" })
    expect(sent.size).to eq(2)
    sent.each do |body|
      expect(body.slice("model", "temperature", "max_tokens")).to eq("model" => model, "temperature" => 0.2, "max_tokens" => 300)
    end
    expect(sent.first["thinking"]).to eq(not_reasoning)
  end

  it "reasons unless the message says not to, whatever an earlier message said" do
    sent = bodies({}, kept: { "reasoning_effort" => "disabled", "temperature" => "1.4", "max_tokens" => "9000" })
    expect(sent.first["thinking"]).to eq(reasoning)
    sent.each { |body| expect(body.keys).not_to include("temperature", "max_tokens") }
    %w[high banana Enabled].each do |named|
      expect(bodies({ "reasoning_effort" => named }).first["thinking"]).to eq(reasoning), named
    end
    expect(bodies({ "reasoning_effort" => " Disabled " }).first["thinking"]).to eq(not_reasoning)
  end

  it "leaves the chat's kept parameters as they are" do
    helper = Class.new(MonadicApp) { include CohereHelper }.new
    kept = { "model" => model, "reasoning_effort" => "high" }
    helper.send(:configure_cohere_reasoning, {}, [{ "role" => "user", "content" => "hi" }], kept, {})
    expect(kept).to eq("model" => model, "reasoning_effort" => "high")
  end

  it "sends no temperature for what is not a number, and no output limit of zero" do
    bodies({ "temperature" => "warm", "max_tokens" => "0" }).each do |body|
      expect(body.keys).not_to include("temperature", "max_tokens")
    end
  end

  it "offers web search in every request of a message sent with it, and in none of one sent without" do
    stub_const("CONFIG", CONFIG.to_h.merge("TAVILY_API_KEY" => "k"))
    searching = ->(message, change) { bodies(message, change: change).map { |b| JSON.generate(b["tools"]).include?("tavily_search") } }
    expect(searching.call({ "websearch" => true }, { "websearch" => false })).to eq([true, true])
    expect(searching.call({ "websearch" => false }, { "websearch" => true })).to eq([false, false])
    expect(searching.call({}, { "websearch" => true })).to eq([false, false])
  end
end
