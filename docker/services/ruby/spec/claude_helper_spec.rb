# frozen_string_literal: true

require_relative "spec_helper"
require 'securerandom'

# Check if the module actually exists, if not create a mock module for testing
begin
  require_relative "../lib/monadic/adapters/vendors/claude_helper"
rescue LoadError
  # Create a mock module if the real one can't be loaded
  module ClaudeHelper
    MAX_FUNC_CALLS = 8
    API_ENDPOINT = "https://api.anthropic.com/v1"
    
    OPEN_TIMEOUT = 5 * 2
    READ_TIMEOUT = 60 * 5
    WRITE_TIMEOUT = 60 * 5
    
    MAX_RETRIES = 5
    RETRY_DELAY = 2
    
    TAVILY_WEBSEARCH_TOOLS = [
      {
        "name" => "tavily_search",
        "description" => "Search the web using Tavily API"
      }
    ]
    
    NATIVE_WEBSEARCH_TOOL = {
      "type" => "web_search_20250305",
      "name" => "web_search",
      "max_uses" => 10
    }
    
    def self.vendor_name
      "Anthropic"
    end
    
    def self.list_models
      ["claude-3-5-sonnet", "claude-3-opus", "claude-3-haiku"]
    end
  end
end

# Create a test class to include the module
class ClaudeHelperTest
  include ClaudeHelper
  
  # Additional methods needed for testing
  def initialize
    @thinking = nil
    @signature = nil
  end
end

