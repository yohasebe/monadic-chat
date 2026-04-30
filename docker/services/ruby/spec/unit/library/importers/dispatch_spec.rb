# frozen_string_literal: true

require 'spec_helper'
require 'monadic/library'

RSpec.describe Monadic::Library::Importers, '.dispatch / .detect' do
  let(:schema) { Monadic::Library::Schema }

  it 'dispatches a Monadic Chat export to MonadicChatExport' do
    input = {
      'parameters' => { 'app_name' => 'ChatOpenAI' },
      'messages' => [{ 'role' => 'user', 'text' => 'hi' }]
    }
    expect(described_class.detect(input)).to eq(Monadic::Library::Importers::MonadicChatExport)
    result = described_class.dispatch(input)
    expect(schema.valid?(result)).to be true
  end

  it 'dispatches a TED transcript to TedTalk' do
    input = [{ 'text' => 'opening line', 'start' => 0.0, 'duration' => 2.0 }]
    expect(described_class.detect(input)).to eq(Monadic::Library::Importers::TedTalk)
  end

  it 'dispatches Gemini contents to GeminiContents' do
    input = { 'contents' => [{ 'role' => 'user', 'parts' => [{ 'text' => 'hi' }] }] }
    expect(described_class.detect(input)).to eq(Monadic::Library::Importers::GeminiContents)
  end

  it 'dispatches Anthropic-shaped messages to AnthropicMessages' do
    input = { 'system' => 'be brief', 'messages' => [{ 'role' => 'user', 'content' => 'hi' }] }
    expect(described_class.detect(input)).to eq(Monadic::Library::Importers::AnthropicMessages)
  end

  it 'falls back to ChatML for a generic messages array with mixed roles' do
    input = [
      { 'role' => 'system', 'content' => 'be brief' },
      { 'role' => 'user', 'content' => 'hi' }
    ]
    expect(described_class.detect(input)).to eq(Monadic::Library::Importers::ChatML)
  end

  it 'dispatches plain text with speaker labels to PlainText' do
    input = "Alice: Hello\nBob: Hi"
    expect(described_class.detect(input)).to eq(Monadic::Library::Importers::PlainText)
  end

  it 'returns nil from detect for unrecognisable input' do
    expect(described_class.detect({ 'random' => 'shape' })).to be_nil
  end

  it 'raises from dispatch for unrecognisable input' do
    expect { described_class.dispatch({ 'random' => 'shape' }) }
      .to raise_error(ArgumentError, /No registered importer/)
  end
end
