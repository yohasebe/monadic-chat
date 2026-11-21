# frozen_string_literal: true

require "spec_helper"
require_relative "../../../support/turn_settings_turn"
require_relative "../../../../lib/monadic/adapters/vendors/openai_helper"

# An OpenAI turn is sent with the settings of its message: in every request
# of the turn, whatever the chat's kept parameters say meanwhile.
RSpec.describe "The settings of an OpenAI turn" do
  include TurnSettingsTurn

  let(:models) { Monadic::Utils::ModelSpec.get_provider_models("openai", "chat") }
  # A model that reasons by levels of effort, and its levels.
  let(:model) { models.find { |m| levels(m).size > 1 } }

  def levels(name)
    Array(Monadic::Utils::ModelSpec.get_reasoning_effort_options(name)&.dig(:options)).map(&:to_s) - ["none"]
  end

  def bodies(message, kept: {}, change: {}, history: [])
    turn_bodies(OpenAIHelper, format: StreamContract::Responses, kind: :sse, key: "OPENAI_API_KEY",
                message: { "model" => model, "context_size" => "5" }.merge(message), kept: kept, change: change,
                history: history)
  end

  it "keeps the message's settings in the request that sends the tool's result back" do
    sent = bodies({ "reasoning_effort" => levels(model).last, "max_tokens" => "3000" },
                  change: { "reasoning_effort" => levels(model).first, "max_tokens" => "9000",
                            "model" => models.find { |m| m != model } })
    expect(sent.size).to eq(2)
    sent.each do |body|
      expect(body["model"]).to eq(model)
      expect(body.dig("reasoning", "effort")).to eq(levels(model).last)
      expect(body["max_output_tokens"]).to eq(3000)
    end
  end

  it "does not take an effort or an output limit the message leaves out from an earlier message" do
    unasked = bodies({}).first
    sent = bodies({}, kept: { "reasoning_effort" => levels(model).last, "max_tokens" => "3000",
                              "max_completion_tokens" => "2000" })
    sent.each do |body|
      expect(body["reasoning"]).to eq(unasked["reasoning"])
      expect(body["max_output_tokens"]).to eq(unasked["max_output_tokens"])
    end
  end

  it "reads the output limit under either name, and sends the model's for one of zero" do
    unasked = bodies({}).first["max_output_tokens"]
    expect(bodies({ "max_completion_tokens" => "512", "max_tokens" => "3000" }).map { |b| b["max_output_tokens"] }).to eq([512, 512])
    expect(bodies({ "max_completion_tokens" => "0", "max_tokens" => "3000" }).map { |b| b["max_output_tokens"] }).to eq([3000, 3000])
    expect(bodies({ "max_tokens" => "0" }).map { |b| b["max_output_tokens"] }).to eq([unasked, unasked])
  end

  describe "a chat with an image" do
    let(:history) do
      [{ "role" => "user", "text" => "Look.", "active" => true,
         "images" => [{ "data" => "data:image/png;base64,iVBORw0KGgo=", "type" => "image/png", "title" => "a.png" }] },
       { "role" => "assistant", "text" => "Seen.", "active" => true }]
    end

    it "is sent to a model the catalog says takes images, whatever the page said" do
      seeing = models.find { |m| Monadic::Utils::ModelSpec.get_model_property(m, "vision_capability") == true }
      sent = turn_bodies(OpenAIHelper, format: StreamContract::Responses, kind: :sse, key: "OPENAI_API_KEY",
                         message: { "model" => seeing, "context_size" => "5", "vision_capability" => false },
                         history: history)
      expect(sent.size).to eq(2)
      expect(JSON.generate(sent.first)).to include("iVBORw0KGgo=")
    end

    it "is not sent to a model the catalog says takes none, whatever the page said" do
      allow(Monadic::Utils::ModelSpec).to receive(:vision_capability?).and_return(false)
      sent = bodies({ "vision_capability" => true }, history: history)
      expect(sent).to be_empty
    end
  end

  it "searches the web for a message sent with it, and not for one sent without" do
    searching = ->(message, kept) { JSON.generate(bodies(message, kept: kept).first["tools"]).include?("web_search") }
    expect(searching.call({ "websearch" => true }, { "websearch" => false })).to be(true)
    expect(searching.call({ "websearch" => false }, { "websearch" => true })).to be(false)
    expect(searching.call({}, { "websearch" => true })).to be(false)
  end
end
