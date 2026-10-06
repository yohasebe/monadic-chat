# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/monadic/adapters/vendors/mistral_helper"

# Two things the live API showed on 2026-10-06:
#
# 1. Leaving reasoning_effort out means different things per model. Mistral
#    Large 4 / Medium 3.5 do not reason without it; Z.ai GLM 5.3 reasons at
#    about its maximum, and rejects "none" (accepts low/high/max). Dropping
#    "none" therefore made "no reasoning" silently the most expensive setting
#    on GLM.
# 2. The model list dropped every id ending in a version number, so
#    mistral-medium-3-5 (the provider default), mistral-large-4 and
#    zai-glm-5-3 never reached the model selector.
RSpec.describe MistralHelper do
  let(:helper) { Class.new { include MistralHelper }.new }

  describe "#mistral_effort_for" do
    it "sends nothing for no reasoning where the model accepts none" do
      expect(helper.mistral_effort_for("mistral-large-4", "none")).to be_nil
      expect(helper.mistral_effort_for("mistral-large-4", nil)).to be_nil
      expect(helper.mistral_effort_for("mistral-medium-3-5", "none")).to be_nil
    end

    it "sends the lowest level where the model rejects none, so no reasoning is not max" do
      expect(helper.mistral_effort_for("zai-glm-5-3", "none")).to eq("low")
      expect(helper.mistral_effort_for("zai-glm-5-3", nil)).to eq("low")
    end

    it "passes a supported level through" do
      expect(helper.mistral_effort_for("mistral-large-4", "high")).to eq("high")
      expect(helper.mistral_effort_for("zai-glm-5-3", "max")).to eq("max")
    end

    it "maps an unsupported level to the nearest accepted one instead of a 400" do
      expect(helper.mistral_effort_for("mistral-large-4", "low")).to eq("high")
      expect(helper.mistral_effort_for("mistral-large-4", "medium")).to eq("high")
      expect(helper.mistral_effort_for("zai-glm-5-3", "medium")).to eq("high")
      expect(helper.mistral_effort_for("zai-glm-5-3", "xhigh")).to eq("max")
    end

    it "sends nothing for a model whose spec declares no reasoning_effort (Magistral rejects it)" do
      expect(helper.mistral_effort_for("magistral-medium-latest", "high")).to be_nil
    end

    it "never raises the effort for a value it does not know" do
      expect(helper.mistral_effort_for("mistral-large-4", "off")).to be_nil
      expect(helper.mistral_effort_for("zai-glm-5-3", "off")).to eq("low")
      expect(helper.mistral_effort_for("zai-glm-5-3", "  ")).to eq("low")
      expect(helper.mistral_effort_for("zai-glm-5-3", "HIGH")).to eq("high")
    end

    it "orders the levels by strength, not by how the spec lists them" do
      allow(Monadic::Utils::ModelSpec).to receive(:get_reasoning_effort_options)
        .with("reordered").and_return(options: %w[max low high], default: "low")
      expect(helper.mistral_effort_for("reordered", "none")).to eq("low")
      expect(helper.mistral_effort_for("reordered", "medium")).to eq("high")
    end
  end

  describe "#mistral_buffer_answer?" do
    it "holds the answer back only when reasoning was asked for on a model that can take none" do
      expect(helper.mistral_buffer_answer?("mistral-large-4", "high", true)).to be true
      expect(helper.mistral_buffer_answer?("mistral-large-4", "none", true)).to be false
      expect(helper.mistral_buffer_answer?("mistral-large-4", nil, true)).to be false
    end

    it "streams GLM, which returns its reasoning as structured parts" do
      expect(helper.mistral_buffer_answer?("zai-glm-5-3", "low", true)).to be false
      expect(helper.mistral_buffer_answer?("zai-glm-5-3", "max", true)).to be false
    end

    it "keeps the earlier behaviour for Magistral and for non-reasoning models" do
      expect(helper.mistral_buffer_answer?("magistral-medium-latest", "high", true)).to be true
      expect(helper.mistral_buffer_answer?("magistral-medium-latest", "none", true)).to be false
      expect(helper.mistral_buffer_answer?("mistral-large-latest", "high", false)).to be false
    end
  end

  # The bodies the two request paths actually send.
  describe "request bodies" do
    let(:app_helper) { Class.new(MonadicApp) { include MistralHelper }.new }
    let(:cases) do
      [
        ["mistral-large-4", nil, nil],
        ["mistral-large-4", "none", nil],
        ["mistral-large-4", "high", "high"],
        ["mistral-large-4", "low", "high"],
        ["mistral-medium-3-5", "none", nil],
        ["mistral-small-2603", "high", "high"],
        ["zai-glm-5-3", nil, "low"],
        ["zai-glm-5-3", "none", "low"],
        ["zai-glm-5-3", "max", "max"],
        ["magistral-medium-latest", "high", nil],
        ["mistral-large-latest", "high", nil]
      ]
    end

    before do
      stub_const("APPS", { "SpecApp" => Struct.new(:settings).new({}) })
      stub_const("CONFIG", { "MISTRAL_API_KEY" => "test-key" })
    end

    def expect_body(body, model, sent)
      if sent
        expect(body["reasoning_effort"]).to eq(sent), "#{model}: effort"
        expect(body).not_to have_key("temperature"), "#{model}: temperature"
      else
        expect(body).not_to have_key("reasoning_effort"), "#{model}: effort"
        expect(body).to have_key("temperature"), "#{model}: temperature"
      end
    end

    it "matches on the send_query path" do
      cases.each do |model, requested, sent|
        body = nil
        allow(app_helper).to receive(:post_json_with_retries) { |_http, _uri, b, **| body = b; nil }
        app_helper.send_query({ "reasoning_effort" => requested, "messages" => [{ "role" => "user", "content" => "hi" }] },
                              model: model)
        expect_body(body, model, sent)
      end
    end

    it "matches on the api_request path" do
      client = double("http")
      allow(HTTP).to receive(:headers).and_return(client)
      allow(client).to receive(:timeout).and_return(client)
      cases.each do |model, requested, sent|
        body = nil
        allow(client).to receive(:post) do |_uri, json:|
          body = json
          double("res", status: double(success?: false, to_s: "400", code: 400), body: '{"message":"stop"}')
        end
        session = { parameters: { "app_name" => "SpecApp", "model" => model, "reasoning_effort" => requested,
                                  "context_size" => "5", "max_tokens" => "100", "message" => "hi" },
                    messages: [] }
        app_helper.api_request("user", session) { |_| }
        expect_body(body, model, sent)
      end
    end
  end

  describe ".mistral_model_excluded?" do
    it "keeps models the model spec knows, whatever their names end with" do
      %w[mistral-large-4 mistral-medium-3-5 mistral-small-2603 zai-glm-5-3].each do |id|
        expect(described_class.mistral_model_excluded?(id)).to be(false), id
      end
    end

    it "keeps only exact spec names, not dated variants of them" do
      expect(described_class.mistral_model_excluded?("mistral-large-4-2610")).to be true
    end

    it "still drops embedding and moderation models even if the spec names them" do
      allow(Monadic::Utils::ModelSpec).to receive(:registered?).and_return(true)
      expect(described_class.mistral_model_excluded?("mistral-embed")).to be true
      expect(described_class.mistral_model_excluded?("mistral-moderation-2411")).to be true
    end

    it "still drops unknown versioned snapshots and non-chat models" do
      expect(described_class.mistral_model_excluded?("mistral-large-2411")).to be true
      expect(described_class.mistral_model_excluded?("mistral-embed")).to be true
      expect(described_class.mistral_model_excluded?("mistral-moderation-latest")).to be true
      expect(described_class.mistral_model_excluded?("mistral-small-latest")).to be false
    end
  end

  it "uses Mistral Large 4 as the provider default" do
    expect(Monadic::Utils::ModelSpec.get_provider_models("mistral", "chat").first).to eq("mistral-large-4")
    expect(described_class.get_default_model).to eq("mistral-large-4")
  end
end
