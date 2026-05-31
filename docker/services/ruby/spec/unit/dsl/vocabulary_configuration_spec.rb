# frozen_string_literal: true

require_relative "../../spec_helper"
require "monadic/dsl/configurations"

RSpec.describe MonadicDSL::VocabularyConfiguration do
  def config(&block)
    cfg = described_class.new
    cfg.instance_eval(&block) if block_given?
    cfg
  end

  describe "#use (explicit built-in tokens)" do
    it "collects a single built-in token (enabled by default)" do
      cfg = config { use :shared }
      expect(cfg.to_hash).to eq(tokens: [:shared], enabled: true)
    end

    it "normalizes string names to symbols" do
      cfg = config { use "shared" }
      expect(cfg.to_hash).to eq(tokens: [:shared], enabled: true)
    end

    it "deduplicates repeated tokens" do
      cfg = config do
        use :shared
        use :shared
      end
      expect(cfg.to_hash).to eq(tokens: [:shared], enabled: true)
    end

    it "raises ArgumentError on an unknown token (typo fails fast)" do
      expect { config { use :shred } }.to raise_error(ArgumentError, /Unknown vocabulary token/)
    end

    it "names the known built-ins in the error message" do
      expect { config { use :nope } }.to raise_error(ArgumentError, /shared/)
    end
  end

  describe "#disable! (vocabulary false opt-out)" do
    it "marks the config disabled with no tokens" do
      cfg = config(&:disable!)
      expect(cfg.to_hash).to eq(tokens: [], enabled: false)
    end
  end

  describe "#to_hash" do
    it "defaults to enabled with no explicit tokens" do
      expect(config.to_hash).to eq(tokens: [], enabled: true)
    end

    it "produces plain data (no Proc) so it survives the .inspect class generator" do
      hash = config { use :shared }.to_hash
      # Round-trips through inspect/eval the way dsl.rb serializes app settings.
      restored = eval(hash.inspect) # rubocop:disable Security/Eval
      expect(restored).to eq(hash)
      expect(hash[:tokens]).to all(be_a(Symbol))
    end
  end
end
