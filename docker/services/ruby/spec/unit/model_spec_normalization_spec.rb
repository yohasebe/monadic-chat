require "spec_helper"
require_relative "../../lib/monadic/utils/model_spec"

RSpec.describe Monadic::Utils::ModelSpec do
  describe "normalization and accessors" do
    it "normalizes reasoning_model to is_reasoning_model (Cohere)" do
      model = "command-a-reasoning-08-2025"
      # Cohere spec uses reasoning_model; normalization should expose is_reasoning_model
      is_reasoning = Monadic::Utils::ModelSpec.get_model_property(model, "is_reasoning_model")
      # Either the spec already provides it, or the normalizer mapped it
      expect([true, false]).to include(is_reasoning)
      # And accessor reflects the canonical property presence
      # If reasoning_effort is present for the model, it is a reasoning-capable model
      opts = Monadic::Utils::ModelSpec.get_model_property(model, "reasoning_effort")
      expect(opts).not_to be_nil
    end

    it "recognizes Perplexity PDF=URL-only via supports_pdf_upload=false" do
      model = "sonar-pro"
      expect(Monadic::Utils::ModelSpec.supports_pdf?(model)).to be true
      expect(Monadic::Utils::ModelSpec.supports_pdf_upload?(model)).to be false
      expect(Monadic::Utils::ModelSpec.supports_web_search?(model)).to be true
      # vision capability present for image URL support
      expect(Monadic::Utils::ModelSpec.vision_capability?(model)).to be true
    end

    it "marks Cohere models as not supporting PDFs" do
      model = "command-a-03-2025"
      expect(Monadic::Utils::ModelSpec.supports_pdf?(model)).to be false
      # vision_capability may be absent; accessor defaults to true when undefined
      # this test only asserts PDF behavior for Cohere non-vision model
    end

    it "exposes streaming/tool capability with safe defaults" do
      model = "grok-2-vision-1212"
      # tools default to true when unspecified
      expect(Monadic::Utils::ModelSpec.tool_capability?(model)).to be true
      # streaming defaults to true when unspecified
      expect(Monadic::Utils::ModelSpec.supports_streaming?(model)).to be true
      # vision=true per spec; pdf=false per spec tweak
      expect(Monadic::Utils::ModelSpec.vision_capability?(model)).to be true
      expect(Monadic::Utils::ModelSpec.supports_pdf?(model)).to be false
    end

    it "supports Responses API detection via api_type" do
      # GPT-5 models are marked as Responses API in the spec
      model = "gpt-5"
      expect(Monadic::Utils::ModelSpec.responses_api?(model)).to be true
    end
  end
end

