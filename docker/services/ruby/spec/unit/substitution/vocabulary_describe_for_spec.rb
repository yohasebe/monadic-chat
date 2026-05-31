# frozen_string_literal: true

require 'spec_helper'
require 'monadic/substitution/vocabulary'

# Specs for the SSOT method backing the Web UI "Available Variables" panel.
RSpec.describe Monadic::Substitution::Vocabulary, '.describe_for' do
  # A session whose params let the stateful resolvers (MODEL/LANG) produce
  # values, so we can assert those too.
  let(:session) do
    {
      parameters: {
        "model" => "gpt-5.4",
        "app_name" => "Chat",
        "conversation_language" => "English"
      }
    }
  end

  # Default app (no `vocabulary` settings) → all DEFAULT_TOKENS enabled.
  let(:default_settings) { {} }

  subject(:entries) { described_class.describe_for(session, default_settings) }

  it 'returns one entry per enabled default token' do
    expect(entries.map { |e| e[:token] }).to contain_exactly(
      "SHARED", "TODAY", "MODEL", "APP", "LANG"
    )
  end

  it 'includes the token, description, display and value keys' do
    entries.each do |e|
      expect(e.keys).to include(:token, :description, :display, :value)
      expect(e[:description]).to be_a(String).and(be_present_string)
    end
  end

  it 'sources descriptions from BUILTINS (no duplication)' do
    today = entries.find { |e| e[:token] == "TODAY" }
    expect(today[:description]).to eq(
      described_class::BUILTINS[:today][:description]
    )
  end

  it 'marks SHARED as display "decorate" and TODAY as "expand"' do
    shared = entries.find { |e| e[:token] == "SHARED" }
    today  = entries.find { |e| e[:token] == "TODAY" }
    expect(shared[:display]).to eq("decorate")
    expect(today[:display]).to eq("expand")
  end

  it 'resolves session-independent and session-dependent values' do
    today = entries.find { |e| e[:token] == "TODAY" }
    model = entries.find { |e| e[:token] == "MODEL" }
    lang  = entries.find { |e| e[:token] == "LANG" }
    expect(today[:value]).to eq(Date.today.to_s)
    expect(model[:value]).to eq("gpt-5.4")
    expect(lang[:value]).to eq("English")
  end

  context 'when a token resolves to nil (unavailable in this context)' do
    # No params at all → MODEL/LANG/APP resolvers return nil, but the tokens
    # must still be listed (value nil), so the user knows they exist.
    let(:session) { { parameters: {} } }

    it 'still lists the token with a nil value' do
      model = entries.find { |e| e[:token] == "MODEL" }
      expect(model).not_to be_nil
      expect(model[:value]).to be_nil
    end
  end

  context 'when a resolver raises' do
    # Override the module method the MODEL resolver delegates to so it raises;
    # describe_for must swallow it (defensive) and yield a nil value. We patch
    # the real singleton method (and restore it) rather than using a partial
    # double, because the failure_mode here is "must never propagate".
    around do |example|
      original = described_class.method(:current_model)
      described_class.define_singleton_method(:current_model) { |_s| raise "boom" }
      begin
        example.run
      ensure
        described_class.define_singleton_method(:current_model, original)
      end
    end

    it 'yields a nil value rather than breaking the panel' do
      model = entries.find { |e| e[:token] == "MODEL" }
      expect(model).not_to be_nil
      expect(model[:value]).to be_nil
    end
  end

  context 'when the app opts out via `vocabulary false`' do
    let(:opt_out_settings) { { "vocabulary" => { "enabled" => false } } }

    it 'returns an empty array' do
      expect(described_class.describe_for(session, opt_out_settings)).to eq([])
    end
  end

  # Small custom matcher so the description assertion above reads cleanly
  # without pulling in rspec-rails' `be_present`.
  matcher :be_present_string do
    match { |actual| actual.is_a?(String) && !actual.strip.empty? }
  end
end
