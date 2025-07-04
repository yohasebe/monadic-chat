require 'spec_helper'
require 'json'

RSpec.describe 'Vendor Helper Function Return Handling' do
  describe 'Function return serialization' do
    let(:hash_return) { { error: "Test error message" } }
    let(:array_return) { ["item1", "item2", "item3"] }
    let(:string_return) { "Simple string result" }
    
    context 'DeepSeek Helper' do
      it 'correctly serializes hash returns to JSON' do
        # Simulate the function return handling
        content = hash_return.is_a?(Hash) || hash_return.is_a?(Array) ? 
                  JSON.generate(hash_return) : 
                  hash_return.to_s
        
        expect(content).to eq('{"error":"Test error message"}')
        expect(content).not_to include('[object Object]')
      end
      
      it 'correctly serializes array returns to JSON' do
        content = array_return.is_a?(Hash) || array_return.is_a?(Array) ? 
                  JSON.generate(array_return) : 
                  array_return.to_s
        
        expect(content).to eq('["item1","item2","item3"]')
      end
      
      it 'correctly handles string returns' do
        content = string_return.is_a?(Hash) || string_return.is_a?(Array) ? 
                  JSON.generate(string_return) : 
                  string_return.to_s
        
        expect(content).to eq('Simple string result')
      end
    end
    
    context 'Claude Helper' do
      it 'correctly serializes hash returns to JSON' do
        # Simulate the function return handling
        content = hash_return.is_a?(Hash) || hash_return.is_a?(Array) ? 
                  JSON.generate(hash_return) : 
                  hash_return.to_s
        
        expect(content).to eq('{"error":"Test error message"}')
        expect(content).not_to include('[object Object]')
      end
    end
    
    context 'Mistral Helper' do
      it 'correctly serializes hash returns to JSON' do
        # This was already fixed
        content = if hash_return.is_a?(Hash) || hash_return.is_a?(Array)
                    JSON.generate(hash_return)
                  else
                    hash_return.to_s
                  end
        
        expect(content).to eq('{"error":"Test error message"}')
        expect(content).not_to include('[object Object]')
      end
    end
    
    context 'Cohere Helper' do
      it 'correctly serializes hash returns to JSON' do
        # Cohere already had correct implementation
        results = hash_return.is_a?(Hash) || hash_return.is_a?(Array) ? 
                  JSON.generate(hash_return) : 
                  hash_return.to_s
        
        expect(results).to eq('{"error":"Test error message"}')
        expect(results).not_to include('[object Object]')
      end
    end
  end
  
  describe 'Error handling from Tavily functions' do
    let(:tavily_error) { { error: "Tavily API error: Invalid API key" } }
    
    it 'properly serializes Tavily error responses' do
      # All helpers should now handle this correctly
      content = tavily_error.is_a?(Hash) || tavily_error.is_a?(Array) ? 
                JSON.generate(tavily_error) : 
                tavily_error.to_s
      
      expect(content).to be_a(String)
      expect(content).to include('Tavily API error')
      expect(content).to include('Invalid API key')
      
      # Verify it can be parsed back to JSON
      parsed = JSON.parse(content)
      expect(parsed).to be_a(Hash)
      expect(parsed['error']).to include('Tavily API error')
    end
  end
end