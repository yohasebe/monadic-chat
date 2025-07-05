# frozen_string_literal: true

require_relative "e2e_helper"

RSpec.describe "Chat Apps Web Search E2E", :e2e do
  include E2EHelper

  before(:all) do
    unless check_containers_running
      skip "E2E tests require containers to be running."
    end
    
    unless wait_for_server
      skip "E2E tests require server to be running on localhost:4567."
    end
  end

  # Test a subset of providers for web search functionality
  WEB_SEARCH_TEST_CONFIGS = [
    {
      app: "ChatOpenAI",
      provider: "OpenAI",
      enabled: -> { CONFIG["OPENAI_API_KEY"] },
      model: "gpt-4o"
    }
  ]

  WEB_SEARCH_TEST_CONFIGS.each do |config|
    describe "#{config[:provider]} Chat Web Search" do
      before(:all) do
        unless config[:enabled].call
          skip "#{config[:provider]} tests require #{config[:provider].upcase.gsub('CLAUDE', 'ANTHROPIC')}_API_KEY to be set"
        end
      end

      let!(:ws_connection) { create_websocket_connection }

      after(:each) do
        if ws_connection && ws_connection[:client]
          ws_connection[:client].close
          sleep 0.5  # Give time for connection to close properly
        end
      end

      it "responds appropriately to current events questions without web search enabled" do
        message = "What's the latest news about artificial intelligence today?"
        
        send_chat_message(ws_connection, message, 
          app: config[:app], 
          model: config[:model],
          websearch: false)  # Explicitly disable web search
        
        response = wait_for_response(ws_connection, timeout: 30)
        
        # Should get a response acknowledging the limitation or using training data
        expect(response).not_to be_empty
        
        # Should either mention lack of current info or provide general AI information
        expect(response.downcase).to match(/don't have access|cannot access|current|real-time|knowledge cutoff|training data|generally|artificial intelligence|may not have|up to date|unable to provide/i)
      end

      it "provides general information without real-time search" do
        # Ask about a well-known entity without current info
        message = "Tell me about OpenAI"
        
        send_chat_message(ws_connection, message, 
          app: config[:app], 
          model: config[:model],
          websearch: false)  # Explicitly disable web search
        
        response = wait_for_response(ws_connection, timeout: 30)
        
        expect(response).not_to be_empty
        expect(response.length).to be > 100  # Should have substantive information
        
        # Should mention OpenAI or related terms from training data
        expect(response.downcase).to match(/openai|artificial intelligence|gpt|ai/i)
        
        # Should not claim to have latest/current information
        expect(response.downcase).not_to match(/latest developments|recent announcements|just announced/i)
      end

      it "maintains general chat capabilities alongside web search" do
        # Test that it still works as a general chat without needing search
        message = "Write a haiku about programming"
        
        send_chat_message(ws_connection, message, 
          app: config[:app], 
          model: config[:model],
          websearch: false)  # Explicitly disable web search
        
        response = wait_for_response(ws_connection, timeout: 30)
        
        expect(response).not_to be_empty
        # Should contain a haiku (3 lines or forward slashes indicating line breaks)
        expect(response).to match(/\n.*\n|\/.*\//)
      end
    end
  end
end