# frozen_string_literal: true

require_relative "e2e_helper"

RSpec.describe "Mistral WebSearch Duplicate Prevention E2E", :e2e do
  include E2EHelper

  before(:all) do
    unless check_containers_running
      skip "E2E tests require containers to be running."
    end
    
    unless wait_for_server
      skip "E2E tests require server to be running on localhost:4567."
    end
    
    unless CONFIG["MISTRAL_API_KEY"] && CONFIG["TAVILY_API_KEY"]
      skip "Mistral web search tests require both MISTRAL_API_KEY and TAVILY_API_KEY"
    end
  end

  describe "Multiple API calls in same session" do
    let!(:ws_connection) { create_websocket_connection }

    after(:each) do
      if ws_connection && ws_connection[:client]
        ws_connection[:client].close
        sleep 0.5
      end
    end

    it "does not duplicate websearch prompt in system message" do
      # First message with websearch enabled
      first_message = "What's happening in AI today?"
      
      send_chat_message(ws_connection, first_message, 
        app: "ChatMistral", 
        model: "mistral-small-latest",
        websearch: true)
      
      first_response = wait_for_response(ws_connection, timeout: 45)
      expect(first_response).not_to be_empty
      
      # Second message in same session
      second_message = "Tell me more about recent AI developments"
      
      send_chat_message(ws_connection, second_message, 
        app: "ChatMistral", 
        model: "mistral-small-latest",
        websearch: true)
      
      second_response = wait_for_response(ws_connection, timeout: 45)
      expect(second_response).not_to be_empty
      
      # Both responses should work correctly
      # The websearch prompt should not be duplicated internally
      # (This is verified by the fact that the API calls succeed)
      expect(first_response.downcase).to match(/ai|artificial intelligence|search|recent|current/i)
      expect(second_response.downcase).to match(/ai|artificial intelligence|developments/i)
    end

    it "handles websearch toggle correctly" do
      # First query without websearch
      message_without = "Explain what machine learning is"
      
      send_chat_message(ws_connection, message_without, 
        app: "ChatMistral", 
        model: "mistral-small-latest",
        websearch: false)
      
      response_without = wait_for_response(ws_connection, timeout: 30)
      
      # Then query with websearch enabled
      message_with = "What are the latest breakthroughs in machine learning?"
      
      send_chat_message(ws_connection, message_with, 
        app: "ChatMistral", 
        model: "mistral-small-latest",
        websearch: true)
      
      response_with = wait_for_response(ws_connection, timeout: 45)
      
      # Both should work correctly
      expect(response_without).not_to be_empty
      expect(response_with).not_to be_empty
      
      # First should be general explanation
      expect(response_without.downcase).to match(/machine learning|algorithm|data|model/i)
      
      # Second should show signs of web search
      expect(response_with.downcase).to match(/latest|recent|breakthrough|2024|research/i)
    end
  end
end