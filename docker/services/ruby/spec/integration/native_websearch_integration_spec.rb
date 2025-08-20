# frozen_string_literal: true

require "spec_helper"
require "json"

# Integration tests for native web search features
# Tests real API calls without mocks to ensure functionality
RSpec.describe "Native Web Search Integration", :integration do
  # Skip these tests in CI or when API keys are not available
  before(:all) do
    @skip_openai = !CONFIG["OPENAI_API_KEY"]
    @skip_claude = !CONFIG["ANTHROPIC_API_KEY"]
    @skip_gemini = !CONFIG["GEMINI_API_KEY"]
    @skip_xai = !CONFIG["XAI_API_KEY"]
    @skip_perplexity = !CONFIG["PERPLEXITY_API_KEY"]
  end

  describe "OpenAI Native Web Search" do
    before(:each) do
      skip "OpenAI API key not configured" if @skip_openai
    end

    it "performs web search with gpt-4.1-mini model" do
      require_relative "../../lib/monadic/adapters/vendors/openai_helper"
      
      class TestOpenAI
        include OpenAIHelper
        
        def self.name
          "OpenAI"
        end
        
        # Add missing helper methods
        def markdown_to_html(text, mathjax: false)
          text # Simple passthrough for testing
        end
      end
      
      helper = TestOpenAI.new
      
      # Create a test session
      session = {
        messages: [],
        parameters: {
          "model" => "gpt-4.1-mini",
          "websearch" => true,
          "temperature" => 0.0,
          "max_tokens" => 500,
          "context_size" => 5,
          "app_name" => "test"
        }
      }
      
      # Test message requesting current information
      session[:parameters]["message"] = "What is the current weather in Tokyo? Please provide a brief answer."
      
      responses = []
      helper.api_request("user", session) do |response|
        responses << response
      end
      
      # Verify we got responses
      expect(responses).not_to be_empty
      
      # Check for web search indicators
      web_search_performed = responses.any? do |r|
        r["type"] == "wait" && r["content"]&.include?("SEARCHING WEB")
      end
      
      expect(web_search_performed).to eq(true), "Expected web search to be performed"
      
      # Verify final response contains content
      final_response = responses.find { |r| r["type"] == "assistant" }
      expect(final_response).not_to be_nil
      expect(final_response["content"]["text"]).to include("Tokyo")
    end
  end

  describe "Claude Native Web Search" do
    before(:each) do
      skip "Claude API key not configured" if @skip_claude
    end

    it "performs web search with Claude 3.5 Sonnet" do
      require_relative "../../lib/monadic/adapters/vendors/claude_helper"
      
      class TestClaude
        include ClaudeHelper
        
        def self.name
          "Claude"
        end
        
        # Add missing helper methods
        def markdown_to_html(text, mathjax: false)
          text # Simple passthrough for testing
        end
      end
      
      helper = TestClaude.new
      
      # Create a test session
      session = {
        messages: [],
        parameters: {
          "model" => "claude-3-5-sonnet-latest",
          "websearch" => true,
          "temperature" => 0.0,
          "max_tokens" => 500,
          "context_size" => 5,
          "app_name" => "test"
        }
      }
      
      # Test message requesting current information
      session[:parameters]["message"] = "What are the latest AI developments in 2025? Brief answer please."
      
      responses = []
      helper.api_request("user", session) do |response|
        responses << response
      end
      
      # Verify we got responses
      expect(responses).not_to be_empty
      
      # Check for content about AI developments
      final_response = responses.find { |r| r["type"] == "assistant" }
      expect(final_response).not_to be_nil
      expect(final_response["content"]["text"].downcase).to match(/ai|artificial intelligence|2025/)
    end
  end

  describe "xAI Live Search" do
    before(:each) do
      skip "xAI API key not configured" if @skip_xai
    end

    it "performs live search with Grok model" do
      require_relative "../../lib/monadic/adapters/vendors/grok_helper"
      
      class TestGrok
        include GrokHelper
        
        def self.name
          "Grok"
        end
        
        # Add missing helper methods
        def markdown_to_html(text, mathjax: false)
          text # Simple passthrough for testing
        end
      end
      
      helper = TestGrok.new
      
      # Create a test session
      session = {
        messages: [],
        parameters: {
          "model" => "grok-4-latest",
          "websearch" => true,
          "temperature" => 0.0,
          "max_tokens" => 500,
          "context_size" => 5,
          "app_name" => "test"
        }
      }
      
      # Test message requesting current information from X/Twitter
      session[:parameters]["message"] = "What are people saying on X about technology today? Brief summary."
      
      responses = []
      helper.api_request("user", session) do |response|
        responses << response
      end
      
      # Verify we got responses
      expect(responses).not_to be_empty
      
      # Check for content
      final_response = responses.find { |r| r["type"] == "assistant" }
      expect(final_response).not_to be_nil
      
      # xAI should return content related to X/Twitter or technology
      content = final_response["content"]["text"].downcase
      expect(content).to match(/technology|tech|x\.com|twitter|social media/)
    end
  end

  describe "Gemini URL Context" do
    before(:each) do
      skip "Gemini API key not configured" if @skip_gemini
    end

    it "uses URL context for web search" do
      require_relative "../../lib/monadic/adapters/vendors/gemini_helper"
      
      class TestGemini
        include GeminiHelper
        
        def self.name
          "Gemini"
        end
        
        # Add missing helper methods
        def markdown_to_html(text, mathjax: false)
          text # Simple passthrough for testing
        end
        
        def translate_role(role)
          role == "assistant" ? "model" : "user"
        end
      end
      
      helper = TestGemini.new
      
      # Create a test session
      session = {
        messages: [],
        parameters: {
          "model" => "gemini-2.5-flash",
          "websearch" => true,
          "temperature" => 0.0,
          "max_tokens" => 500,
          "context_size" => 5,
          "app_name" => "test",
          "reasoning_effort" => "minimal"  # Required for function calling
        }
      }
      
      # Test message that should trigger URL context
      session[:parameters]["message"] = "What is the latest news about space exploration?"
      
      responses = []
      helper.api_request("user", session) do |response|
        responses << response
      end
      
      # Verify we got responses
      expect(responses).not_to be_empty
      
      # Check for content about space
      final_response = responses.find { |r| r["type"] == "assistant" }
      expect(final_response).not_to be_nil
      expect(final_response["content"]["text"].downcase).to match(/space|nasa|exploration|rocket/)
    end
  end

  describe "Perplexity Built-in Search" do
    before(:each) do
      skip "Perplexity API key not configured" if @skip_perplexity
    end

    it "uses built-in web search capabilities" do
      require_relative "../../lib/monadic/adapters/vendors/perplexity_helper"
      
      class TestPerplexity
        include PerplexityHelper
        
        def self.name
          "Perplexity"
        end
        
        # Add missing helper methods
        def markdown_to_html(text, mathjax: false)
          text # Simple passthrough for testing
        end
      end
      
      helper = TestPerplexity.new
      
      # Create a test session
      session = {
        messages: [],
        parameters: {
          "model" => "perplexity",
          "temperature" => 0.0,
          "max_tokens" => 500,
          "context_size" => 5,
          "app_name" => "test"
        }
      }
      
      # Test message - Perplexity always searches
      session[:parameters]["message"] = "What are the current stock market trends?"
      
      responses = []
      helper.api_request("user", session) do |response|
        responses << response
      end
      
      # Verify we got responses
      expect(responses).not_to be_empty
      
      # Check for financial content
      final_response = responses.find { |r| r["type"] == "assistant" }
      expect(final_response).not_to be_nil
      expect(final_response["content"]["text"].downcase).to match(/market|stock|trading|finance/)
    end
  end

  describe "Provider Comparison" do
    it "compares search capabilities across providers" do
      results = {}
      test_query = "What happened in technology news today?"
      
      # Test each provider if available
      unless @skip_openai
        puts "Testing OpenAI..."
        # Add OpenAI test
        results["OpenAI"] = { available: true, search_type: "web_search_preview" }
      end
      
      unless @skip_claude
        puts "Testing Claude..."
        # Add Claude test
        results["Claude"] = { available: true, search_type: "web_search_20250305" }
      end
      
      unless @skip_xai
        puts "Testing xAI..."
        # Add xAI test
        results["xAI"] = { available: true, search_type: "live_search" }
      end
      
      unless @skip_gemini
        puts "Testing Gemini..."
        # Add Gemini test
        results["Gemini"] = { available: true, search_type: "url_context" }
      end
      
      unless @skip_perplexity
        puts "Testing Perplexity..."
        # Add Perplexity test
        results["Perplexity"] = { available: true, search_type: "built_in" }
      end
      
      # Output summary
      puts "\n=== Native Web Search Capabilities ==="
      results.each do |provider, info|
        puts "#{provider}: #{info[:search_type]}"
      end
      
      # At least one provider should be available for testing
      expect(results).not_to be_empty
    end
  end

  describe "Error Handling" do
    it "handles search errors gracefully" do
      # Test with invalid configuration
      require_relative "../../lib/monadic/adapters/vendors/gemini_helper"
      
      class TestGeminiError
        include GeminiHelper
        
        def self.name
          "Gemini"
        end
        
        # Add missing helper methods
        def markdown_to_html(text, mathjax: false)
          text # Simple passthrough for testing
        end
        
        def translate_role(role)
          role == "assistant" ? "model" : "user"
        end
      end
      
      helper = TestGeminiError.new
      
      session = {
        messages: [],
        parameters: {
          "model" => "invalid-model",
          "websearch" => true,
          "temperature" => 0.0,
          "max_tokens" => 500,
          "context_size" => 5,
          "app_name" => "test"
        }
      }
      
      session[:parameters]["message"] = "Test query"
      
      responses = []
      expect {
        helper.api_request("user", session) do |response|
          responses << response
        end
      }.not_to raise_error
      
      # Should handle error gracefully
      error_response = responses.find { |r| r["type"] == "error" }
      expect(error_response).not_to be_nil if CONFIG["GEMINI_API_KEY"]
    end
  end
end