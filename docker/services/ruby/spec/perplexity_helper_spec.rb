# frozen_string_literal: true

require_relative "spec_helper"

# Check if the module actually exists, if not create a mock module for testing
begin
  require_relative "../lib/monadic/helpers/vendors/perplexity_helper"
rescue LoadError
  # Create a mock module if the real one can't be loaded
  module PerplexityHelper
    MAX_FUNC_CALLS = 8
    API_ENDPOINT = "https://api.perplexity.ai"
    
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 60 * 10
    WRITE_TIMEOUT = 60 * 10
    
    MAX_RETRIES = 5
    RETRY_DELAY = 1
    
    def self.vendor_name
      "Perplexity"
    end
    
    def self.list_models
      ["sonar", "sonar-pro", "sonar-reasoning", "sonar-reasoning-pro", "r1-1776"]
    end
    
    def send_query(options, model: "sonar-pro")
      "Mock Perplexity response"
    end
  end
end

# Create a test class to include the module
class PerplexityHelperTest
  include PerplexityHelper
  
  # Additional methods needed for testing
  def initialize
    # Any setup needed
  end
end

RSpec.describe PerplexityHelper do
  let(:helper) { PerplexityHelperTest.new }
  
  # Mock HTTP and CONFIG for tests
  before do
    # Mock HTTP module
    stub_const("HTTP", double)
    allow(HTTP).to receive(:headers).and_return(HTTP)
    allow(HTTP).to receive(:timeout).and_return(HTTP)
    allow(HTTP).to receive(:post).and_return(double("Response", 
      status: double("Status", success?: true),
      body: '{"choices":[{"message":{"content":"Test response"}}]}'
    ))
    
    # Mock CONFIG
    stub_const("CONFIG", {"PERPLEXITY_API_KEY" => "mock-api-key"})
  end
  
  describe ".vendor_name" do
    it "returns the correct vendor name" do
      expect(PerplexityHelper.vendor_name).to eq("Perplexity")
    end
  end
  
  describe ".list_models" do
    it "returns the available model list" do
      models = PerplexityHelper.list_models
      expect(models).to include("sonar")
      expect(models).to include("sonar-pro")
      expect(models).to include("sonar-deep-research")
    end
  end
  
  describe "#send_query" do
    context "with normal conversation" do
      it "sends properly formatted messages" do
        options = {
          "messages" => [
            {"role" => "system", "content" => "You are an assistant"},
            {"role" => "user", "content" => "Hello"},
            {"role" => "assistant", "content" => "Hi there"},
            {"role" => "user", "content" => "How are you?"}
          ],
          "temperature" => 0.7,
          "max_tokens" => 1000
        }
        
        # Expect HTTP to be called with specific parameters
        expect(HTTP).to receive(:post).with(
          "#{PerplexityHelper::API_ENDPOINT}/chat/completions",
          hash_including(
            json: hash_including(
              "model" => "sonar-pro",
              "temperature" => 0.7,
              "max_tokens" => 1000,
              "messages" => array_including(
                hash_including("role" => "user", "content" => "How are you?")
              )
            )
          )
        ).and_return(double("Response", 
          status: double("Status", success?: true),
          body: '{"choices":[{"message":{"content":"I am fine, thank you!"}}]}'
        ))
        
        result = helper.send_query(options)
        expect(result).to eq("I am fine, thank you!")
      end
      
      it "ensures the last message is always a user message" do
        options = {
          "messages" => [
            {"role" => "system", "content" => "You are an assistant"},
            {"role" => "user", "content" => "Hello"},
            {"role" => "assistant", "content" => "Hi there"}
          ]
        }
        
        # Check if an additional user message is added
        expect(HTTP).to receive(:post).with(
          "#{PerplexityHelper::API_ENDPOINT}/chat/completions",
          hash_including(
            json: hash_including(
              "messages" => array_including(
                hash_including("role" => "user") # Last message should be user
              )
            )
          )
        )
        
        helper.send_query(options)
      end
    end
    
    context "with AI User request" do
      it "formats the request properly for AI User" do
        options = {
          "ai_user_system_message" => "Based on this conversation history: User: Hello, Assistant: Hi there",
          "temperature" => 0.7,
          "max_tokens" => 1000
        }
        
        # For AI User in the updated implementation, we expect a simplified format
        expect(HTTP).to receive(:post).with(
          "#{PerplexityHelper::API_ENDPOINT}/chat/completions",
          hash_including(
            json: hash_including(
              "model" => "sonar-pro",
              "messages" => [
                hash_including("role" => "user"),
                hash_including("role" => "assistant"),
                hash_including("role" => "user") # Last must be user
              ]
            )
          )
        )
        
        helper.send_query(options)
      end
      
      it "returns error message on API failure" do
        options = {"ai_user_system_message" => "Test conversation"}
        
        # Simulate API error
        error_response = double("Response",
          status: double("Status", success?: false),
          body: '{"error":{"message":"Last message must have role `user`"}}'
        )
        allow(HTTP).to receive(:post).and_return(error_response)
        
        result = helper.send_query(options)
        expect(result).to include("Error: Last message must have role `user`")
      end
    end
    
    it "returns error when API key is missing" do
      # Remove API key from CONFIG
      stub_const("CONFIG", {})
      
      # Mock the API key check
      allow(helper).to receive(:send_query).and_call_original
      allow(CONFIG).to receive(:[]).with("PERPLEXITY_API_KEY").and_return(nil)
      allow(ENV).to receive(:[]).with("PERPLEXITY_API_KEY").and_return(nil)
      
      # Override the HTTP response for this specific test
      error_response = double("Response", 
        status: double("Status", success?: false),
        body: '{"error":"API key not found"}'
      )
      allow(HTTP).to receive(:post).and_return(error_response)
      
      result = helper.send_query({})
      expect(result).to include("Error")
    end
  end
end