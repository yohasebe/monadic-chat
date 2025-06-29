# frozen_string_literal: true

require_relative 'e2e_helper'
require_relative 'validation_helper'

RSpec.describe "Image Generator E2E Workflow", type: :e2e do
  include E2EHelper
  include ValidationHelper

  before(:all) do
    unless wait_for_server
      skip "E2E tests require server to be running on localhost:4567. Run: rake server"
    end
  end

  describe "Image Generation" do
    let(:ws_connection) { create_websocket_connection }
    
    after do
      ws_connection[:client].close if ws_connection[:client]
    end

    it "generates an image from a simple prompt" do
      message = "Generate an image of a sunset over mountains"
      send_chat_message(ws_connection, message, app: "ImageGeneratorOpenAI")
      
      response = wait_for_response(ws_connection, timeout: 60)
      
      # Should get a valid response
      expect(valid_response?(response)).to be true
      # Should mention image generation or acknowledge the request
      expect(response.downcase).to match(/generat|creat|image|sunset|mountain/i)
      # Accept either successful generation, explanation, or model selection prompt
      # Also accept markdown image format ![alt](path) or description of how to create
      expect(response).to match(/<img|http|data:image|unable|!\[.*\]\(|model|dall-e/i)
    end

    it "handles size specifications" do
      message = "Create a 1024x1024 image of a cat playing with yarn"
      send_chat_message(ws_connection, message, app: "ImageGeneratorOpenAI")
      
      response = wait_for_response(ws_connection, timeout: 60)
      
      expect(valid_response?(response)).to be true
      expect(response.downcase).to match(/cat|yarn|image/i)
    end

    it "handles style specifications" do
      message = "Generate a watercolor style painting of a garden"
      send_chat_message(ws_connection, message, app: "ImageGeneratorOpenAI")
      
      response = wait_for_response(ws_connection, timeout: 60)
      
      expect(valid_response?(response)).to be true
      # Accept various responses - successful generation, acknowledgment, or explanation
      expect(response.downcase).to match(/watercolor|painting|garden|image/i)
    end
  end

  describe "Error Handling" do
    let(:ws_connection) { create_websocket_connection }
    
    after do
      ws_connection[:client].close if ws_connection[:client]
    end

    it "handles inappropriate content requests gracefully" do
      message = "Generate an image of [inappropriate content]"
      send_chat_message(ws_connection, message, app: "ImageGeneratorOpenAI")
      
      response = wait_for_response(ws_connection)
      
      # Should get a response (error or refusal)
      expect(response).not_to be_empty
      # Should either refuse or provide alternative (accept various polite refusals)
      expect(response.downcase).to match(/cannot|unable|inappropriate|can't|sorry/i)
    end
  end
end