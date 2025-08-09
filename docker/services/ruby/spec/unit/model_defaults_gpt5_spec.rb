require "spec_helper"
require_relative "../../lib/monadic/utils/model_defaults"

RSpec.describe Monadic::Utils::ModelDefaults do
  describe ".get_max_tokens" do
    context "with GPT-5 models (128K max output)" do
      it "returns 128K token limit for GPT-5" do
        expect(described_class.get_max_tokens("gpt-5")).to eq(128000)
      end
      
      it "returns 128K token limit for GPT-5-mini" do
        expect(described_class.get_max_tokens("gpt-5-mini")).to eq(128000)
      end
      
      it "returns 128K token limit for GPT-5-nano" do
        expect(described_class.get_max_tokens("gpt-5-nano")).to eq(128000)
      end
    end
    
    context "with o3 series models" do
      it "returns high token limit for o3-pro" do
        expect(described_class.get_max_tokens("o3-pro")).to eq(32768)
      end
      
      it "returns appropriate token limit for o3" do
        expect(described_class.get_max_tokens("o3")).to eq(16384)
      end
      
      it "returns appropriate token limit for o3-mini" do
        expect(described_class.get_max_tokens("o3-mini")).to eq(8192)
      end
    end
    
    context "with existing models" do
      it "returns correct token limit for GPT-4.1" do
        expect(described_class.get_max_tokens("gpt-4.1")).to eq(32768)
      end
      
      it "returns correct token limit for Claude Sonnet" do
        expect(described_class.get_max_tokens("claude-3-5-sonnet-20241022")).to eq(8192)
      end
    end
    
    context "with unknown models" do
      it "returns default token limit for unknown model" do
        expect(described_class.get_max_tokens("unknown-model-xyz")).to eq(4096)
      end
      
      it "returns default token limit for nil model" do
        expect(described_class.get_max_tokens(nil)).to eq(4096)
      end
    end
  end
end