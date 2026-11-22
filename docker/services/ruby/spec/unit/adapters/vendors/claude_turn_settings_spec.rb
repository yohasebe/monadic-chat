# frozen_string_literal: true

require "spec_helper"
require_relative "../../../support/turn_settings_turn"
require_relative "../../../../lib/monadic/adapters/vendors/claude_helper"

# A Claude turn is sent with the settings of its message: in every request
# of the turn, whatever the chat's kept parameters say meanwhile.
RSpec.describe "The settings of a Claude turn" do
  include TurnSettingsTurn

  let(:models) { Monadic::Utils::ModelSpec.get_provider_models("anthropic", "chat") }
  # A model that thinks by levels of effort.
  let(:model) { models.find { |m| Monadic::Utils::ModelSpec.supports_adaptive_thinking?(m) } }
  let(:levels) { Monadic::Utils::ModelSpec.get_reasoning_effort_options(model).fetch(:options).map(&:to_s) - ["none"] }

  def bodies(message, kept: {}, change: {})
    turn_bodies(ClaudeHelper, format: StreamContract::Claude, kind: :sse, key: "ANTHROPIC_API_KEY",
                message: { "model" => model, "context_size" => "5" }.merge(message), kept: kept, change: change)
  end

  # What a body says of thinking and its output.
  def thinking(body) = body.slice("thinking", "output_config", "max_tokens")

  it "keeps the message's settings in the request that sends the tool's result back" do
    alone = bodies({ "reasoning_effort" => levels.last, "show_thinking" => false, "max_tokens" => "3000" })
    sent = bodies({ "reasoning_effort" => levels.last, "show_thinking" => false, "max_tokens" => "3000" },
                  change: { "reasoning_effort" => levels.first, "show_thinking" => true, "max_tokens" => "9000",
                            "model" => models.find { |m| m != model } })
    expect(sent.size).to eq(2)
    sent.each do |body|
      expect(body["model"]).to eq(model)
      expect(thinking(body)).to eq(thinking(alone.first))
      expect(body["max_tokens"]).to eq(3000)
    end
    expect(thinking(sent.first)).not_to eq(thinking(bodies({ "reasoning_effort" => levels.first }).first))
  end

  it "does not take an effort, hidden thinking or an output limit from an earlier message" do
    unasked = bodies({})
    sent = bodies({}, kept: { "reasoning_effort" => levels.last, "show_thinking" => false, "max_tokens" => "3000" })
    sent.each { |body| expect(thinking(body)).to eq(thinking(unasked.first)) }
  end

  it "tells apart a message that says not to reason from one that says nothing of it" do
    always = models.find { |m| Monadic::Utils::ModelSpec.thinking_on_by_default?(m) && Monadic::Utils::ModelSpec.supports_adaptive_thinking?(m) }
    skip "no model that always thinks" unless always
    lowest = Monadic::Utils::ModelSpec.get_reasoning_effort_options(always).fetch(:options).first
    said = turn_bodies(ClaudeHelper, format: StreamContract::Claude, kind: :sse, key: "ANTHROPIC_API_KEY",
                       message: { "model" => always, "context_size" => "5", "reasoning_effort" => "none" })
    unsaid = turn_bodies(ClaudeHelper, format: StreamContract::Claude, kind: :sse, key: "ANTHROPIC_API_KEY",
                         message: { "model" => always, "context_size" => "5" }, kept: { "reasoning_effort" => "none" })
    expect(said.map { |body| body.dig("output_config", "effort") }).to eq([lowest, lowest])
    expect(unsaid.map { |body| body.dig("output_config", "effort") }).to eq([nil, nil])
  end

  it "sends the model's output limit for one of zero, and no temperature for what is not a number" do
    unasked = bodies({}).first
    bodies({ "max_tokens" => "0", "temperature" => "warm" }).each do |body|
      expect(body["max_tokens"]).to eq(unasked["max_tokens"])
      expect(body).not_to have_key("temperature")
    end
  end

  # The search tool goes with a turn's first request.
  it "searches the web for a message sent with it, and not for one sent without" do
    searching = ->(message, kept) { JSON.generate(bodies(message, kept: kept).first["tools"]).include?("web_search") }
    expect(searching.call({ "websearch" => true }, { "websearch" => false })).to be(true)
    expect(searching.call({ "websearch" => false }, { "websearch" => true })).to be(false)
    expect(searching.call({}, { "websearch" => true })).to be(false)
  end
end
