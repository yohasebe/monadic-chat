# frozen_string_literal: true

require_relative "../../spec_helper"
require "monadic/substitution/vocabulary"

RSpec.describe Monadic::Substitution::Vocabulary do
  describe "BUILTINS registry (SSOT)" do
    it "is frozen" do
      expect(described_class::BUILTINS).to be_frozen
    end

    it "includes the canonical :shared token" do
      shared = described_class::BUILTINS[:shared]
      expect(shared[:token]).to eq("SHARED")
      expect(shared[:description]).to be_a(String).and(satisfy { |d| !d.empty? })
    end

    it "uses single-word UPPER_CASE token names disjoint from Privacy's <<TYPE_N>>" do
      described_class::BUILTINS.each_value do |meta|
        expect(meta[:token]).to match(/\A[A-Z][A-Z_]*\z/),
          "vocabulary token #{meta[:token].inspect} must be single-word UPPER_CASE"
        # Must NOT look like a Privacy placeholder (TYPE_N) to keep the
        # namespaces disjoint in the unified ${...} space.
        expect(meta[:token]).not_to match(/_\d+\z/)
      end
    end

    it "every entry carries a token and a description" do
      described_class::BUILTINS.each do |name, meta|
        expect(name).to be_a(Symbol)
        expect(meta).to include(:token, :description)
      end
    end

    it "every entry carries a session-taking :resolve proc" do
      described_class::BUILTINS.each_value do |meta|
        expect(meta[:resolve]).to respond_to(:call)
        expect(meta[:resolve].arity).to eq(1) # takes the session hash (decision D)
      end
    end
  end

  describe ".entry_for_token" do
    it "looks up a built-in by its ${TOKEN} name" do
      expect(described_class.entry_for_token("SHARED")).to eq(described_class::BUILTINS[:shared])
    end

    it "returns nil for an unknown token" do
      expect(described_class.entry_for_token("NOPE")).to be_nil
    end
  end

  describe ".tokens_for (default-on policy)" do
    it "defaults to [:shared] when the app has no vocabulary config" do
      expect(described_class.tokens_for(nil)).to eq([:shared])
      expect(described_class.tokens_for({})).to eq([:shared])
    end

    it "defaults to [:shared] for an empty vocabulary block" do
      expect(described_class.tokens_for(vocabulary: { tokens: [], enabled: true })).to eq([:shared])
    end

    it "returns [] when the app opts out with enabled:false" do
      expect(described_class.tokens_for(vocabulary: { tokens: [], enabled: false })).to eq([])
    end

    it "honors string-keyed settings (Rack/serialization tolerance)" do
      expect(described_class.tokens_for("vocabulary" => { "enabled" => false })).to eq([])
      expect(described_class.tokens_for("vocabulary" => { "tokens" => ["shared"] })).to eq([:shared])
    end

    it "filters unknown declared tokens but keeps the :shared default" do
      expect(described_class.tokens_for(vocabulary: { tokens: [:bogus] })).to eq([:shared])
    end
  end

  describe ".builtin?" do
    it "is true for a known token (symbol or string)" do
      expect(described_class.builtin?(:shared)).to be(true)
      expect(described_class.builtin?("shared")).to be(true)
    end

    it "is false for an unknown token" do
      expect(described_class.builtin?(:nope)).to be(false)
    end
  end

  describe ".builtin_names" do
    it "returns the registry keys" do
      expect(described_class.builtin_names).to include(:shared)
      expect(described_class.builtin_names).to all(be_a(Symbol))
    end
  end
end
