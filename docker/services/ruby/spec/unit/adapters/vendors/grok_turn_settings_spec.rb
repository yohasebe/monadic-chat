# frozen_string_literal: true

require "spec_helper"
require_relative "../../../support/turn_settings_turn"
require_relative "../../../../lib/monadic/adapters/vendors/grok_helper"

# A Grok turn is sent with the settings of its message: in every request of
# the turn, whatever the chat's kept parameters say meanwhile.
RSpec.describe "The settings of a Grok turn" do
  include TurnSettingsTurn

  let(:model) { Monadic::Utils::ModelSpec.get_provider_models("xai", "chat").first }
  let(:effort) { Monadic::Utils::ModelSpec.get_reasoning_effort_options(model)&.dig(:options)&.last }

  def bodies(message, kept: {}, change: {})
    turn_bodies(GrokHelper, format: StreamContract::Responses, kind: :sse, key: "XAI_API_KEY",
                message: { "model" => model, "context_size" => "5" }.merge(message), kept: kept, change: change)
  end

  it "keeps the message's settings in the request that sends the tool's result back" do
    sent = bodies({ "temperature" => "0.2", "max_tokens" => "300", "presence_penalty" => "0.3",
                    "frequency_penalty" => "0.1", "reasoning_effort" => effort },
                  change: { "temperature" => "1.4", "max_tokens" => "9000", "presence_penalty" => "1.5",
                            "frequency_penalty" => "1.5", "reasoning_effort" => "none", "model" => "another-model" })
    expect(sent.size).to eq(2)
    sent.each do |body|
      expect(body.slice("model", "temperature", "max_output_tokens", "presence_penalty", "frequency_penalty")).to eq(
        "model" => model, "temperature" => 0.2, "max_output_tokens" => 300, "presence_penalty" => 0.3,
        "frequency_penalty" => 0.1
      )
      expect(body.dig("reasoning", "effort")).to eq(effort) if effort
    end
  end

  it "does not take a penalty, an output limit or an effort the message leaves out from an earlier message" do
    sent = bodies({}, kept: { "presence_penalty" => "0.8", "frequency_penalty" => "0.8", "max_tokens" => "9000",
                              "reasoning_effort" => effort })
    sent.each do |body|
      expect(body.keys).not_to include("presence_penalty", "frequency_penalty", "max_output_tokens", "reasoning")
    end
  end

  it "sends a request a tool makes of its own with that request's settings, not those of the reply it runs in" do
    sent = turn_bodies(GrokHelper, format: StreamContract::Responses, kind: :sse, key: "XAI_API_KEY",
                       message: { "model" => model, "context_size" => "5", "temperature" => "0.1" },
                       answering: { "model" => "the-chat-s-model", "temperature" => "1.9", "max_tokens" => "9000",
                                    "presence_penalty" => "1.5" })
    sent.each do |body|
      expect(body.slice("model", "temperature")).to eq("model" => model, "temperature" => 0.1)
      expect(body.keys).not_to include("max_output_tokens", "presence_penalty")
    end
  end

  it "sends a penalty the message names as zero, and none for what is not a number" do
    sent = bodies({ "presence_penalty" => "0", "frequency_penalty" => 0.0 })
    sent.each { |body| expect(body.slice("presence_penalty", "frequency_penalty")).to eq("presence_penalty" => 0.0, "frequency_penalty" => 0.0) }
    sent = bodies({ "presence_penalty" => "much", "frequency_penalty" => "" })
    sent.each { |body| expect(body.keys).not_to include("presence_penalty", "frequency_penalty") }
  end

  it "sends no output limit of zero" do
    bodies({ "max_tokens" => "0" }).each { |body| expect(body).not_to have_key("max_output_tokens") }
  end

  it "searches the web in every request of a message sent with it, and in none of one sent without" do
    searching = ->(message, change) { bodies(message, change: change).map { |b| JSON.generate(b["tools"]).include?("web_search") } }
    expect(searching.call({ "websearch" => true }, { "websearch" => false })).to eq([true, true])
    expect(searching.call({ "websearch" => false }, { "websearch" => true })).to eq([false, false])
    expect(searching.call({}, { "websearch" => true })).to eq([false, false])
  end

  describe "a message with an image" do
    let(:image) { { "title" => "dot.png", "type" => "image/png", "data" => "data:image/png;base64,iVBORw0KGgo=" } }

    def sent_with(message)
      history = [{ "role" => "user", "text" => "Look.", "active" => true, "images" => [image] }]
      turn_bodies(GrokHelper, format: StreamContract::Responses, kind: :sse, key: "XAI_API_KEY",
                  message: { "model" => model, "context_size" => "5", "message" => "Look.", "images" => [image] }
                           .merge(message),
                  messages: [{ "role" => "system", "text" => "S", "active" => true }] + history)
    end

    it "is sent with its image in a chat" do
      sent = sent_with({})
      expect(sent).not_to be_empty
      expect(JSON.generate(sent.first)).to include("iVBORw0KGgo=")
    end

    it "is refused by Image Generator, whose API takes no image" do
      expect(sent_with({ "display_name" => "Image Generator" })).to be_empty
    end
  end
end
