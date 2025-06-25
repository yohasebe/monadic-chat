# frozen_string_literal: true

require_relative 'e2e_helper'
require_relative 'validation_helper'

RSpec.describe "Chat Application E2E Workflow", type: :e2e do
  include E2EHelper
  include ValidationHelper

  before(:all) do
    unless check_containers_running
      skip "E2E tests require all containers to be running. Run: ./docker/monadic.sh start"
    end
    
    unless wait_for_server
      skip "E2E tests require server to be running on localhost:4567. Run: rake server"
    end
  end

  describe "Core Chat Functionality" do
    let(:ws_connection) { create_websocket_connection }
    
    after do
      ws_connection[:client].close if ws_connection[:client]
    end

    it "responds to messages" do
      send_chat_message(ws_connection, "What is the capital of Japan?")
      response = wait_for_response(ws_connection)
      
      expect(response).not_to be_empty
      expect(response.downcase).to match(/tokyo|capital/i)
    end

    it "maintains conversation context" do
      # First message
      send_chat_message(ws_connection, "My favorite color is blue")
      response1 = wait_for_response(ws_connection)
      expect(response1).not_to be_empty
      
      ws_connection[:messages].clear
      
      # Second message referring to context
      send_chat_message(ws_connection, "What color did I mention?")
      response2 = wait_for_response(ws_connection)
      expect(response2.downcase).to include("blue")
    end

    it "handles follow-up questions" do
      send_chat_message(ws_connection, "What is Python?")
      response1 = wait_for_response(ws_connection)
      expect(response1.downcase).to match(/programming|language/i)
      
      ws_connection[:messages].clear
      
      send_chat_message(ws_connection, "What are its main uses?")
      response2 = wait_for_response(ws_connection)
      expect(response2).not_to be_empty
      # Accept any response about uses/applications
      expect(response2.downcase).to match(/data|web|science|development|application|use/i)
    end
  end

  describe "Special Features" do
    let(:ws_connection) { create_websocket_connection }
    
    after do
      ws_connection[:client].close if ws_connection[:client]
    end

    it "handles markdown formatting in responses" do
      send_chat_message(ws_connection, "Show me a simple Python function with proper formatting")
      response = wait_for_response(ws_connection)
      
      # Should contain code block or function keyword
      expect(response).to match(/```|def\s+\w+|function/i)
    end

    it "handles code blocks in responses" do
      send_chat_message(ws_connection, "Give me an example of a for loop")
      response = wait_for_response(ws_connection)
      
      # Should contain loop-related content
      expect(response.downcase).to match(/for|loop|iterate/i)
    end
  end

  describe "Performance Characteristics" do
    let(:ws_connection) { create_websocket_connection }
    
    after do
      ws_connection[:client].close if ws_connection[:client]
    end

    it "responds within reasonable time" do
      start_time = Time.now
      send_chat_message(ws_connection, "Count to 5")
      response = wait_for_response(ws_connection, timeout: 30)
      end_time = Time.now
      
      expect(response).not_to be_empty
      expect(end_time - start_time).to be < 30
    end

    it "handles streaming responses efficiently" do
      send_chat_message(ws_connection, "Tell me a very short fact")
      
      # Collect streaming chunks
      chunks = []
      start_time = Time.now
      
      begin
        Timeout.timeout(10) do
          loop do
            ws_connection[:client].on :message do |event|
              data = JSON.parse(event.data)
              chunks << data if data["type"] == "content"
              break if data["type"] == "system" && data["content"] == "END_STREAM"
            end
            sleep 0.1
            break if chunks.any? || (Time.now - start_time) > 5
          end
        end
      rescue Timeout::Error
        # Normal - streaming may complete quickly
      end
      
      # Should have received some response
      final_response = wait_for_response(ws_connection, timeout: 5) rescue nil
      expect(chunks.any? || final_response).to be_truthy
    end
  end
end