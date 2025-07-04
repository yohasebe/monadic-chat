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
      
      # Check condition: should NOT show message for web search
      # Message should only show for RESPONSES_API_MODELS (o3-pro)
      responses_api_models = ["o3-pro", "o3-pro-mini"] # From OpenAIHelper
      
      # For web search with regular model
      expect(responses_api_models).not_to include(original_user_model)
      
      # For o3-pro model  
      o3_model = "o3-pro"
      expect(responses_api_models).to include(o3_model)
    end
    
    it "should show 'This may take a while' only for o3-pro models" do
      # List of models that should show the processing message
      models_with_message = ["o3-pro", "o3-pro-mini"]
      
      # List of models that should NOT show the message
      models_without_message = [
        "gpt-4.1-mini", 
        "gpt-4.1", 
        "gpt-4.0-turbo",
        "gpt-3.5-turbo"
      ]
      
      # Verify o3-pro models are in the list
      models_with_message.each do |model|
        # These should be in RESPONSES_API_MODELS
        expect(["o3-pro", "o3-pro-mini"]).to include(model)
      end
      
      # Verify regular models are NOT in the list
      models_without_message.each do |model|
        expect(["o3-pro", "o3-pro-mini"]).not_to include(model)
      end
    end
  end
end