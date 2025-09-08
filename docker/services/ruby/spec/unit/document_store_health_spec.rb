require 'rspec'
require_relative '../../lib/monadic/document_store/openai_vector_store'

RSpec.describe Monadic::DocumentStore::OpenAIVectorStore do
  let(:store) { described_class.new }

  context 'health' do
    it 'returns healthy: false when API key is missing' do
      original = defined?(CONFIG) ? CONFIG['OPENAI_API_KEY'] : nil
      CONFIG['OPENAI_API_KEY'] = nil if defined?(CONFIG)
      begin
        result = store.health
        expect(result).to be_a(Hash)
        expect(result[:healthy]).to eq(false)
      ensure
        CONFIG['OPENAI_API_KEY'] = original if defined?(CONFIG)
      end
    end

    it 'returns healthy: true when API key is present' do
      original = defined?(CONFIG) ? CONFIG['OPENAI_API_KEY'] : nil
      CONFIG['OPENAI_API_KEY'] = 'sk-xxxx' if defined?(CONFIG)
      begin
        result = store.health
        expect(result[:healthy]).to eq(true)
      ensure
        CONFIG['OPENAI_API_KEY'] = original if defined?(CONFIG)
      end
    end
  end
end
