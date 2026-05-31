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

    it "includes the tier-1 stateful tokens" do
      expect(described_class::BUILTINS[:today][:token]).to eq("TODAY")
      expect(described_class::BUILTINS[:model][:token]).to eq("MODEL")
      expect(described_class::BUILTINS[:app][:token]).to eq("APP")
      expect(described_class::BUILTINS[:lang][:token]).to eq("LANG")
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

    it "carries a per-token :display mode (decision E)" do
      described_class::BUILTINS.each_value do |meta|
        expect(%i[decorate expand]).to include(meta[:display]),
          "vocabulary token #{meta[:token].inspect} :display must be :decorate or :expand"
      end
    end

    it "tags ${SHARED} as :decorate (path-like) and value tokens as :expand" do
      expect(described_class::BUILTINS[:shared][:display]).to eq(:decorate)
      expect(described_class::BUILTINS[:today][:display]).to eq(:expand)
      expect(described_class::BUILTINS[:model][:display]).to eq(:expand)
      expect(described_class::BUILTINS[:app][:display]).to eq(:expand)
      expect(described_class::BUILTINS[:lang][:display]).to eq(:expand)
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
    it "defaults to DEFAULT_TOKENS when the app has no vocabulary config" do
      expect(described_class.tokens_for(nil)).to eq(described_class::DEFAULT_TOKENS)
      expect(described_class.tokens_for({})).to eq(described_class::DEFAULT_TOKENS)
    end

    it "defaults to DEFAULT_TOKENS for an empty vocabulary block" do
      expect(described_class.tokens_for(vocabulary: { tokens: [], enabled: true }))
        .to eq(described_class::DEFAULT_TOKENS)
    end

    it "returns [] when the app opts out with enabled:false" do
      expect(described_class.tokens_for(vocabulary: { tokens: [], enabled: false })).to eq([])
    end

    it "honors string-keyed settings (Rack/serialization tolerance)" do
      expect(described_class.tokens_for("vocabulary" => { "enabled" => false })).to eq([])
      expect(described_class.tokens_for("vocabulary" => { "tokens" => ["shared"] }))
        .to eq(described_class::DEFAULT_TOKENS)
    end

    it "filters unknown declared tokens but keeps the defaults" do
      expect(described_class.tokens_for(vocabulary: { tokens: [:bogus] }))
        .to eq(described_class::DEFAULT_TOKENS)
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

  describe ".current_model" do
    it "reads the model from string-keyed parameters" do
      session = { parameters: { "model" => "gpt-x" } }
      expect(described_class.current_model(session)).to eq("gpt-x")
    end

    it "returns nil when parameters are missing" do
      expect(described_class.current_model({})).to be_nil
    end
  end

  describe ".conversation_language" do
    it "falls back to ui_language when conversation_language is auto" do
      session = { parameters: { "conversation_language" => "auto", "ui_language" => "ja" } }
      expect(described_class.conversation_language(session)).to eq("ja")
    end

    it "returns the explicit conversation language" do
      session = { parameters: { "conversation_language" => "fr", "ui_language" => "ja" } }
      expect(described_class.conversation_language(session)).to eq("fr")
    end

    it "returns nil when only auto is known" do
      session = { parameters: { "conversation_language" => "auto" } }
      expect(described_class.conversation_language(session)).to be_nil
    end
  end

  describe ".current_app_display_name" do
    it "returns the raw app_name when APPS lookup is unavailable" do
      session = { parameters: { "app_name" => "ChatOpenAI" } }
      expect(described_class.current_app_display_name(session)).to eq("ChatOpenAI")
    end

    it "returns nil when app_name is missing" do
      expect(described_class.current_app_display_name({ parameters: {} })).to be_nil
    end
  end
end
