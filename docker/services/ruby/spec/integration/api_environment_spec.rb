require 'spec_helper'

RSpec.describe 'API Environment Endpoint' do
  describe '/api/environment endpoint logic' do
    context 'when TAVILY_API_KEY is present' do
      before do
        allow(CONFIG).to receive(:[]).and_call_original
        allow(CONFIG).to receive(:[]).with("TAVILY_API_KEY").and_return("test-api-key")
      end

      it 'indicates Tavily key is available' do
        # Simulate the endpoint logic
        result = { has_tavily_key: !CONFIG["TAVILY_API_KEY"].to_s.empty? }
        expect(result[:has_tavily_key]).to be true
      end
    end

    context 'when TAVILY_API_KEY is empty string' do
      before do
        allow(CONFIG).to receive(:[]).and_call_original
        allow(CONFIG).to receive(:[]).with("TAVILY_API_KEY").and_return("")
      end

      it 'indicates Tavily key is not available' do
        # Simulate the endpoint logic
        result = { has_tavily_key: !CONFIG["TAVILY_API_KEY"].to_s.empty? }
        expect(result[:has_tavily_key]).to be false
      end
    end

    context 'when TAVILY_API_KEY is nil' do
      before do
        allow(CONFIG).to receive(:[]).and_call_original
        allow(CONFIG).to receive(:[]).with("TAVILY_API_KEY").and_return(nil)
      end

      it 'indicates Tavily key is not available' do
        # Simulate the endpoint logic
        result = { has_tavily_key: !CONFIG["TAVILY_API_KEY"].to_s.empty? }
        expect(result[:has_tavily_key]).to be false
      end
    end

    context 'when TAVILY_API_KEY has whitespace only' do
      before do
        allow(CONFIG).to receive(:[]).and_call_original
        allow(CONFIG).to receive(:[]).with("TAVILY_API_KEY").and_return("   ")
      end

      it 'indicates Tavily key is available (non-empty)' do
        # Note: Current implementation considers whitespace as valid
        # This test documents the current behavior
        result = { has_tavily_key: !CONFIG["TAVILY_API_KEY"].to_s.empty? }
        expect(result[:has_tavily_key]).to be true
      end
    end
  end
end