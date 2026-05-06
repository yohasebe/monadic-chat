# frozen_string_literal: true

require 'spec_helper'
require 'monadic/utils/privacy/pipeline'
require 'monadic/utils/privacy/types'
require 'monadic/utils/privacy/registry'

RSpec.describe Monadic::Utils::Privacy::Pipeline do
  let(:fake_backend) do
    double('Backend').tap do |b|
      allow(b).to receive(:anonymize).and_return(
        masked_text: 'masked', registry: {}, entities: [], stats: {}
      )
    end
  end

  let(:session) { {} }

  def build(config)
    described_class.new(backend: fake_backend, config: config, session: session)
  end

  describe 'mask_types → entity_types translation' do
    it 'maps DSL symbols to Presidio canonical entity strings' do
      pipeline = build(enabled: true, mask_types: [:person, :email, :phone])
      raw = Monadic::Utils::Privacy::RawMessage.new('Email Alice', 'user', {})
      pipeline.before_send_to_llm(raw)

      expect(fake_backend).to have_received(:anonymize).with(
        hash_including(entity_types: %w[PERSON EMAIL_ADDRESS PHONE_NUMBER])
      )
    end

    it 'maps :organization to ORGANIZATION but skips :address (LOCATION)' do
      pipeline = build(enabled: true, mask_types: [:person, :organization])
      raw = Monadic::Utils::Privacy::RawMessage.new('hi', 'user', {})
      pipeline.before_send_to_llm(raw)

      expect(fake_backend).to have_received(:anonymize).with(
        hash_including(entity_types: %w[PERSON ORGANIZATION])
      )
    end

    it 'sends nil entity_types when mask_types is empty (backend keeps legacy behavior)' do
      pipeline = build(enabled: true, mask_types: [])
      raw = Monadic::Utils::Privacy::RawMessage.new('hi', 'user', {})
      pipeline.before_send_to_llm(raw)

      expect(fake_backend).to have_received(:anonymize).with(
        hash_including(entity_types: nil)
      )
    end

    it 'sends nil entity_types when mask_types is unset' do
      pipeline = build(enabled: true)
      raw = Monadic::Utils::Privacy::RawMessage.new('hi', 'user', {})
      pipeline.before_send_to_llm(raw)

      expect(fake_backend).to have_received(:anonymize).with(
        hash_including(entity_types: nil)
      )
    end

    it 'silently drops unknown symbols (no canonical mapping)' do
      pipeline = build(enabled: true, mask_types: [:person, :totally_made_up])
      raw = Monadic::Utils::Privacy::RawMessage.new('hi', 'user', {})
      pipeline.before_send_to_llm(raw)

      expect(fake_backend).to have_received(:anonymize).with(
        hash_including(entity_types: %w[PERSON])
      )
    end
  end

  describe 'PRESIDIO_TYPE_MAP completeness' do
    it 'covers every symbol in PrivacyFilterConfiguration::ALLOWED_TYPES' do
      require 'monadic/dsl/configurations'
      missing = MonadicDSL::PrivacyFilterConfiguration::ALLOWED_TYPES - Monadic::Utils::Privacy::PRESIDIO_TYPE_MAP.keys
      expect(missing).to be_empty,
        "Symbols allowed in DSL but not mapped to Presidio canonical: #{missing}"
    end
  end

  describe 'language resolution from session conversation_language' do
    def build_with_session(session_hash)
      described_class.new(backend: fake_backend, config: { enabled: true }, session: session_hash)
    end

    let(:raw) { Monadic::Utils::Privacy::RawMessage.new('hi', 'user', {}) }

    it 'defaults to ["en"] when session has no parameters' do
      build({ enabled: true }).before_send_to_llm(raw)
      expect(fake_backend).to have_received(:anonymize).with(hash_including(languages: ['en']))
    end

    it 'maps "auto" to ["en"]' do
      build_with_session(parameters: { 'conversation_language' => 'auto' }).before_send_to_llm(raw)
      expect(fake_backend).to have_received(:anonymize).with(hash_including(languages: ['en']))
    end

    it 'passes through Japanese (ja) when sidebar selects it' do
      build_with_session(parameters: { 'conversation_language' => 'ja' }).before_send_to_llm(raw)
      expect(fake_backend).to have_received(:anonymize).with(hash_including(languages: ['ja']))
    end

    it 'passes through every language Presidio supports' do
      %w[en de es fr it ja nl pt zh].each do |code|
        backend = double('Backend').tap do |b|
          allow(b).to receive(:anonymize).and_return(masked_text: 'x', registry: {}, entities: [], stats: {})
        end
        described_class.new(backend: backend, config: { enabled: true },
                            session: { parameters: { 'conversation_language' => code } })
                       .before_send_to_llm(raw)
        expect(backend).to have_received(:anonymize).with(hash_including(languages: [code]))
      end
    end

    it 'falls back to ["en"] when sidebar language is outside Presidio support (e.g. Korean)' do
      build_with_session(parameters: { 'conversation_language' => 'ko' }).before_send_to_llm(raw)
      expect(fake_backend).to have_received(:anonymize).with(hash_including(languages: ['en']))
    end

    it 'reads symbol-keyed parameters as well (Rack::Session quirk)' do
      build_with_session(parameters: { conversation_language: 'de' }).before_send_to_llm(raw)
      expect(fake_backend).to have_received(:anonymize).with(hash_including(languages: ['de']))
    end
  end
end
