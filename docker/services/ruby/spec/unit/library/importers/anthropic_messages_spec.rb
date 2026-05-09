# frozen_string_literal: true

require 'spec_helper'
require 'monadic/library'

RSpec.describe Monadic::Library::Importers::AnthropicMessages do
  let(:schema) { Monadic::Library::Schema }

  describe '.can_import?' do
    it 'recognises a request body with system+messages' do
      input = {
        'system' => 'You are a coder.',
        'messages' => [
          { 'role' => 'user', 'content' => 'Write hello world' }
        ]
      }
      expect(described_class.can_import?(input)).to be true
    end

    it 'rejects ChatML-only "system" role messages' do
      # Anthropic doesn't put system inside messages
      expect(described_class.can_import?([
        { 'role' => 'system', 'content' => 'Be brief' }
      ])).to be false
    end
  end

  describe '.import' do
    it 'produces a valid v1 conversation when given a request body' do
      input = {
        'system' => 'You are a friendly assistant.',
        'messages' => [
          { 'role' => 'user', 'content' => 'Hi.' },
          { 'role' => 'assistant', 'content' => [
            { 'type' => 'text', 'text' => 'Hello there.' }
          ]}
        ]
      }
      result = described_class.import(input)
      expect(schema.valid?(result)).to be true
      expect(result['messages'].size).to eq(3) # system + user + assistant
      expect(result['messages'].first['text']).to eq('You are a friendly assistant.')
      expect(result['messages'].last['text']).to eq('Hello there.')
    end

    it 'omits the system message when no system field is provided' do
      input = [
        { 'role' => 'user', 'content' => 'Hi' },
        { 'role' => 'assistant', 'content' => 'Hello' }
      ]
      result = described_class.import(input)
      expect(result['messages'].size).to eq(2)
      expect(result['participants'].map { |p| p['role'] })
        .to contain_exactly('human', 'assistant')
    end
  end
end
