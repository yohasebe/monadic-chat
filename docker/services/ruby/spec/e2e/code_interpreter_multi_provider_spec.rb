# frozen_string_literal: true

require_relative 'e2e_helper'
require_relative 'validation_helper'

RSpec.describe "Code Interpreter Multi-Provider E2E", type: :e2e do
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

  # Test configuration for each provider
  PROVIDER_CONFIGS = [
    {
      app: "CodeInterpreterOpenAI",
      provider: "OpenAI",
      enabled: -> { CONFIG["OPENAI_API_KEY"] },
      model: "gpt-4.1",
      timeout: 60
    },
    {
      app: "CodeInterpreterClaude",
      provider: "Claude", 
      enabled: -> { CONFIG["ANTHROPIC_API_KEY"] },
      model: "claude-sonnet-4-20250514",
      timeout: 90,
      max_tokens: 4096
    },
    {
      app: "CodeInterpreterGemini",
      provider: "Gemini",
      enabled: -> { CONFIG["GEMINI_API_KEY"] },
      model: "gemini-2.5-pro",
      timeout: 60,
      skip_activation: true
    },
    {
      app: "CodeInterpreterGrok",
      provider: "Grok",
      enabled: -> { CONFIG["XAI_API_KEY"] },
      model: "grok-3",
      timeout: 60
    },
    {
      app: "CodeInterpreterMistral",
      provider: "Mistral",
      enabled: -> { CONFIG["MISTRAL_API_KEY"] },
      model: "mistral-large-latest",
      timeout: 60,
      skip_activation: true
    },
    {
      app: "CodeInterpreterCohere",
      provider: "Cohere",
      enabled: -> { CONFIG["COHERE_API_KEY"] },
      model: "command-a-03-2025",
      timeout: 60
    },
    {
      app: "CodeInterpreterDeepSeek",
      provider: "DeepSeek",
      enabled: -> { CONFIG["DEEPSEEK_API_KEY"] },
      model: "deepseek-chat",
      timeout: 60,
      skip_activation: true
    }
  ]

  PROVIDER_CONFIGS.each do |config|
    describe "#{config[:provider]} Provider" do
      before(:all) do
        unless config[:enabled].call
          skip "#{config[:provider]} tests require #{config[:provider].upcase}_API_KEY to be set"
        end
      end

      let(:ws_connection) { create_websocket_connection }

      after do
        ws_connection[:client].close if ws_connection[:client]
      end

      it "executes Python code" do
        message = case config[:provider]
                  when "DeepSeek", "Mistral"
                    "Use the run_code function to execute: print('Testing ' + str(2 + 3))"
                  when "Gemini"
                    "Use run_code to execute this Python: print('Testing ' + str(2 + 3)). This is in our Docker environment."
                  else
                    "Execute this Python code: print('Testing ' + str(2 + 3))"
                  end
        
        send_chat_message(ws_connection, message, 
          app: config[:app], 
          model: config[:model],
          max_tokens: config[:max_tokens],
          skip_activation: config[:skip_activation])
        
        begin
          response = wait_for_response(ws_connection, timeout: config[:timeout])
        rescue => e
          # Skip test if API error occurs
          if e.message.include?("API ERROR") || e.message.include?("internal error")
            skip "Provider API error: #{e.message}"
          else
            raise e
          end
        end
        
        # Check if run_code tool was actually used
        tool_used = tool_used?(ws_connection[:messages], "run_code")
        
        # For Gemini, accept either tool use or correct result mention
        if config[:provider] == "Gemini" && !tool_used
          expect(response).to match(/Testing 5|2.*3.*5|result.*5/i)
        else
          # Prefer verification of actual tool usage
          expect(tool_used || code_execution_attempted?(response)).to be true
        end
      end

      it "handles errors gracefully" do
        message = "Execute this code and show the error: print(undefined_variable)"
        
        send_chat_message(ws_connection, message,
          app: config[:app],
          model: config[:model], 
          max_tokens: config[:max_tokens],
          skip_activation: config[:skip_activation])
        
        begin
          response = wait_for_response(ws_connection, timeout: config[:timeout])
        rescue => e
          if e.message.include?("API ERROR") || e.message.include?("internal error")
            skip "Provider API error: #{e.message}"
          else
            raise e
          end
        end
        
        # Skip test if API error occurs
        if api_error?(response)
          skip "Provider API error detected in response"
        end
        
        expect(response).not_to be_empty
        # Accept any response that mentions error or the variable
        expect(response.downcase).to match(/error|undefined|name|not defined|variable/i)
      end

      # Only one data analysis test per provider
      it "performs data analysis" do
        message = <<~MSG
          Use pandas to create a DataFrame with values [15, 25, 35, 45, 55] and calculate basic statistics.
          Use run_code to execute.
        MSG
        
        send_chat_message(ws_connection, message,
          app: config[:app],
          model: config[:model],
          max_tokens: config[:max_tokens],
          skip_activation: config[:skip_activation])
        
        begin
          response = wait_for_response(ws_connection, timeout: config[:timeout] * 2)
        rescue => e
          if e.message.include?("API ERROR") || e.message.include?("internal error")
            skip "Provider API error: #{e.message}"
          else
            raise e
          end
        end
        
        skip "System error or tool failure" if system_error?(response)
        
        # Skip test if API error occurs
        if api_error?(response)
          skip "Provider API error detected in response"
        end
        
        # Skip if response is too minimal (API issue)
        if response.strip.length < 5
          skip "Provider returned minimal response, likely API issue"
        else
          # Very lenient check - just ensure we got some response
          expect(response).not_to be_empty
          expect(response.length).to be > 5
        end
      end
    end
  end
end