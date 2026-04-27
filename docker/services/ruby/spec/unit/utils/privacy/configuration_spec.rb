# frozen_string_literal: true

require 'monadic/dsl/configurations'

RSpec.describe MonadicDSL::PrivacyFilterConfiguration do
  it "starts disabled with English only" do
    h = described_class.new.to_hash
    expect(h[:enabled]).to be false
    expect(h[:languages]).to eq(["en"])
    expect(h[:on_failure]).to eq(:block)
    expect(h[:score_threshold]).to eq(0.4)
    expect(h[:honorific_trim]).to be true
  end

  it "accepts the full DSL via instance_eval" do
    config = described_class.new
    config.instance_eval do
      enabled true
      languages ["ja", "en"]
      mask_types [:person, :email]
      score_threshold 0.6
      honorific_trim false
      on_failure :pass
    end
    h = config.to_hash
    expect(h[:enabled]).to be true
    expect(h[:languages]).to eq(["ja", "en"])
    expect(h[:mask_types]).to eq([:person, :email])
    expect(h[:score_threshold]).to eq(0.6)
    expect(h[:honorific_trim]).to be false
    expect(h[:on_failure]).to eq(:pass)
  end

  it "rejects unknown mask_types" do
    config = described_class.new
    expect { config.mask_types([:not_a_real_type]) }.to raise_error(ArgumentError, /Unknown mask_types/)
  end

  it "rejects out-of-range score_threshold" do
    config = described_class.new
    expect { config.score_threshold(1.5) }.to raise_error(ArgumentError, /between 0 and 1/)
    expect { config.score_threshold(-0.1) }.to raise_error(ArgumentError, /between 0 and 1/)
  end

  it "rejects unknown on_failure modes" do
    config = described_class.new
    expect { config.on_failure(:explode) }.to raise_error(ArgumentError, /on_failure must be one of/)
  end

  it "default mask_types excludes :address (LOCATION) but includes :organization" do
    h = described_class.new.to_hash
    expect(h[:mask_types]).to include(:person, :organization, :email)
    expect(h[:mask_types]).not_to include(:address)
  end

  it "default mask_types contains DEFAULT_MASK_TYPES" do
    h = described_class.new.to_hash
    expect(h[:mask_types]).to eq(described_class::DEFAULT_MASK_TYPES.dup)
  end

  it "accepts :address as an explicit opt-in for LOCATION masking" do
    config = described_class.new
    config.mask_types([:person, :address])
    expect(config.to_hash[:mask_types]).to eq([:person, :address])
  end
end
