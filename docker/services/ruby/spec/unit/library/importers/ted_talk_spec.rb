# frozen_string_literal: true

require 'spec_helper'
require 'monadic/library'

RSpec.describe Monadic::Library::Importers::TedTalk do
  let(:schema) { Monadic::Library::Schema }

  # Pre-parsed Ruby array — the simplest shape.
  let(:array_input) do
    [
      { 'text' => 'We are stealing nature from our children.', 'start' => 12.56, 'duration' => 3.28 },
      { 'text' => 'Now, when I say this, I do not mean that we are destroying nature',
        'start' => 16.84, 'duration' => 3.056 },
      { 'text' => 'that they will have wanted us to preserve.',
        'start' => 19.92, 'duration' => 2.376 }
    ]
  end

  # Python repr-of-list form — what tcse stores on disk.
  let(:python_repr) do
    "[{'text': 'We are stealing nature from our children.', 'start': 12.56, 'duration': 3.28}, " \
    "{'text': \"Now, when I say this, I don\\'t mean\", 'start': 16.84, 'duration': 3.056}]"
  end

  describe '.can_import?' do
    it 'recognises a pre-parsed Ruby array' do
      expect(described_class.can_import?(array_input)).to be true
    end

    it 'recognises the Python-repr string form' do
      expect(described_class.can_import?(python_repr)).to be true
    end

    it 'rejects unrelated arrays' do
      expect(described_class.can_import?([{ 'role' => 'user' }])).to be false
    end
  end

  describe '.import' do
    let(:options) do
      {
        external_id: '02551',
        title: 'Nature is everywhere — we just need to learn to see it',
        speaker_label: 'Emma Marris',
        language: 'en',
        license: 'CC-BY-NC-ND-4.0',
        duration_seconds: 1080
      }
    end

    it 'produces a valid v1 conversation from a Ruby array' do
      result = described_class.import(array_input, options)
      expect(schema.valid?(result)).to be true
    end

    it 'maps each segment into a message with timing' do
      result = described_class.import(array_input, options)
      first = result['messages'].first
      expect(first['timing']).to eq('offset_seconds' => 12.56, 'duration_seconds' => 3.28)
      expect(first['text']).to eq('We are stealing nature from our children.')
    end

    it 'creates a single narrator participant with TED label' do
      result = described_class.import(array_input, options)
      expect(result['participants'].size).to eq(1)
      p = result['participants'].first
      expect(p['role']).to eq('narrator')
      expect(p['description']).to eq('TED_speaker')
      expect(p['label']).to eq('Emma Marris')
    end

    it 'fills in conversation_metadata from options' do
      result = described_class.import(array_input, options)
      meta = result['conversation_metadata']
      expect(meta['source']).to eq('ted-talk')
      expect(meta['external_id']).to eq('02551')
      expect(meta['license']).to eq('CC-BY-NC-ND-4.0')
      expect(meta['duration_seconds']).to eq(1080)
    end

    it 'defaults license to CC-BY-NC-ND-4.0 when none provided' do
      result = described_class.import(array_input, title: 'A talk')
      expect(result.dig('conversation_metadata', 'license')).to eq('CC-BY-NC-ND-4.0')
    end

    it 'parses the Python repr-of-list string form' do
      result = described_class.import(python_repr, options)
      expect(schema.valid?(result)).to be true
      expect(result['messages'].size).to eq(2)
      expect(result['messages'].last['text']).to include("don't mean")
    end
  end
end
