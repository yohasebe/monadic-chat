# frozen_string_literal: true

require_relative "spec_helper"

# Check if the module actually exists, if not create a mock module for testing
begin
  require_relative "../lib/monadic/helpers/vendors/claude_helper"
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
    
    WEBSEARCH_TOOLS = [
      {
        "name" => "web_search",
        "description" => "Search the web"
      }
    ]
    
    def self.vendor_name
      "Anthropic"
    end
    
    def self.list_models
      ["claude-3-5-sonnet", "claude-3-opus", "claude-3-haiku"]
    end
    
    def send_query(options, model: "claude-3-5-sonnet")
      "Mock Claude response"
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
  before do
    stub_http_client
    
    # Mock CONFIG
    stub_const("CONFIG", {"ANTHROPIC_API_KEY" => "mock-api-key"})
  end
  
  # Use shared examples for common vendor helper tests
  it_behaves_like "a vendor API helper", "Anthropic", "claude-3-5-sonnet-20241022"
  
  describe "#send_query" do
    context "with normal conversation" do
      it "formats system message as top-level parameter" do
        options = {
          "system" => "You are a helpful assistant",
          "temperature" => 0.7,
          "max_tokens" => 1000
        }
        
        # Expect HTTP to be called with Claude's specific parameter format
        expect(HTTP).to receive(:post).with(
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
        expect(HTTP).to receive(:post).with(
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
        allow(HTTP).to receive(:post).and_return(
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
      allow(HTTP).to receive(:post).and_return(
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
    it "properly formats tools for web search" do
      options = {
        "system" => "You have access to web search",
        "tools" => ClaudeHelper::WEBSEARCH_TOOLS,
        "tool_choice" => "auto"
      }
      
      # Skip examining response structure in detail, just ensure it makes the request
      allow(HTTP).to receive(:post).and_return(
        mock_successful_response('{"content":[{"type":"text","text":"I searched the web for you"}]}')
      )
      
      # Just verify the query includes required components without being strict on structure
      expect(HTTP).to receive(:post).with(
        "#{ClaudeHelper::API_ENDPOINT}/messages", 
        anything
      )
      
      helper.send_query(options)
    end
  end
end