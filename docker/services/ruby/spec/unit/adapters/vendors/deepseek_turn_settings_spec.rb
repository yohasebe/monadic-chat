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

  it "offers web search in every request of a message sent with it, and in none of one sent without" do
    stub_const("CONFIG", CONFIG.to_h.merge("TAVILY_API_KEY" => "k"))
    searching = ->(message, change) { bodies(message, change: change).map { |b| JSON.generate(b["tools"]).include?("tavily_search") } }
    expect(searching.call({ "websearch" => true }, { "websearch" => false })).to eq([true, true])
    expect(searching.call({ "websearch" => false }, { "websearch" => true })).to eq([false, false])
    expect(searching.call({}, { "websearch" => true })).to eq([false, false])
  end

  it "does not give the search tools to a model the catalog says takes no tools" do
    stub_const("CONFIG", CONFIG.to_h.merge("TAVILY_API_KEY" => "k"))
    allow(Monadic::Utils::ModelSpec).to receive(:get_model_property).and_call_original
    allow(Monadic::Utils::ModelSpec).to receive(:get_model_property).with(model, "tool_capability").and_return(false)
    sent = bodies({ "websearch" => true })
    expect(sent).not_to be_empty
    expect(JSON.generate(sent.first)).not_to include("tavily_search")
  end
end
