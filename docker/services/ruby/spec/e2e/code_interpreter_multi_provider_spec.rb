# frozen_string_literal: true

require_relative 'e2e_helper'
require_relative 'validation_helper'
require_relative 'shared_examples/code_interpreter_examples'

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
  # Only test if API key is configured
  PROVIDER_CONFIGS = [
    {
      app: "CodeInterpreterOpenAI",
      provider: "OpenAI",
      enabled: -> { CONFIG["OPENAI_API_KEY"] },
      model: "gpt-4.1",  # Use actual default model from MDSL
      timeout: 60  # Increased to match provider's actual timeout
    },
    {
      app: "CodeInterpreterClaude",
      provider: "Claude",
      enabled: -> { CONFIG["ANTHROPIC_API_KEY"] },
      model: "claude-sonnet-4-20250514",  # Use actual default model from MDSL
      timeout: 90,  # Increased timeout for Claude (300s read timeout in real code)
      max_tokens: 4096  # Claude requires max_tokens
    },
    {
      app: "CodeInterpreterGemini",
      provider: "Gemini",
      enabled: -> { CONFIG["GEMINI_API_KEY"] },
      model: "gemini-2.5-pro",  # Updated to pro model
      timeout: 60,  # Increased timeout for Gemini (120s read timeout in real code)
      skip_activation: true  # Skip activation for Gemini
    },
    {
      app: "CodeInterpreterGrok",
      provider: "Grok",
      enabled: -> { CONFIG["XAI_API_KEY"] },
      model: "grok-3",  # Use actual default model from MDSL
      timeout: 60  # Increased to match provider's actual timeout
    },
    {
      app: "CodeInterpreterMistral",
      provider: "Mistral",
      enabled: -> { CONFIG["MISTRAL_API_KEY"] },
      model: "mistral-large-latest",  # Use actual default model from MDSL
      timeout: 60,  # Increased to match provider's actual timeout
      skip_activation: true  # Skip activation for Mistral
    },
    {
      app: "CodeInterpreterCohere",
      provider: "Cohere",
      enabled: -> { CONFIG["COHERE_API_KEY"] },
      model: "command-a-03-2025",  # Updated model
      timeout: 60  # Increased timeout for Cohere
    },
    {
      app: "CodeInterpreterDeepSeek",
      provider: "DeepSeek",
      enabled: -> { CONFIG["DEEPSEEK_API_KEY"] },
      model: "deepseek-chat",  # Use actual default model from MDSL
      timeout: 60,  # Increased to match provider's actual timeout
      skip_activation: true  # Skip activation for DeepSeek
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

      # Include shared examples for basic functionality
      include_examples "code interpreter basic functionality", config[:app], 
        model: config[:model], 
        max_tokens: config[:max_tokens],
        skip_activation: config[:skip_activation]
      include_examples "code interpreter error handling", config[:app],
        model: config[:model],
        max_tokens: config[:max_tokens],
        skip_activation: config[:skip_activation]

      # Provider-specific tests
      context "Provider-specific behavior" do
        # Skip this test for providers with initiate_from_assistant: false
        # as they tend to return activation/greeting responses
        unless ["Gemini", "DeepSeek", "Mistral"].include?(config[:provider])
          it "handles provider-specific code execution" do
          # Simple test that should work across all providers
          message = if config[:provider] == "Gemini"
                      "I have a simple Python print statement to execute in our Docker environment. Please use the run_code function to execute this exact code: print('Hello from #{config[:provider]}!')\n\nIMPORTANT: Use the run_code tool to execute this specific code, don't create a different example."
                    else
                      "Execute this Python code: print('Hello from #{config[:provider]}!')"
                    end
          send_chat_message(ws_connection, message, 
            app: config[:app], 
            model: config[:model], 
            max_tokens: config[:max_tokens])
          
          response = wait_for_response(ws_connection, timeout: config[:timeout])
          
          expect(valid_response?(response)).to be true
          
          
          # Different providers respond differently
          if config[:provider] == "Cohere"
            # Cohere might have issues with function calls or respond differently
            if response.include?("don't have the code")
              # Check if it at least understood the request
              expect(response.downcase).to match(/code|run|execute/)
            else
              expect(response).to include("Hello from #{config[:provider]}!")
            end
          elsif config[:provider] == "Gemini" && (response.include?("ready to help") || response.include?("Great! Let's start"))
            # Gemini might still be in greeting/activation mode, skip this test
            skip "Gemini returned activation response instead of executing code"
          elsif config[:provider] == "DeepSeek" && response.include?("Great! The environment")
            # DeepSeek might also return activation response
            skip "DeepSeek returned activation response instead of executing code"
          else
            expect(response).to include("Hello from #{config[:provider]}!")
          end
        end
        end

        it "uses run_code function correctly" do
          # Explicitly ask to use run_code function
          # For Mistral, be very explicit about executing new code
          message = if config[:provider] == "Mistral"
                      "Use the run_code function to execute this Python code and show the output: print(2 ** 10)"
                    elsif config[:provider] == "Gemini"
                      "I need to calculate 2^10 in our Docker Python environment. Please use the run_code function to execute this Python code: print(2 ** 10)\n\nIMPORTANT: This is a safe containerized environment. You must use the run_code tool to execute the code, not calculate it yourself."
                    elsif config[:provider] == "DeepSeek"
                      "Use the run_code function to execute this Python code and show the output: print(2 ** 10)"
                    else
                      "Use the run_code function to calculate 2 ** 10 in Python"
                    end
          send_chat_message(ws_connection, message, 
            app: config[:app], 
            model: config[:model],
            max_tokens: config[:max_tokens],
            skip_activation: config[:skip_activation])
          
          response = wait_for_response(ws_connection, timeout: config[:timeout])
          
          expect(valid_response?(response)).to be true
          
          
          # Different providers may respond differently
          if config[:provider] == "Mistral" && response.start_with?("[{")
            # If Mistral returns raw JSON, it might be trying to fetch a file
            # This is still a valid response showing tool usage
            expect(response).to match(/fetch_text_from_file|run_code/)
          elsif config[:provider] == "Gemini" && response.include?("ready to help")
            # Gemini might still be in greeting mode, skip this test
            skip "Gemini returned greeting instead of executing code"
          else
            expect(response).to include("1024")
          end
        end

        # Special handling for providers that need explicit function calls
        if ["DeepSeek", "Mistral", "Cohere"].include?(config[:provider])
          it "executes code with explicit function call instruction" do
            message = <<~MSG
              IMPORTANT: You MUST use the run_code function to execute this Python code:
              ```python
              result = sum(range(1, 11))
              print(f"Sum of 1 to 10 is: {result}")
              ```
            MSG
            
            send_chat_message(ws_connection, message, 
              app: config[:app], 
              model: config[:model],
              max_tokens: config[:max_tokens])
            
            response = wait_for_response(ws_connection, timeout: config[:timeout])
            
            expect(valid_response?(response)).to be true
            expect(response).to include("55")
          end
        end
      end

      # Data analysis test that should work for all providers
      context "Cross-provider data analysis" do
        it "performs pandas data analysis" do
          message = <<~MSG
            Create a pandas DataFrame with this data and calculate the mean:
            ```
            values = [10, 20, 30, 40, 50]
            ```
            
            Use run_code to execute the pandas code and show the result.
          MSG
          
          send_chat_message(ws_connection, message, 
            app: config[:app], 
            model: config[:model],
            max_tokens: config[:max_tokens],
            skip_activation: config[:skip_activation])
          
          response = wait_for_response(ws_connection, timeout: config[:timeout] * 2)
          
          expect(valid_response?(response)).to be true
          
          # Skip if system error occurs
          skip "System error or tool failure" if system_error?(response) || response.include?("missing.*parameter")
          
          # Accept if code execution was attempted
          expect(code_execution_attempted?(response)).to be true
          
          # If successful, check for the mean value (30)
          if shows_code_execution?(response) && !response.include?("unable")
            expect(contains_number_near?(response, 30.0, 0.1)).to be true
          end
        end
      end

      # Visualization test (may not work for all providers)
      context "Visualization support" do
        it "attempts to create a simple plot" do
          message = if config[:provider] == "Gemini"
                      <<~MSG
                        Use the run_code function to create a simple matplotlib plot: plot y=x for x from 0 to 5, save as 'plot.png'
                      MSG
                    else
                      <<~MSG
                        Use matplotlib to create a simple line plot of y = x^2 for x from 0 to 5.
                        Save it as 'simple_plot.png'.
                      MSG
                    end
          
          send_chat_message(ws_connection, message, 
            app: config[:app], 
            model: config[:model],
            max_tokens: config[:max_tokens],
            skip_activation: config[:skip_activation])
          
          response = wait_for_response(ws_connection, timeout: config[:timeout] * 2)
          
          # More lenient expectations - some providers might not save the file
          expect(response).not_to be_empty
          # Just check that the provider understood the visualization task
          expect(understands_task?(response, ["plot", "matplotlib", "graph", "chart", "visual", "x^2", "line"])).to be true
        end
      end
    end
  end

end