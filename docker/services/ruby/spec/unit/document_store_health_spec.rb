require 'rspec'
require_relative '../../../lib/monadic/document_store/openai_vector_store'

RSpec.describe Monadic::DocumentStore::OpenAIVectorStore do
  let(:store) { described_class.new }

  context 'health' do
    it 'returns healthy: false when API key is missing' do
      stub_const('CONFIG', {}) unless defined?(CONFIG)
      result = store.health
      expect(result).to be_a(Hash)
      expect(result[:healthy]).to eq(false)
    end

    it 'returns healthy: true when API key is present' do
      stub_const('CONFIG', { 'OPENAI_API_KEY' => 'sk-xxxx' })
      result = store.health
      expect(result[:healthy]).to eq(true)
    end
  end
end

