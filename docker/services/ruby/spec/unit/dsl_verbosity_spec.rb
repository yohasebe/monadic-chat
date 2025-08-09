require "spec_helper"
require "ostruct"
require_relative "../../lib/monadic/dsl"

RSpec.describe "MDSL Verbosity Support" do
  describe MonadicDSL::LLMConfiguration do
    let(:state) { OpenStruct.new(settings: {}) }
    let(:llm_config) { MonadicDSL::LLMConfiguration.new(state) }

    describe "#verbosity" do
      it "sets verbosity parameter for GPT-5" do
        llm_config.verbosity("low")
        expect(state[:settings][:verbosity]).to eq("low")
      end

      it "accepts high verbosity setting" do
        llm_config.verbosity("high")
        expect(state[:settings][:verbosity]).to eq("high")
      end

      it "accepts medium verbosity setting" do
        llm_config.verbosity("medium")
        expect(state[:settings][:verbosity]).to eq("medium")
      end
    end
  end

  # Note: MDSL parsing is tested through the LLMConfiguration class above
  # The actual file parsing is handled internally by the DSL system
end