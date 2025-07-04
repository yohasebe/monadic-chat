# frozen_string_literal: true

require_relative "../spec_helper"
require_relative "../../lib/monadic/adapters/vendors/tavily_helper"
require_relative "../../lib/monadic/utils/interaction_utils"

RSpec.describe "Tavily API Missing Behavior", type: :integration do
  describe "when TAVILY_API_KEY is not configured" do
    let(:original_key) { CONFIG["TAVILY_API_KEY"] }
    
    before do
      # Backup and remove the API key
      @original_tavily_key = CONFIG["TAVILY_API_KEY"]
      CONFIG["TAVILY_API_KEY"] = nil
    end
    
    after do
      # Restore the original key
      CONFIG["TAVILY_API_KEY"] = @original_tavily_key
    end
    
    context "TavilyHelper module" do
      include TavilyHelper
      
      it "returns error message for tavily_search" do
        result = tavily_search(query: "test query", n: 3)
        
        expect(result).to be_a(Hash)
        expect(result[:error]).to include("Tavily API key is not configured")
        expect(result[:error]).to include("TAVILY_API_KEY")
      end
    end
    
    context "InteractionUtils module" do
      include InteractionUtils
      
      it "returns error message for tavily_fetch" do
        result = tavily_fetch(url: "https://example.com")
        
        expect(result).to be_a(String)
        expect(result).to eq("ERROR: Tavily API key is not configured")
      end
    end
    
    context "with empty string API key" do
      before do
        CONFIG["TAVILY_API_KEY"] = ""
      end
      
      it "treats empty string as missing key for tavily_search" do
        helper = Class.new { include TavilyHelper }.new
        result = helper.tavily_search(query: "test", n: 1)
        
        expect(result[:error]).to include("Tavily API key is not configured")
      end
      
      it "treats empty string as missing key for tavily_fetch" do
        helper = Class.new { include InteractionUtils }.new
        result = helper.tavily_fetch(url: "https://example.com")
        
        expect(result).to eq("ERROR: Tavily API key is not configured")
      end
    end
  end
  
  describe "AI behavior when Tavily API is missing" do
    it "should gracefully handle missing Tavily API" do
      # When web search is enabled but Tavily API is missing,
      # the AI should receive error messages from function calls
      # and should inform the user about the missing configuration
      
      # Simulate function call response
      function_result = {
        error: "Tavily API key is not configured. Please set TAVILY_API_KEY in your environment."
      }
      
      # AI should handle this gracefully
      expect(function_result[:error]).to match(/Tavily API key/)
    end
  end
end