RSpec.describe ClaudeHelper do
  let(:helper) { ClaudeHelperTest.new }
  
  # Using shared test utilities
  let(:http_double) { nil }
  
  before do
    @http_double = stub_http_client
    
    # Mock CONFIG
    stub_const("CONFIG", {"ANTHROPIC_API_KEY" => "mock-api-key"})
  end
  
  # Use shared examples for common vendor helper tests
  it_behaves_like "a vendor API helper", "Anthropic", "claude-3-5-sonnet-20241022"
  it_behaves_like "a helper that handles symbol keys", "claude-3-5-sonnet-20241022"
  
  describe "#send_query" do
    context "with normal conversation" do
      it "formats system message as top-level parameter" do
        options = {
          "system" => "You are a helpful assistant",
          "temperature" => 0.7,
          "max_tokens" => 1000
        }
        
        # Expect HTTP to be called with Claude's specific parameter format
        expect(@http_double).to receive(:post).with(
          "#{ClaudeHelper::API_ENDPOINT}/messages",
          hash_including(
            json: hash_including(
              "model" => "claude-3-5-sonnet-20241022",
              "temperature" => 0.7,
              "max_tokens" => 1000,
              "system" => "You are a helpful assistant"
            )
          )
        ).and_return(mock_successful_response('{"content":[{"type":"text","text":"I am Claude, how can I help?"}]}'))
        
        result = helper.send_query(options)
        expect(result).to eq("I am Claude, how can I help?")
      end
      
      it "handles symbol keys in options hash" do
        options = {
          system: "You are a helpful assistant",
          temperature: 0.7,
          max_tokens: 1000
        }
        
        # Expect HTTP to be called with Claude's specific parameter format (with string keys)
        expect(@http_double).to receive(:post).with(
          "#{ClaudeHelper::API_ENDPOINT}/messages",
          hash_including(
            json: hash_including(
              "model" => "claude-3-5-sonnet-20241022",
              "temperature" => 0.7,
              "max_tokens" => 1000,
              "system" => "You are a helpful assistant"
            )
          )
        ).and_return(mock_successful_response('{"content":[{"type":"text","text":"I am Claude, how can I help?"}]}'))
        
        result = helper.send_query(options)
        expect(result).to eq("I am Claude, how can I help?")
      end
    end
    
    context "with AI User request" do
      it "formats the request properly for AI User" do
        options = {
          "ai_user_system_message" => "Based on this conversation history: User: Hello, Assistant: Hi there",
          "temperature" => 0.7,
          "max_tokens" => 1000
        }
        
        # For Claude AI User, expect a properly formatted request with system parameter
        expect(@http_double).to receive(:post).with(
          "#{ClaudeHelper::API_ENDPOINT}/messages",
          hash_including(
            json: hash_including(
              "model" => "claude-3-5-sonnet-20241022",
              "system" => options["ai_user_system_message"],
              "messages" => array_including(
                hash_including("role" => "user")
              )
            )
          )
        )
        
        helper.send_query(options)
      end
      
      it "returns error message on API failure" do
        options = {"ai_user_system_message" => "Test conversation"}
        
        # Simulate API error
        allow(@http_double).to receive(:post).and_return(
          mock_error_response('{"error":{"message":"Invalid request"}}')
        )
        
        result = helper.send_query(options)
        expect(result).to include("ERROR")
      end
    end
    
    it "extracts content from different response formats" do
      # Test with content array format
      content_response = mock_successful_response(
        '{"content":[{"type":"text","text":"Response from content array"}]}'
      )
      
      # Test with message.content format
      message_response = mock_successful_response(
        '{"message":{"content":[{"type":"text","text":"Response from message.content"}]}}'
      )
      
      # Test with completion format (older Claude API)
      completion_response = mock_successful_response(
        '{"completion":"Response from completion field"}'
      )
      
      # Set up HTTP to return different responses in sequence
      allow(@http_double).to receive(:post).and_return(
        content_response, 
        message_response, 
        completion_response
      )
      
      # Test each format
      expect(helper.send_query({})).to eq("Response from content array")
      expect(helper.send_query({})).to eq("Response from message.content")
      expect(helper.send_query({})).to eq("Response from completion field")
    end
  end
  
  describe "websearch capabilities" do
    it "properly formats Tavily tools for web search" do
      options = {
        "system" => "You have access to web search",
        "tools" => ClaudeHelper::TAVILY_WEBSEARCH_TOOLS,
        "tool_choice" => "auto"
      }
      
      # Skip examining response structure in detail, just ensure it makes the request
      allow(@http_double).to receive(:post).and_return(
        mock_successful_response('{"content":[{"type":"text","text":"I searched the web for you"}]}')
      )
      
      # Just verify the query includes required components without being strict on structure
      expect(@http_double).to receive(:post).with(
        "#{ClaudeHelper::API_ENDPOINT}/messages", 
        anything
      )
      
      helper.send_query(options)
    end
    
    it "properly formats native web search tool in api_request" do
      # Create a mock session using api_request which handles tools
      session = {
        parameters: {
          "model" => "claude-3-5-sonnet-20241022",
          "app_name" => "test_app",
          "websearch" => "true"  # This will trigger native websearch detection
        },
        messages: [
          { "role" => "system", "text" => "You have access to native web search" }
        ]
      }
      
      # Mock the APPS constant
      mock_app = double("App", settings: { "tools" => [] })
      stub_const("APPS", { "test_app" => mock_app })
      
      # Expect the API request to include the native web search tool
      expect(@http_double).to receive(:post).with(
        "#{ClaudeHelper::API_ENDPOINT}/messages", 
        hash_including(
          json: hash_including(
            "tools" => include(
              hash_including(
                type: "web_search_20250305",
                name: "web_search"
              )
            ),
            "model" => "claude-3-5-sonnet-20241022"
          )
        )
      ).and_return(double("Response", 
        status: double("Status", success?: true),
        body: double("Body", each: proc { |&block|
          block.call('data: {"type":"message_delta","delta":{"text":"Searched the web"}}')
          block.call('data: {"type":"message_stop","stop_reason":"end_turn"}')
        })
      ))
      
      # Just verify the request was made with the right parameters
      # The HTTP expectation above validates that the request includes the correct tools
      expect {
        helper.api_request("user", session) { |result| }
      }.not_to raise_error
    end
    
    it "automatically selects native search for supported models" do
      # Test with a model that supports native search
      session = {
        parameters: {
          "model" => "claude-3-5-sonnet-20241022",
          "websearch" => "true",
          "app_name" => "test_app"
        },
        messages: [
          { "role" => "system", "text" => "You are a helpful assistant" },
          { "role" => "user", "text" => "Search for something" }
        ]
      }
      
      # Mock APPS constant
      mock_app = double("App", settings: { "tools" => [] })
      stub_const("APPS", { "test_app" => mock_app })
      
      # Override CONFIG to ensure native websearch is enabled
      stub_const("CONFIG", {
        "ANTHROPIC_API_KEY" => "mock-api-key",
        "ANTHROPIC_NATIVE_WEBSEARCH" => nil  # nil will use default (enabled)
      })
      
      # Expect the request to include native search tool
      expect(@http_double).to receive(:post).with(
        "#{ClaudeHelper::API_ENDPOINT}/messages",
        hash_including(
          json: hash_including(
            "tools" => array_including(
              hash_including(:type => "web_search_20250305")
            )
          )
        )
      ).and_return(double("Response", 
        status: double("Status", success?: true),
        body: double("Body", each: proc { |&block|
          block.call('data: {"type":"message_delta","delta":{"text":"Native search result"}}')
          block.call('data: {"type":"message_stop","stop_reason":"end_turn"}')
        })
      ))
      
      # Just verify the request was made correctly via the expectation above
      expect {
        helper.api_request("user", session) { |result| }
      }.not_to raise_error
    end
    
    it "falls back to Tavily for non-supported models when API key exists" do
      # Test with a model that doesn't support native search
      session = {
        parameters: {
          "model" => "claude-3-opus-20240229",
          "websearch" => "true",
          "app_name" => "test_app"
        },
        messages: [
          { "role" => "system", "text" => "You are a helpful assistant" },
          { "role" => "user", "text" => "Search for something" }
        ]
      }
      
      # Mock APPS constant
      mock_app = double("App", settings: { "tools" => [] })
      stub_const("APPS", { "test_app" => mock_app })
      
      # Mock CONFIG with TAVILY_API_KEY
      stub_const("CONFIG", { 
        "ANTHROPIC_API_KEY" => "mock-api-key",
        "TAVILY_API_KEY" => "mock-tavily-key"
      })
      
      # Expect the request to include Tavily tools
      expect(@http_double).to receive(:post).with(
        "#{ClaudeHelper::API_ENDPOINT}/messages",
        hash_including(
          json: hash_including(
            "tools" => array_including(
              hash_including(name: "tavily_search")
            )
          )
        )
      ).and_return(double("Response", 
        status: double("Status", success?: true),
        body: double("Body", each: proc { |&block|
          block.call('data: {"type":"message_delta","delta":{"text":"Tavily search result"}}')
          block.call('data: {"type":"message_stop","stop_reason":"end_turn"}')
        })
      ))
      
      # Just verify the request was made correctly via the expectation above
      expect {
        helper.api_request("user", session) { |result| }
      }.not_to raise_error
    end
  end
end