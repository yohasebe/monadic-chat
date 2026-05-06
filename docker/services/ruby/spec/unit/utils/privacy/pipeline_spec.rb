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

    it 'uses LanguageDetector lock when conversation_language is "auto"' do
      session_hash = {
        parameters: { 'conversation_language' => 'auto' },
        monadic_state: {
          privacy: {
            registry: {},
            audit: [],
            detection: { language: 'ja', reliable: true, locked: true, attempts: 1 }
          }
        }
      }
      build_with_session(session_hash).before_send_to_llm(raw)
      expect(fake_backend).to have_received(:anonymize).with(hash_including(languages: ['ja']))
    end

    it 'falls back to ["en"] under "auto" when no detection lock exists yet' do
      session_hash = {
        parameters: { 'conversation_language' => 'auto' },
        monadic_state: {
          privacy: {
            registry: {},
            audit: [],
            detection: { language: nil, reliable: nil, locked: false, attempts: 0 }
          }
        }
      }
      build_with_session(session_hash).before_send_to_llm(raw)
      expect(fake_backend).to have_received(:anonymize).with(hash_including(languages: ['en']))
    end

    it 'ignores a locked language that is not in PRESIDIO_LANGS (defensive)' do
      session_hash = {
        parameters: { 'conversation_language' => 'auto' },
        monadic_state: {
          privacy: {
            registry: {},
            audit: [],
            detection: { language: 'ko', reliable: true, locked: true, attempts: 1 }
          }
        }
      }
      build_with_session(session_hash).before_send_to_llm(raw)
      expect(fake_backend).to have_received(:anonymize).with(hash_including(languages: ['en']))
    end
  end

  describe '#after_receive_from_llm' do
    let(:session_with_registry) do
      {
        monadic_state: {
          privacy: {
            registry: {
              '<<PERSON_1>>' => 'Alice',
              '<<EMAIL_ADDRESS_1>>' => 'alice@example.com'
            },
            audit: []
          }
        }
      }
    end

    def pipeline_for(session_hash, enabled: true)
      described_class.new(backend: fake_backend, config: { enabled: enabled }, session: session_hash)
    end

    it 'restores placeholders to their registry values' do
      pipeline = pipeline_for(session_with_registry)
      result = pipeline.after_receive_from_llm('Hello <<PERSON_1>> at <<EMAIL_ADDRESS_1>>.')
      expect(result.text).to eq('Hello Alice at alice@example.com.')
    end

    it 'attaches restored_spans metadata listing each unique substitution' do
      pipeline = pipeline_for(session_with_registry)
      result = pipeline.after_receive_from_llm('Hello <<PERSON_1>>, contact <<EMAIL_ADDRESS_1>>.')
      spans = result.meta[:restored_spans]
      expect(spans).to contain_exactly(
        { placeholder: '<<PERSON_1>>', entity_type: 'PERSON', original: 'Alice' },
        { placeholder: '<<EMAIL_ADDRESS_1>>', entity_type: 'EMAIL_ADDRESS', original: 'alice@example.com' }
      )
    end

    it 'deduplicates spans when the same placeholder appears multiple times' do
      pipeline = pipeline_for(session_with_registry)
      result = pipeline.after_receive_from_llm('<<PERSON_1>> said hi. Then <<PERSON_1>> left.')
      spans = result.meta[:restored_spans]
      expect(spans.length).to eq(1)
      expect(spans.first[:placeholder]).to eq('<<PERSON_1>>')
    end

    it 'records placeholders missing from the registry without halting restoration' do
      pipeline = pipeline_for(session_with_registry)
      result = pipeline.after_receive_from_llm('Hi <<PERSON_1>> and <<UNKNOWN_99>>.')
      expect(result.text).to eq('Hi Alice and <<UNKNOWN_99>>.')
      expect(result.meta[:missing_placeholders]).to eq(['<<UNKNOWN_99>>'])
    end

    it 'is a no-op when the pipeline is disabled' do
      pipeline = pipeline_for(session_with_registry, enabled: false)
      text = 'Hi <<PERSON_1>>.'
      result = pipeline.after_receive_from_llm(text)
      expect(result.text).to eq(text)
      expect(result.meta).to eq({})
    end

    it 'returns an empty restored_spans array when no placeholders are present' do
      pipeline = pipeline_for(session_with_registry)
      result = pipeline.after_receive_from_llm('Plain text without any placeholder tokens.')
      expect(result.meta[:restored_spans]).to eq([])
      expect(result.meta[:missing_placeholders]).to eq([])
    end
  end
end
