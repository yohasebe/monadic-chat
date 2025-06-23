# frozen_string_literal: true

require_relative 'e2e_helper'
require_relative 'validation_helper'

RSpec.describe "Monadic Help E2E Workflow", type: :e2e do
  include E2EHelper
  include ValidationHelper

  before(:all) do
    unless wait_for_server
      skip "E2E tests require server to be running on localhost:4567. Run: rake server"
    end
    
    # Check if help database is available
    unless system("docker exec monadic-chat-pgvector-container psql -U postgres -d monadic_help -c 'SELECT COUNT(*) FROM help_items' > /dev/null 2>&1")
      skip "Monadic Help requires help database to be populated"
    end
  end

  describe "Help Topic Search" do
    let(:ws_connection) { create_websocket_connection }
    
    after do
      ws_connection[:client].close if ws_connection[:client]
    end

    it "finds information about basic features" do
      message = "How do I use voice chat in Monadic Chat?"
      send_chat_message(ws_connection, message, app: "MonadicHelpOpenAI")
      
      response = wait_for_response(ws_connection)
      
      expect(valid_response?(response)).to be true
      # Accept various ways of describing voice chat functionality
      expect(response.downcase).to match(/voice|chat|speech|audio|microphone|speak|talk|conversation/i)
      # Should provide helpful information - documentation link, instructions, or explanation
      expect(response).to match(/https:\/\/|docs|documentation|choose.*app|platform|whatsapp|discord|feature|enable|use|click|button|setting/i)
    end

    it "provides information about specific apps" do
      message = "Tell me about the Code Interpreter app"
      send_chat_message(ws_connection, message, app: "MonadicHelpOpenAI")
      
      response = wait_for_response(ws_connection, timeout: 60)  # Increase timeout
      
      expect(valid_response?(response)).to be true
      expect(response.downcase).to match(/code.*interpreter|python|execute|programming/i)
    end

    it "handles configuration questions" do
      message = "How do I set up API keys?"
      send_chat_message(ws_connection, message, app: "MonadicHelpOpenAI")
      
      response = wait_for_response(ws_connection)
      
      expect(valid_response?(response)).to be true
      expect(response.downcase).to match(/api.*key|config|environment|setup/i)
    end
  end

  describe "Complex Queries" do
    let(:ws_connection) { create_websocket_connection }
    
    after do
      ws_connection[:client].close if ws_connection[:client]
    end

    it "handles multi-topic questions" do
      message = "What's the difference between Chat and Chat Plus?"
      send_chat_message(ws_connection, message, app: "MonadicHelpOpenAI")
      
      response = wait_for_response(ws_connection)
      
      expect(valid_response?(response)).to be true
      expect(response.downcase).to match(/chat|plus|difference|feature/i)
      expect(response.length).to be > 100  # Should be a detailed explanation
    end

    it "provides troubleshooting help" do
      message = "My Docker containers won't start"
      send_chat_message(ws_connection, message, app: "MonadicHelpOpenAI")
      
      response = wait_for_response(ws_connection)
      
      expect(valid_response?(response)).to be true
      expect(response.downcase).to match(/docker|container|start|troubleshoot|check/i)
    end
  end
end