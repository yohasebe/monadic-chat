# frozen_string_literal: true

require 'spec_helper'
require 'monadic/library'

RSpec.describe Monadic::Library::Importers::MonadicChatExport do
  let(:schema) { Monadic::Library::Schema }

  let(:export_payload) do
    {
      'parameters' => {
        'app_name' => 'ChatOpenAI',
        'model' => 'gpt-5.4',
        'temperature' => 0.7
      },
      'messages' => [
        { 'role' => 'system', 'text' => 'Be brief.', 'mid' => 'm-001' },
        { 'role' => 'user', 'text' => 'Hello', 'mid' => 'm-002' },
        { 'role' => 'assistant', 'text' => 'Hi.', 'mid' => 'm-003',
          'thinking' => 'Let me think...' }
      ]
    }
  end

  describe '.can_import?' do
    it 'recognises the parameters + messages shape' do
      expect(described_class.can_import?(export_payload)).to be true
    end

    it 'rejects raw arrays (those are ChatML)' do
      expect(described_class.can_import?([{ 'role' => 'user', 'text' => 'hi' }])).to be false
    end

    it 'rejects shapes without "parameters"' do
      expect(described_class.can_import?({ 'messages' => export_payload['messages'] })).to be false
    end
  end

  describe '.import' do
    it 'produces a valid v1 conversation' do
      result = described_class.import(export_payload)
      expect(schema.valid?(result)).to be true
    end

    it 'preserves mid as the message id' do
      result = described_class.import(export_payload)
      expect(result['messages'].map { |m| m['id'] }).to eq(%w[m-001 m-002 m-003])
    end

    it 'attaches provider/model metadata to assistant messages only' do
      result = described_class.import(export_payload)
      asst = result['messages'].find { |m| m['id'] == 'm-003' }
      user = result['messages'].find { |m| m['id'] == 'm-002' }
      expect(asst.dig('metadata', 'provider')).to eq('openai')
      expect(asst.dig('metadata', 'model')).to eq('gpt-5.4')
      expect(user['metadata']).to be_nil # user has no thinking/images
    end

    it 'preserves thinking content on assistant messages' do
      result = described_class.import(export_payload)
      asst = result['messages'].find { |m| m['id'] == 'm-003' }
      expect(asst.dig('metadata', 'thinking')).to eq('Let me think...')
    end

    it 'guesses provider from app_name suffix' do
      claude_payload = export_payload.merge(
        'parameters' => { 'app_name' => 'ChatPlusClaude', 'model' => 'claude-sonnet-4-6' }
      )
      result = described_class.import(claude_payload)
      asst = result['messages'].find { |m| m['id'] == 'm-003' }
      expect(asst.dig('metadata', 'provider')).to eq('anthropic')
    end

    it 'uses app_name as default title in conversation_metadata' do
      result = described_class.import(export_payload)
      expect(result.dig('conversation_metadata', 'title')).to eq('ChatOpenAI')
    end

    it 'allows the caller to override license / language' do
      result = described_class.import(export_payload, license: 'CC-BY-4.0', language: 'ja')
      meta = result['conversation_metadata']
      expect(meta['license']).to eq('CC-BY-4.0')
      expect(meta['language']).to eq('ja')
    end
  end
end
