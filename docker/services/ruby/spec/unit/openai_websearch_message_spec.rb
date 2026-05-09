# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe "OpenAI Web Search Processing Message" do
  describe "OpenAIHelper api_request behavior" do
    it "does not flag regular OpenAI chat models as slow reasoning models" do
      # Regular chat models should not trigger the "This may take a while" UX.
      # The slow-path message is gated on latency_tier: "slow" + is_reasoning_model,
      # which is currently dormant for OpenAI (no slow-path model in catalog).
      regular_models = ["gpt-5.4", "gpt-5.4-mini", "gpt-5.4-nano", "gpt-5.2", "gpt-5.1"]

      regular_models.each do |model|
        expect(Monadic::Utils::ModelSpec.responses_api?(model)).to be true
        expect(Monadic::Utils::ModelSpec.is_reasoning_model?(model)).to be_falsey
        expect(Monadic::Utils::ModelSpec.get_model_property(model, "latency_tier")).not_to eq("slow")
      end
    end
  end
end
