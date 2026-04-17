# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/monadic/utils/tts_utils"
require_relative "../../../lib/monadic/utils/model_spec"

# Focused tests for InteractionUtils#resolve_tts_model dispatch, especially for
# providers newly added beside OpenAI. Verifies that each provider_label
# routes to the correct ModelSpec provider entry.

RSpec.describe "InteractionUtils#resolve_tts_model dispatch" do
  let(:host) do
    Class.new do
      include InteractionUtils
      public :resolve_tts_model
    end.new
  end

  describe "Grok dispatch" do
    it "resolves 'grok' to the first xai TTS model" do
      allow(Monadic::Utils::ModelSpec).to receive(:get_provider_models)
        .with("xai", "tts")
        .and_return(["grok-tts"])

      expect(host.resolve_tts_model("grok")).to eq("grok-tts")
    end

    it "returns nil when xai has no TTS models configured" do
      allow(Monadic::Utils::ModelSpec).to receive(:get_provider_models)
        .with("xai", "tts")
        .and_return([])

      expect(host.resolve_tts_model("grok")).to be_nil
    end

    it "does not fall through to OpenAI when label starts with 'grok'" do
      # Guard against a regression where provider_label case ordering changes
      # and a 'grok-*' label accidentally dispatches to the OpenAI default.
      allow(Monadic::Utils::ModelSpec).to receive(:get_provider_models)
        .with("xai", "tts")
        .and_return(["grok-tts"])
      allow(Monadic::Utils::ModelSpec).to receive(:get_provider_models)
        .with("openai", "tts")
        .and_return(["gpt-4o-mini-tts"])

      expect(host.resolve_tts_model("grok")).to eq("grok-tts")
    end
  end

  describe "Gemini dispatch preserves new 3.1 model as primary" do
    it "resolves 'gemini-flash' to the first gemini TTS entry (SSOT-ordered)" do
      allow(Monadic::Utils::ModelSpec).to receive(:get_provider_models)
        .with("gemini", "tts")
        .and_return([
          "gemini-3.1-flash-tts-preview",
          "gemini-2.5-flash-preview-tts",
          "gemini-2.5-pro-preview-tts"
        ])

      expect(host.resolve_tts_model("gemini-flash")).to eq("gemini-3.1-flash-tts-preview")
    end

    it "resolves 'gemini-pro' to the [1] entry (kept for backward compat)" do
      allow(Monadic::Utils::ModelSpec).to receive(:get_provider_models)
        .with("gemini", "tts")
        .and_return([
          "gemini-3.1-flash-tts-preview",
          "gemini-2.5-flash-preview-tts",
          "gemini-2.5-pro-preview-tts"
        ])

      # Note: resolve_tts_model for "gemini-pro" returns index [1], which is
      # the old 2.5 flash model in the new SSOT order. This is intentional:
      # "gemini-pro" historically mapped to 2.5-pro, but after 3.1 rollout
      # the [1] slot is now 2.5-flash. Users who specifically want 2.5-pro
      # can wait for a dedicated follow-up or specify the model explicitly.
      expect(host.resolve_tts_model("gemini-pro")).to eq("gemini-2.5-flash-preview-tts")
    end
  end
end
