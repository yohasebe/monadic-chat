# frozen_string_literal: true

require 'spec_helper'
require 'monadic/library'

RSpec.describe Monadic::Library::Importers::GeminiContents do
  let(:schema) { Monadic::Library::Schema }

  describe '.can_import?' do
    it 'recognises Gemini "contents" arrays with parts' do
      expect(described_class.can_import?([
        { 'role' => 'user', 'parts' => [{ 'text' => 'Hello' }] },
        { 'role' => 'model', 'parts' => [{ 'text' => 'Hi' }] }
      ])).to be true
    end

    it 'rejects ChatML-style content (no parts)' do
      expect(described_class.can_import?([
        { 'role' => 'user', 'content' => 'Hello' }
      ])).to be false
    end
  end

  describe '.import' do
    it 'maps user/model roles to human/assistant' do
      input = {
        'contents' => [
          { 'role' => 'user',  'parts' => [{ 'text' => 'Hi' }] },
          { 'role' => 'model', 'parts' => [{ 'text' => 'Hello' }] }
        ]
      }
      result = described_class.import(input)
      expect(schema.valid?(result)).to be true
      expect(result['participants'].map { |p| p['role'] })
        .to contain_exactly('human', 'assistant')
    end

    it 'concatenates multi-part text with newlines' do
      input = [
        { 'role' => 'user', 'parts' => [
          { 'text' => 'Line 1' },
          { 'text' => 'Line 2' }
        ]}
      ]
      result = described_class.import(input)
      expect(result['messages'].first['text']).to eq("Line 1\nLine 2")
    end

    it 'prepends system_instruction as a system message' do
      input = {
        'system_instruction' => { 'parts' => [{ 'text' => 'Be concise.' }] },
        'contents' => [
          { 'role' => 'user', 'parts' => [{ 'text' => 'Hi' }] }
        ]
      }
      result = described_class.import(input)
      expect(result['messages'].size).to eq(2)
      expect(result['messages'].first['text']).to eq('Be concise.')
      roles = result['participants'].map { |p| p['role'] }
      expect(roles).to include('system', 'human')
    end
  end
end
