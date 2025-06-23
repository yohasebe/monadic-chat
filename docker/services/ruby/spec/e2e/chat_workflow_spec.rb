# frozen_string_literal: true

require_relative 'e2e_helper'

RSpec.describe "Chat Application E2E Workflow", type: :e2e do
  include E2EHelper

  before(:all) do
    unless check_containers_running
      skip "E2E tests require all containers to be running. Run: ./docker/monadic.sh start"
    end
    
    unless wait_for_server
      skip "E2E tests require server to be running on localhost:4567. Run: rake server"
    end
  end

  describe "Basic Chat Interaction" do
    let(:ws_connection) { create_websocket_connection }
    
    after do
      ws_connection[:client].close if ws_connection[:client]
    end

    it "completes a simple question-answer workflow" do
      # Send a simple math question
      send_chat_message(ws_connection, "What is 2 + 2?")
      
      # Wait for response
      response = wait_for_response(ws_connection)
      
      # Verify response contains the answer
      expect(response).to include("4")
      expect(response).not_to be_empty
    end

    it "maintains conversation context" do
      # First message
      send_chat_message(ws_connection, "My name is TestUser")
      response1 = wait_for_response(ws_connection)
      expect(response1).to match(/nice to meet you|hello|hi/i)
      
      # Clear messages for next interaction
      ws_connection[:messages].clear
      
      # Second message referring to context
      send_chat_message(ws_connection, "What is my name?")
      response2 = wait_for_response(ws_connection)
      expect(response2).to include("TestUser")
    end

    it "handles multiple messages in sequence" do
      messages = [
        "What is the capital of France?",
        "What is the population of that city?",
        "Name one famous landmark there"
      ]
      
      responses = []
      
      messages.each do |msg|
        ws_connection[:messages].clear
        send_chat_message(ws_connection, msg)
        response = wait_for_response(ws_connection)
        responses << response
      end
      
      # Verify responses
      expect(responses[0]).to include("Paris")
      # Accept either population answer or clarification request
      expect(responses[1]).to match(/million|population|specify|which.*city|referring/i)
      # Accept landmark answer or follow-up based on context
      expect(responses[2]).to match(/Eiffel Tower|Louvre|Notre-Dame|Arc de Triomphe|landmark|famous|Paris/i)
    end
  end

  describe "Error Handling" do
    let(:ws_connection) { create_websocket_connection }
    
    after do
      ws_connection[:client].close if ws_connection[:client]
    end

    it "handles empty messages gracefully" do
      send_chat_message(ws_connection, "")
      
      # Should get some kind of response even for empty message
      begin
        response = wait_for_response(ws_connection, timeout: 5)
        # AI usually responds even to empty messages
        expect(response).not_to be_nil
      rescue => e
        # Timeout is also acceptable for empty message
        expect(e.message).to match(/timeout|error/i)
      end
    end

    it "handles very long messages" do
      long_message = "Please summarize this: " + ("Lorem ipsum " * 100)
      send_chat_message(ws_connection, long_message)
      
      response = wait_for_response(ws_connection)
      expect(response).not_to be_empty
      expect(response.length).to be < long_message.length # Should be a summary
    end
  end

  describe "Different Chat Models" do
    let(:ws_connection) { create_websocket_connection }
    
    after do
      ws_connection[:client].close if ws_connection[:client]
    end

    it "works with different OpenAI models" do
      models = ["gpt-4.1-mini", "gpt-4o"]
      
      models.each do |model|
        ws_connection[:messages].clear
        send_chat_message(ws_connection, "Say 'Hello from #{model}'", model: model)
        
        begin
          response = wait_for_response(ws_connection)
          expect(response.downcase).to include("hello from #{model.downcase}")
        rescue => e
          # Model might not be available
          expect(e.message).to match(/model|api/i)
        end
      end
    end
  end

  describe "Conversation Management" do
    it "supports creating new conversations" do
      # First conversation
      ws1 = create_websocket_connection
      send_chat_message(ws1, "Remember the number 42")
      response1 = wait_for_response(ws1)
      expect(response1).to include("42")
      ws1[:client].close
      
      # New conversation should not have context
      ws2 = create_websocket_connection
      send_chat_message(ws2, "What number did I ask you to remember?")
      response2 = wait_for_response(ws2)
      expect(response2).not_to include("42")
      ws2[:client].close
    end
  end

  describe "Special Features" do
    let(:ws_connection) { create_websocket_connection }
    
    after do
      ws_connection[:client].close if ws_connection[:client]
    end

    it "handles markdown formatting in responses" do
      send_chat_message(ws_connection, "Show me a markdown list with 3 items")
      response = wait_for_response(ws_connection)
      
      # Check for markdown list indicators (bullet or numbered)
      expect(response).to match(/(?:[-*]\s+\w+|\d+\.\s+\w+)/)
      expect(response).to match(/\n/)
    end

    it "handles code blocks in responses" do
      send_chat_message(ws_connection, "Show me a simple Python hello world example")
      response = wait_for_response(ws_connection)
      
      # Check for code block indicators
      expect(response).to match(/```|print\(|hello/i)
    end
  end

  describe "Performance Characteristics" do
    let(:ws_connection) { create_websocket_connection }
    
    after do
      ws_connection[:client].close if ws_connection[:client]
    end

    it "responds within reasonable time" do
      start_time = Time.now
      send_chat_message(ws_connection, "What is 1+1?")
      response = wait_for_response(ws_connection)
      end_time = Time.now
      
      response_time = end_time - start_time
      expect(response_time).to be < 10 # Should respond within 10 seconds
      expect(response).to include("2")
    end

    it "handles streaming responses efficiently" do
      fragment_count = 0
      start_time = nil
      
      # Count fragments as they arrive
      ws_connection[:client].on :message do |msg|
        data = JSON.parse(msg.data)
        if data["type"] == "fragment"
          fragment_count += 1
          start_time ||= Time.now
        end
      end
      
      send_chat_message(ws_connection, "Count from 1 to 10")
      response = wait_for_response(ws_connection)
      
      # Should receive multiple fragments for streaming
      expect(fragment_count).to be > 1
      # Check that numbers 1-10 appear in some form
      (1..10).each do |num|
        expect(response).to include(num.to_s)
      end
    end
  end
end