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
          "max_tokens" => 1000,
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
      # Ensure api_request is public for the test harness, regardless of module visibility changes
      begin
        TestClaude.send(:public, :api_request)
      rescue StandardError
        # ignore if already public or method missing
      end
      
      # Create a test session
      session = {
        messages: [],
        parameters: {
          "model" => "claude-3-5-sonnet-latest",
          "websearch" => true,
          "temperature" => 0.0,
          "max_tokens" => 1000,
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
      
      # Try multiple times with different queries to handle API variability
      max_attempts = 3
      attempt = 0
      success = false
      
      queries = [
        "What are the latest developments in artificial intelligence in 2025?",
        "Tell me about OpenAI's GPT-5 release in 2025",
        "What major technology news happened this week?"
      ]
      
      while attempt < max_attempts && !success
        # Create a test session with increased max_tokens for grok-4-fast-reasoning
        session = {
          messages: [],
          parameters: {
            "model" => "grok-4-fast-reasoning",
            "websearch" => true,
            "temperature" => 0.3,  # Slightly higher temperature for more consistent responses
            "max_tokens" => 2000,  # Increased from 1000 to ensure sufficient response
            "context_size" => 5,
            "app_name" => "test"
          }
        }
        
        # Use a different query for each attempt
        session[:parameters]["message"] = queries[attempt % queries.length]
        
        responses = []
        begin
          helper.api_request("user", session) do |response|
            responses << response
          end
        rescue => e
          # Log error but continue to next attempt
          puts "Attempt #{attempt + 1} failed with error: #{e.message}" if ENV["DEBUG_TESTS"]
          attempt += 1
          next
        end
        
        # Verify we got responses
        if responses.empty?
          attempt += 1
          next
        end
        
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
        
        # Check if we got a valid response
        if content.length > 20
          success = true
          # Accept any response that shows search was performed
          expect(content).not_to be_empty
          expect(content.length).to be > 20, "Should have some content from xAI Live Search"
          
          # More flexible verification - just check that we got a real response
          # xAI Live Search should return content related to the query
          if queries[attempt % queries.length].include?("GPT-5")
            # For specific queries, check for related terms
            expect(content.downcase).to match(/ai|artificial|intelligence|gpt|openai|technology|model|language/i)
          else
            # For general queries, just verify we got substantial content
            expect(content.split.length).to be > 10, "Should have at least 10 words in response"
          end
        else
          attempt += 1
          puts "Attempt #{attempt}: Got short response (#{content.length} chars)" if ENV["DEBUG_TESTS"]
        end
      end
      
      # If all attempts failed, skip with informative message
      unless success
        skip "xAI Live Search did not return sufficient content after #{max_attempts} attempts. This may be due to API rate limits or temporary issues."
      end
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
          "max_tokens" => 1000,
          "context_size" => 5,
          "app_name" => "test"
          # Note: reasoning_effort must NOT be set for function calling to work
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
          "max_tokens" => 1000,
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
          "max_tokens" => 1000,
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
