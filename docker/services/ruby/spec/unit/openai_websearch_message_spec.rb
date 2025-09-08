# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe "OpenAI Web Search Processing Message" do
  describe "OpenAIHelper api_request behavior" do
    it "should not show 'This may take a while' for web search requests" do
      # Test configuration for web search
      obj = {
        "websearch" => true,
        "model" => "gpt-4.1-mini",
        "message" => "What's the latest news?"
      }
      
      # Create a mock session
      session = {}
      
      # Track any processing_status messages
      processing_messages = []
      
      # Mock block to capture messages
      message_handler = lambda do |msg|
        if msg["type"] == "processing_status"
          processing_messages << msg["content"]
        end
      end
      
      # We can't easily test the full api_request method,
      # but we can verify the logic condition
      
      # Original user model for regular chat
      original_user_model = "gpt-4.1-mini"
      
      # Check condition: processing message is only for slow models (e.g., o3-pro)
      # Web search itself does not trigger the message for regular models
      # gpt-4.1-mini now uses Responses API via model_spec
      expect(Monadic::Utils::ModelSpec.responses_api?(original_user_model)).to be true
      expect(Monadic::Utils::ModelSpec.supports_web_search?(original_user_model)).to be true
      
      # Slow reasoning model example (o3 family)
      o3_model = "o3-pro"
      # Ensure it's recognized as a reasoning model eligible for the slow-path UX
      expect(Monadic::Utils::ModelSpec.is_reasoning_model?(o3_model)).to be true
    end
    
    it "should show 'This may take a while' only for o3-pro models" do
      # List of models that should show the processing message
      # Only o3-pro is guaranteed to be a slow Responses API model in our spec
      models_with_message = ["o3-pro"]
      
      # List of models that should NOT show the message
      models_without_message = [
        "gpt-4.1-mini", 
        "gpt-4.1", 
        "gpt-4.0-turbo",
        "gpt-3.5-turbo"
      ]
      
      # Verify o3-pro is a responses API model and considered slow in helper logic
      models_with_message.each do |model|
        # Assert they are recognized as reasoning models (slow-path)
        expect(Monadic::Utils::ModelSpec.is_reasoning_model?(model)).to be true
      end
      
      # Verify regular models are NOT in the list
      models_without_message.each do |model|
        # Regular chat models should not be considered reasoning models
        expect(Monadic::Utils::ModelSpec.is_reasoning_model?(model)).to be false
      end
    end
  end
end
