# frozen_string_literal: true

require "spec_helper"
require "monadic/substitution/registry"

RSpec.describe Monadic::Substitution::Registry do
  # Minimal stub providers that respond to #token_names and #name.
  let(:stub_provider) do
    Class.new do
      attr_reader :token_names, :name
      def initialize(names, label)
        @token_names = names
        @name = label
      end
    end
  end

  describe ".validate_builtins!" do
    it "returns true for the real BUILTINS (invariant guard)" do
      expect(described_class.validate_builtins!).to be true
    end
  end

  describe ".privacy_token?" do
    it "is true for Privacy placeholder inner-names" do
      expect(described_class.privacy_token?("PERSON_1")).to be true
      expect(described_class.privacy_token?("EMAIL_12")).to be true
    end

    it "is false for vocabulary token names" do
      expect(described_class.privacy_token?("SHARED")).to be false
      expect(described_class.privacy_token?("MODEL")).to be false
      expect(described_class.privacy_token?("LAST_IMAGE")).to be false
    end
  end

  describe ".reserved?" do
    it "is true for built-in vocabulary tokens" do
      %w[SHARED TODAY MODEL APP LANG].each do |name|
        expect(described_class.reserved?(name)).to be true
      end
    end

    it "is true for Privacy placeholders" do
      expect(described_class.reserved?("PERSON_1")).to be true
    end

    it "is false for an unused name" do
      expect(described_class.reserved?("ZZZ")).to be false
    end
  end

  describe ".builtin_tokens" do
    it "includes the five built-in names" do
      expect(described_class.builtin_tokens).to include("SHARED", "TODAY", "MODEL", "APP", "LANG")
    end
  end

  describe ".assert_no_collision!" do
    it "raises when two providers report overlapping token_names" do
      a = stub_provider.new(%w[MODEL TODAY], "alpha")
      b = stub_provider.new(%w[TODAY LANG], "beta")
      expect do
        described_class.assert_no_collision!([a], b)
      end.to raise_error(Monadic::Substitution::TokenCollisionError, /TODAY/)
    end

    it "does not raise for disjoint token_names" do
      a = stub_provider.new(%w[MODEL], "alpha")
      b = stub_provider.new(%w[TODAY], "beta")
      expect do
        described_class.assert_no_collision!([a], b)
      end.not_to raise_error
    end

    it "does not raise when the incoming provider returns []" do
      a = stub_provider.new(%w[MODEL], "alpha")
      b = stub_provider.new([], "beta")
      expect do
        described_class.assert_no_collision!([a], b)
      end.not_to raise_error
    end

    it "does not raise when an existing provider returns []" do
      a = stub_provider.new([], "alpha")
      b = stub_provider.new(%w[MODEL], "beta")
      expect do
        described_class.assert_no_collision!([a], b)
      end.not_to raise_error
    end
  end
end
