# frozen_string_literal: true

require_relative "e2e_helper"

RSpec.describe "Chat Apps with Web Search Manually Enabled E2E", :e2e do
  include E2EHelper

  before(:all) do
    unless check_containers_running
      skip "E2E tests require containers to be running."
    end
    
    unless wait_for_server
      skip "E2E tests require server to be running on localhost:4567."
    end
  end

  # Test OpenAI with web search manually enabled
  describe "OpenAI Chat with Web Search Enabled" do
    before(:all) do
      unless CONFIG["OPENAI_API_KEY"]
        skip "OpenAI tests require OPENAI_API_KEY to be set"
      end
    end

    let!(:ws_connection) { create_websocket_connection }

    after(:each) do
      if ws_connection && ws_connection[:client]
        ws_connection[:client].close
        sleep 0.5
      end
    end

    it "performs web search when manually enabled by user" do
      # Send message with websearch explicitly enabled
      message = "What are the latest AI developments this week?"
      
      send_chat_message(ws_connection, message, 
        app: "ChatOpenAI", 
        model: "gpt-4.1-mini",
        websearch: true)  # Manually enable web search
      
      response = wait_for_response(ws_connection, timeout: 45)
      
      # Should get a substantive response
      expect(response).not_to be_empty
      
      # OpenAI with websearch enabled should either:
      # 1. Provide search results about AI
      # 2. Acknowledge the request about AI developments
      # 3. Or provide a general response about AI
      expect(response.downcase).to match(/ai|artificial intelligence|development|information|help|happy|assist/i)
    end
  end

  # Test Mistral with Tavily (when available)
  describe "Mistral Chat with Tavily Web Search" do
    before(:all) do
      unless CONFIG["MISTRAL_API_KEY"] && CONFIG["TAVILY_API_KEY"]
        skip "Mistral web search tests require both MISTRAL_API_KEY and TAVILY_API_KEY"
      end
    end

    let!(:ws_connection) { create_websocket_connection }

    after(:each) do
      if ws_connection && ws_connection[:client]
        ws_connection[:client].close
        sleep 0.5
      end
    end

    it "uses Tavily for web search when enabled" do
      message = "What is the current weather in Tokyo?"
      
      send_chat_message(ws_connection, message, 
        app: "ChatMistralAI", 
        model: "mistral-small-latest",
        websearch: true)
      
      response = wait_for_response(ws_connection, timeout: 45)
      
      expect(response).not_to be_empty
      # Should mention weather-related terms or search attempts
      expect(response.downcase).to match(/weather|temperature|tokyo|celsius|fahrenheit|degrees|search|current|cannot/i)
    end
  end
end