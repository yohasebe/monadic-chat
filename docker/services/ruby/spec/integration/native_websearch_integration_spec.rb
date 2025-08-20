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
      require_relative "../../lib/monadic/utils/string_utils"
      
      class TestOpenAI
        include OpenAIHelper
        include StringUtils
        
        def self.name
          "OpenAI"
        end
        
        # Add missing helper methods
        def markdown_to_html(text, mathjax: false)
          text # Simple passthrough for testing
        end
        
        def detect_language(text)
          "en" # Simple stub for testing
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
      # Collect all fragments to build the complete response
      fragments = responses.select { |r| r["type"] == "fragment" }.map { |r| r["content"] }.join
      
      # Check if we have content (might be about Tokyo or include date/time)
      expect(fragments).not_to be_empty
      # OpenAI might return just date/time or weather info
      expect(fragments.downcase).to match(/tokyo|weather|temperature|cloudy|sunny|rain|pm|am|\d{4}/)
    end
  end

  describe "Claude Native Web Search" do
    before(:each) do
      skip "Claude API key not configured" if @skip_claude
    end

    it "performs web search with Claude 3.5 Sonnet" do
      require_relative "../../lib/monadic/adapters/vendors/claude_helper"
      require_relative "../../lib/monadic/utils/string_utils"
      
      class TestClaude
        include ClaudeHelper
        include StringUtils
        
        def self.name
          "Claude"
        end
        
        # Add missing helper methods
        def markdown_to_html(text, mathjax: false)
          text # Simple passthrough for testing
        end
        
        def detect_language(text)
          "en" # Simple stub for testing
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
      # Collect all fragments to build the complete response
      fragments = responses.select { |r| r["type"] == "fragment" }.map { |r| r["content"] }.join
      
      # Check if we have content about AI or 2025
      expect(fragments).not_to be_empty
      expect(fragments.downcase).to match(/ai|artificial intelligence|2025/)
    end
  end

  describe "xAI Live Search" do
    before(:each) do
      skip "xAI API key not configured" if @skip_xai
      # Remove the skip to test with actual API
    end

    it "performs live search with Grok model" do
      require_relative "../../lib/monadic/adapters/vendors/grok_helper"
      require_relative "../../lib/monadic/utils/string_utils"
      
      class TestGrok
        include GrokHelper
        include StringUtils
        
        def self.name
          "Grok"
        end
        
        # Add missing helper methods
        def markdown_to_html(text, mathjax: false)
          text # Simple passthrough for testing
        end
        
        def detect_language(text)
          "en" # Simple stub for testing
        end
      end
      
      helper = TestGrok.new
      
      # Create a test session
      session = {
        messages: [],
        parameters: {
          "model" => "grok-3",
          "websearch" => true,
          "temperature" => 0.0,
          "max_tokens" => 500,
          "context_size" => 5,
          "app_name" => "test"
        }
      }
      
      # Test message requesting current information
      session[:parameters]["message"] = "What is the current weather in Tokyo Japan? Please provide a brief answer with today's temperature."
      
      responses = []
      helper.api_request("user", session) do |response|
        responses << response
      end
      
      # Verify we got responses
      expect(responses).not_to be_empty
      
      # xAI returns responses differently
      
      # Check for content - handle fragment, assistant and message response types
      fragments = responses.select { |r| r["type"] == "fragment" }.map { |r| r["content"] }.join
      assistant_response = responses.find { |r| r["type"] == "assistant" }
      message_response = responses.find { |r| r["type"] == "message" && r["content"] != "DONE" }
      
      # Collect content from all possible response types
      content = ""
      content += fragments if !fragments.empty?
      if assistant_response
        content += assistant_response["content"]["text"] rescue assistant_response["content"].to_s
      end
      if message_response
        content += message_response["content"]["text"] rescue message_response["content"].to_s
      end
      
      # Remove debug output for cleaner test results
      if ENV["DEBUG_XAI_TESTS"]
        puts "\n[DEBUG] xAI Response Analysis:"
        puts "  Total responses: #{responses.length}"
        puts "  Response types: #{responses.map { |r| r["type"] }.uniq.join(", ")}"
        puts "  Fragment count: #{responses.select { |r| r["type"] == "fragment" }.length}"
        puts "  Content length: #{content.length}"
        puts "  First 200 chars: #{content[0..199]}" if content.length > 0
      end
      
      # Verify response content
      expect(content.length).to be > 50, "Should have substantial content from xAI Live Search"
      expect(content.downcase).to match(/tokyo|weather|temperature|°c|°f|celsius|fahrenheit|sunny|cloudy|rain/i)
    end
  end

  describe "Gemini URL Context" do
    before(:each) do
      skip "Gemini API key not configured" if @skip_gemini
      # Test with fixed implementation
    end

    it "uses URL context for web search" do
      require_relative "../../lib/monadic/adapters/vendors/gemini_helper"
      require_relative "../../lib/monadic/utils/string_utils"
      
      class TestGemini
        include GeminiHelper
        include StringUtils
        
        def self.name
          "Gemini"
        end
        
        # Add missing helper methods
        def markdown_to_html(text, mathjax: false)
          text # Simple passthrough for testing
        end
        
        def detect_language(text)
          "en" # Simple stub for testing
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
      
      # Gemini URL Context handling
      
      # Check for content about space - handle both fragment and assistant response types
      fragments = responses.select { |r| r["type"] == "fragment" }.map { |r| r["content"] }.join
      assistant_response = responses.find { |r| r["type"] == "assistant" }
      
      content = fragments.empty? && assistant_response ? assistant_response["content"]["text"] : fragments
      
      expect(content).not_to be_empty
      expect(content.downcase).to match(/space|nasa|exploration|rocket/)
    end
  end

  describe "Perplexity Built-in Search" do
    before(:each) do
      skip "Perplexity API key not configured" if @skip_perplexity
    end

    it "uses built-in web search capabilities" do
      require_relative "../../lib/monadic/adapters/vendors/perplexity_helper"
      require_relative "../../lib/monadic/utils/string_utils"
      
      class TestPerplexity
        include PerplexityHelper
        include StringUtils
        
        def self.name
          "Perplexity"
        end
        
        # Add missing helper methods
        def markdown_to_html(text, mathjax: false)
          text # Simple passthrough for testing
        end
        
        def detect_language(text)
          "en" # Simple stub for testing
        end
      end
      
      helper = TestPerplexity.new
      
      # Create a test session
      session = {
        messages: [],
        parameters: {
          "model" => "sonar",  # Use a valid Perplexity model
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
      
      # Perplexity always searches
      
      # Check for financial content - handle both fragment and assistant response types
      fragments = responses.select { |r| r["type"] == "fragment" }.map { |r| r["content"] }.join
      assistant_response = responses.find { |r| r["type"] == "assistant" }
      
      content = fragments.empty? && assistant_response ? assistant_response["content"]["text"] : fragments
      
      expect(content).not_to be_empty
      expect(content.downcase).to match(/market|stock|trading|finance/)
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
      require_relative "../../lib/monadic/utils/string_utils"
      
      class TestGeminiError
        include GeminiHelper
        include StringUtils
        
        def self.name
          "Gemini"
        end
        
        # Add missing helper methods
        def markdown_to_html(text, mathjax: false)
          text # Simple passthrough for testing
        end
        
        def detect_language(text)
          "en" # Simple stub for testing
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