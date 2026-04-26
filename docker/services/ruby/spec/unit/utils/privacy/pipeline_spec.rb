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
end
