require 'spec_helper'
require 'json'

RSpec.describe TavilyHelper do
  let(:test_class) do
    Class.new do
      include TavilyHelper
      
      def initialize
        @config = {}
      end
      
      def CONFIG
        @config
      end
    end
  end
  
  let(:helper) { test_class.new }
  
  describe '#tavily_search' do
    context 'when API key is missing' do
      before do
        helper.instance_variable_get(:@config)["TAVILY_API_KEY"] = nil
      end
      
      it 'returns an error hash' do
        result = helper.tavily_search(query: "test")
        expect(result).to be_a(Hash)
        expect(result[:error]).to include("Tavily API key is not configured")
      end
    end
    
    context 'when API returns an error' do
      before do
        helper.instance_variable_get(:@config)["TAVILY_API_KEY"] = "test-key"
        
        # Mock HTTP response with error
        error_response = double('response',
          status: double('status', success?: false),
          body: '{"error": "Invalid API key", "message": "Authentication failed"}'
        )
        
        allow(HTTP).to receive(:headers).and_return(
          double('http', timeout: double('timeout', post: error_response))
        )
      end
      
      it 'returns an error hash with proper message' do
        result = helper.tavily_search(query: "test")
        expect(result).to be_a(Hash)
        expect(result[:error]).to include("Tavily API error:")
        expect(result[:error]).to include("Invalid API key")
      end
    end
    
    context 'when network error occurs' do
      before do
        helper.instance_variable_get(:@config)["TAVILY_API_KEY"] = "test-key"
        
        # Mock HTTP timeout
        allow(HTTP).to receive(:headers).and_raise(HTTP::TimeoutError.new("Request timed out"))
      end
      
      it 'returns an error hash' do
        result = helper.tavily_search(query: "test")
        expect(result).to be_a(Hash)
        expect(result[:error]).to include("Network error occurred:")
        expect(result[:error]).to include("Request timed out")
      end
    end
  end
end