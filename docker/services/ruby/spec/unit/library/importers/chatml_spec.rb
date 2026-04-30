# frozen_string_literal: true

require 'spec_helper'
require 'monadic/library'

RSpec.describe Monadic::Library::Importers::ChatML do
  let(:schema) { Monadic::Library::Schema }

  describe '.can_import?' do
    it 'recognises a bare messages array' do
      expect(described_class.can_import?([
        { 'role' => 'user', 'content' => 'Hi' },
        { 'role' => 'assistant', 'content' => 'Hello' }
      ])).to be true
    end

    it 'recognises a request body hash' do
      expect(described_class.can_import?(
        'messages' => [{ 'role' => 'user', 'content' => 'Hi' }]
      )).to be true
    end

    it 'rejects unrelated shapes' do
      expect(described_class.can_import?({ 'foo' => 'bar' })).to be false
      expect(described_class.can_import?('plain string')).to be false
    end
  end

  describe '.import' do
    let(:input) do
      [
        { 'role' => 'system', 'content' => 'You are helpful.' },
        { 'role' => 'user', 'content' => 'What is 2+2?' },
        { 'role' => 'assistant', 'content' => '4.' }
      ]
    end

    it 'produces a valid monadic-conversation v1 conversation' do
      result = described_class.import(input, license: 'private')
      expect(schema.valid?(result)).to be true
    end

    it 'maps roles to the broad enum' do
      result = described_class.import(input)
      roles = result['participants'].map { |p| p['role'] }
      expect(roles).to contain_exactly('system', 'human', 'assistant')
    end

    it 'preserves message order and text' do
      result = described_class.import(input)
      texts = result['messages'].map { |m| m['text'] }
      expect(texts).to eq(['You are helpful.', 'What is 2+2?', '4.'])
    end

    it 'extracts text from array-shaped content (typed parts)' do
      multimodal = [
        { 'role' => 'user', 'content' => [
          { 'type' => 'text', 'text' => 'Look at this:' },
          { 'type' => 'image_url', 'image_url' => { 'url' => '...' } },
          { 'type' => 'text', 'text' => 'What is it?' }
        ]}
      ]
      result = described_class.import(multimodal)
      expect(result['messages'].first['text']).to eq("Look at this:\nWhat is it?")
    end
  end
end
