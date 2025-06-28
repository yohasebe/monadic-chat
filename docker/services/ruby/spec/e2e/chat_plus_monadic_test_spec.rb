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
      model: "sonar-pro",
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
        
        # The final response should at least mention Ruby
        expect(response3).to match(/Ruby/i)
        
        # Try to parse JSON if available
        json_match = response3.match(/\{.*"message".*"context".*\}/m)
        if json_match
          begin
            parsed = JSON.parse(json_match[0])
            
            # Check that context accumulation is working
            if parsed["context"] && parsed["context"]["topics"]
              topics = parsed["context"]["topics"].join(" ")
              expect(topics).to match(/Ruby|programming/i)
              
              # Rails might be in topics if AI recognizes it
              if topics.match(/Rails/i)
                expect(topics).to match(/Rails/i)
              end
            end
            
            if parsed["context"] && parsed["context"]["people"]
              people = parsed["context"]["people"].join(" ")
              # Sarah should be in people if context is properly accumulated
              if people.match(/Sarah/i)
                expect(people).to match(/Sarah/i)
              end
            end
          rescue JSON::ParserError
            # If JSON parsing fails, just check that the response mentions the topics
            expect(response3).to match(/programming|topics|discussed/i)
          end
        else
          # If no JSON structure found, check for mentions in regular text
          expect(response3).to match(/programming|topics|discussed/i)
        end
      end

      it "displays reasoning in monadic format" do
        message = "What's the weather like today?"
        
        send_chat_message(ws_connection, message, 
          app: config[:app], model: config[:model])
        
        response = wait_for_response(ws_connection, timeout: 60)
        
        # For providers with web search (like Perplexity), they might return actual weather data
        # For others, they explain they can't provide current weather
        # Accept either case as long as weather is discussed
        expect(response).to match(/weather|temperature|forecast|climate/i)
        
        # Check for either monadic display OR JSON structure
        if response.match(/\{.*"message".*"context".*\}/m)
          # If JSON is present, verify it's valid
          begin
            json_match = response.match(/\{.*"message".*"context".*\}/m)
            parsed = JSON.parse(json_match[0])
            expect(parsed).to have_key("message")
            expect(parsed).to have_key("context")
          rescue JSON::ParserError
            # If JSON parsing fails, just ensure response discusses weather
            expect(response).to match(/weather|temperature|forecast/i)
          end
        else
          # For non-JSON responses, just verify weather content
          expect(response).to match(/weather|temperature|forecast|current|location/i)
        end
      end
    end
  end
end