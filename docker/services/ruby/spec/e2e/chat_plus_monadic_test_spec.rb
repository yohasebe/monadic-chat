# frozen_string_literal: true

require_relative "e2e_helper"

RSpec.describe "Chat Plus Monadic Mode E2E", :e2e do
  include E2EHelper

  before(:all) do
    unless check_containers_running
      skip "E2E tests require containers to be running."
    end
    
    unless wait_for_server
      skip "E2E tests require server to be running on localhost:4567."
    end
  end

  # Test configurations for each provider
  MONADIC_PROVIDER_CONFIGS = [
    {
      app: "ChatPlusOpenAI",
      provider: "OpenAI",
      enabled: -> { CONFIG["OPENAI_API_KEY"] },
      model: "gpt-4.1",
      supports_json_schema: true
    },
    {
      app: "ChatPlusDeepSeek",
      provider: "DeepSeek",
      enabled: -> { CONFIG["DEEPSEEK_API_KEY"] },
      model: "deepseek-chat",
      supports_json_schema: false
    },
    {
      app: "ChatPlusPerplexity",
      provider: "Perplexity",
      enabled: -> { CONFIG["PERPLEXITY_API_KEY"] },
      model: "llama-3.3-70b-versatile",
      supports_json_schema: false
    },
    {
      app: "ChatPlusGrok",
      provider: "Grok",
      enabled: -> { CONFIG["XAI_API_KEY"] },
      model: "grok-3",
      supports_json_schema: false
    }
  ]

  MONADIC_PROVIDER_CONFIGS.each do |config|
    describe "#{config[:provider]} Provider Monadic Mode" do
      before(:all) do
        unless config[:enabled].call
          skip "#{config[:provider]} tests require #{config[:provider].upcase.gsub('GROK', 'XAI')}_API_KEY to be set"
        end
      end

      let(:ws_connection) { create_websocket_connection }

      after do
        ws_connection[:client].close if ws_connection[:client]
      end

      it "returns properly structured JSON response with context" do
        message = "Hello! I'm planning a trip to Tokyo next month. My friend Yuki recommended visiting in spring."
        
        send_chat_message(ws_connection, message, 
          app: config[:app], 
          model: config[:model])
        
        response = wait_for_response(ws_connection, timeout: 60)
        
        # Parse the response to check JSON structure
        begin
          # The response might be wrapped in HTML for display
          json_match = response.match(/\{.*"message".*"context".*\}/m)
          if json_match
            parsed = JSON.parse(json_match[0])
            
            # Verify required fields exist
            expect(parsed).to have_key("message")
            expect(parsed).to have_key("context")
            expect(parsed["context"]).to have_key("reasoning")
            expect(parsed["context"]).to have_key("topics")
            expect(parsed["context"]).to have_key("people")
            expect(parsed["context"]).to have_key("notes")
            
            # Verify content makes sense
            expect(parsed["message"]).to match(/Tokyo|trip|travel|Japan/i)
            expect(parsed["context"]["topics"]).to include(match(/Tokyo|travel|trip/i))
            expect(parsed["context"]["people"]).to include(match(/Yuki/i))
          else
            # If no JSON found, at least verify monadic HTML structure
            expect(response).to match(/class="monadic-container"|data-monadic|toggleable/i)
          end
        rescue JSON::ParserError
          # If JSON parsing fails, check for monadic HTML structure
          expect(response).to match(/class="monadic-container"|data-monadic|toggleable/i)
        end
      end

      it "accumulates context across multiple messages" do
        # First message
        send_chat_message(ws_connection, "I'm learning Ruby programming.", 
          app: config[:app], model: config[:model])
        response1 = wait_for_response(ws_connection, timeout: 60)
        
        # Second message
        send_chat_message(ws_connection, "My colleague Sarah is helping me with Rails.", 
          app: config[:app], model: config[:model])
        response2 = wait_for_response(ws_connection, timeout: 60)
        
        # Third message
        send_chat_message(ws_connection, "What topics have we discussed so far?", 
          app: config[:app], model: config[:model])
        response3 = wait_for_response(ws_connection, timeout: 60)
        
        # The final response should mention both Ruby and Rails
        expect(response3).to match(/Ruby/i)
        expect(response3).to match(/Rails|Sarah/i)
        
        # Try to parse JSON if available
        json_match = response3.match(/\{.*"message".*"context".*\}/m)
        if json_match
          parsed = JSON.parse(json_match[0])
          topics = parsed["context"]["topics"].join(" ")
          people = parsed["context"]["people"].join(" ")
          
          expect(topics).to match(/Ruby|programming/i)
          expect(topics).to match(/Rails/i)
          expect(people).to match(/Sarah/i)
        end
      end

      it "displays reasoning in monadic format" do
        message = "What's the weather like today?"
        
        send_chat_message(ws_connection, message, 
          app: config[:app], model: config[:model])
        
        response = wait_for_response(ws_connection, timeout: 60)
        
        # Check for monadic HTML elements or JSON structure
        expect(response).to match(/reasoning|context|monadic-container|toggleable/i)
        
        # The reasoning should explain why it can't provide current weather
        expect(response).to match(/weather|current|real-time|location/i)
      end
    end
  end
end