# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/monadic/utils/provider_capabilities"

# Analysis runs on the app's own provider or not at all: no other provider is
# ever chosen because it happens to have a key.
RSpec.describe Monadic::Utils::ProviderCapabilities do
  let(:all_keys) do
    described_class::API_KEYS.values.to_h { |k| [k, "set"] }
  end

  it "normalizes provider names and aliases" do
    expect(described_class.normalize("Claude")).to eq("anthropic")
    expect(described_class.normalize("gemini")).to eq("google")
    expect(described_class.normalize("grok")).to eq("xai")
    expect(described_class.normalize("  ")).to be_nil
    expect(described_class.normalize("somebody")).to be_nil
  end

  it "resolves to the app's own provider when it can do the job and has a key" do
    expect(described_class.resolve(:image, "claude", all_keys)).to eq(provider: "anthropic")
    expect(described_class.resolve(:audio, "gemini", all_keys)).to eq(provider: "google")
  end

  it "never falls back to another provider, even when every other key is set" do
    result = described_class.resolve(:audio, "anthropic", all_keys)
    expect(result).not_to have_key(:provider)
    expect(result[:error]).to start_with("ERROR: Audio transcription is not available")

    no_own_key = all_keys.reject { |k, _| k == "ANTHROPIC_API_KEY" }
    expect(described_class.resolve(:image, "anthropic", no_own_key)[:error]).to include("ANTHROPIC_API_KEY")
  end

  it "refuses an empty or unknown provider instead of picking one" do
    expect(described_class.resolve(:image, "", all_keys)[:error]).to include("needs a provider")
    expect(described_class.resolve(:image, nil, all_keys)[:error]).to include("needs a provider")
    expect(described_class.resolve(:image, "somebody", all_keys)[:error]).to include("not available")
  end

  it "keeps video separate from image" do
    expect(described_class.supports?(:video, "openai")).to be true
    expect(described_class.supports?(:video, "ollama")).to be false
  end
end
