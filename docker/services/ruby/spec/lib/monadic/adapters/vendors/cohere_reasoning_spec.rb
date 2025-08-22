# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../../lib/monadic/adapters/vendors/cohere_helper"

# Mock CONFIG and MonadicApp if not already loaded
unless defined?(CONFIG)
  CONFIG = {}
end

unless defined?(MonadicApp)
  module MonadicApp
    EXTRA_LOG_FILE = "/tmp/test_extra.log"
  end
end

RSpec.describe "Cohere Reasoning Model Support" do
  describe "reasoning model detection" do
    it "identifies command-a-reasoning models correctly" do
      model_name = "command-a-reasoning-08-2025"
      expect(model_name.include?("reasoning")).to eq(true)
    end
    
    it "does not identify regular command models as reasoning" do
      model_name = "command-a-08-2024"
      expect(model_name.include?("reasoning")).to eq(false)
    end
  end
  
  describe "format_conversation_as_single_text" do
    # Create a test instance that includes the module
    let(:test_helper) do
      Class.new do
        include CohereHelper
        
        # Make the private method accessible for testing
        def format_conversation_as_single_text(messages)
          super
        end
      end.new
    end
    
    it "formats conversation history correctly" do
      messages = [
        { "role" => "system", "content" => "You are a helpful assistant." },
        { "role" => "user", "content" => "Hello" },
        { "role" => "assistant", "content" => "Hi there!" },
        { "role" => "user", "content" => "How are you?" }
      ]
      
      result = test_helper.format_conversation_as_single_text(messages)
      
      expect(result).to include("You are continuing an ongoing conversation")
      expect(result).to include("System Instructions:")
      expect(result).to include("You are a helpful assistant")
      expect(result).to include("Previous Conversation:")
      expect(result).to include("User: Hello")
      expect(result).to include("Assistant: Hi there!")
      expect(result).to include("Now, the user asks:")
      expect(result).to include("How are you?")
    end
    
    it "handles messages without system prompt" do
      messages = [
        { "role" => "user", "content" => "Hello" },
        { "role" => "assistant", "content" => "Hi!" },
        { "role" => "user", "content" => "What's up?" }
      ]
      
      result = test_helper.format_conversation_as_single_text(messages)
      
      expect(result).to include("Previous Conversation:")
      expect(result).to include("User: Hello")
      expect(result).to include("Assistant: Hi!")
      expect(result).to include("What's up?")
      expect(result).not_to include("System Instructions:")
    end
    
    it "handles first message correctly" do
      messages = [
        { "role" => "system", "content" => "Be helpful." },
        { "role" => "user", "content" => "First question" }
      ]
      
      result = test_helper.format_conversation_as_single_text(messages)
      
      expect(result).to include("System Instructions:")
      expect(result).to include("Be helpful")
      expect(result).not_to include("Previous Conversation:")
      expect(result).to include("Now, the user asks:")
      expect(result).to include("First question")
    end
    
    it "separates messages with proper formatting" do
      messages = [
        { "role" => "user", "content" => "Question 1" },
        { "role" => "assistant", "content" => "Answer 1" },
        { "role" => "user", "content" => "Question 2" }
      ]
      
      result = test_helper.format_conversation_as_single_text(messages)
      
      # Check for proper separation
      expect(result).to match(/User: Question 1\n\nAssistant: Answer 1/)
      expect(result).to include("---")
    end
  end
  
  describe "reasoning effort handling" do
    it "recognizes enabled reasoning effort" do
      obj = { "reasoning_effort" => "enabled" }
      expect(obj["reasoning_effort"] == "enabled").to eq(true)
    end
    
    it "recognizes disabled reasoning effort" do
      obj = { "reasoning_effort" => "disabled" }
      expect(obj["reasoning_effort"] == "disabled").to eq(true)
    end
    
    it "handles missing reasoning effort" do
      obj = {}
      expect(obj["reasoning_effort"]).to be_nil
    end
  end
end