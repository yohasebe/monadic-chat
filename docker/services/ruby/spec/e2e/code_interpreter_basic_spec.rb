# frozen_string_literal: true

require_relative 'e2e_helper'
require_relative 'validation_helper'
require_relative 'shared_examples/code_interpreter_examples'

RSpec.describe "Code Interpreter Basic E2E", type: :e2e do
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

  # Test only with OpenAI as the reference implementation
  describe "Core Functionality (OpenAI)" do
    let(:ws_connection) { create_websocket_connection }
    
    after do
      ws_connection[:client].close if ws_connection[:client]
    end

    before(:all) do
      unless CONFIG["OPENAI_API_KEY"]
        skip "OpenAI tests require OPENAI_API_KEY to be set"
      end
    end

    # Include basic shared examples
    include_examples "code interpreter basic functionality", "CodeInterpreterOpenAI", 
      model: "gpt-4.1"
    include_examples "code interpreter error handling", "CodeInterpreterOpenAI",
      model: "gpt-4.1"

    it "persists data between executions" do
      # First execution
      message1 = "Execute: my_list = [10, 20, 30, 40, 50]"
      send_chat_message(ws_connection, message1, app: "CodeInterpreterOpenAI")
      response1 = wait_for_response(ws_connection)
      expect(code_execution_attempted?(response1)).to be true
      
      ws_connection[:messages].clear
      
      # Second execution using previous data
      message2 = "Using my_list from before, calculate the sum"
      send_chat_message(ws_connection, message2, app: "CodeInterpreterOpenAI")
      response2 = wait_for_response(ws_connection)
      expect(code_execution_attempted?(response2)).to be true
    end

    it "handles data visualization" do
      message = <<~MSG
        Create a simple bar chart with matplotlib showing values [10, 25, 30, 15, 20]
        Save it as 'test_chart.png'
      MSG
      
      send_chat_message(ws_connection, message, app: "CodeInterpreterOpenAI")
      response = wait_for_response(ws_connection, timeout: 90)
      
      expect(code_execution_attempted?(response)).to be true
      expect(response.downcase).to match(/chart|plot|matplotlib|save/i)
    end
  end

  # Test cross-provider consistency with minimal tests
  describe "Cross-Provider Consistency" do
    # Only test providers that are configured
    MINIMAL_PROVIDER_CONFIGS = [
      { app: "CodeInterpreterClaude", provider: "Claude", key: "ANTHROPIC_API_KEY", model: "claude-sonnet-4-20250514", max_tokens: 4096 },
      { app: "CodeInterpreterGemini", provider: "Gemini", key: "GEMINI_API_KEY", model: "gemini-2.5-pro", skip_activation: true },
      { app: "CodeInterpreterMistral", provider: "Mistral", key: "MISTRAL_API_KEY", model: "mistral-large-latest", skip_activation: true }
    ]

    MINIMAL_PROVIDER_CONFIGS.each do |config|
      context "#{config[:provider]} Provider" do
        before(:all) do
          unless CONFIG[config[:key]]
            skip "#{config[:provider]} tests require #{config[:key]} to be set"
          end
        end

        let(:ws_connection) { create_websocket_connection }
        
        after do
          ws_connection[:client].close if ws_connection[:client]
        end

        it "executes basic Python code" do
          message = "Use run_code to calculate: print(100 + 200)"
          send_chat_message(ws_connection, message, 
            app: config[:app], 
            model: config[:model],
            max_tokens: config[:max_tokens],
            skip_activation: config[:skip_activation])
          
          response = wait_for_response(ws_connection, timeout: 60)
          
          expect(valid_response?(response)).to be true
          expect(code_execution_attempted?(response)).to be true
        end
      end
    end
  end
end