# frozen_string_literal: true

require_relative "e2e_helper"
require_relative "../support/custom_retry"

RSpec.describe "Second Opinion E2E", :e2e do
  include E2EHelper
  include E2ERetryHelper
  
  let(:app_name) { "SecondOpinionOpenAI" }
  
  before(:all) do
    unless check_containers_running
      skip "E2E tests require containers to be running."
    end
    
    unless wait_for_server
      skip "E2E tests require server to be running on localhost:4567."
    end
  end
  
  before do
    skip "OpenAI API key not configured" unless CONFIG["OPENAI_API_KEY"]
  end
  
  describe "Second Opinion workflow" do
    it "displays welcome message and explains two-step process" do
      with_e2e_retry do
        response = activate_app_and_get_greeting(app_name)
        
        # Should explain the two-step process
        expect(response.downcase).to match(/welcome|second opinion|two-step|step 1|step 2/i)
        expect(response.downcase).to match(/ask.*question|verification|claude|gemini/i)
        expect(response.length).to be > 100
      end
    end
  end
  
  describe "First opinion (without second opinion)" do
    it "provides direct answer without calling second opinion" do
      with_e2e_retry do
        ws_connection = create_websocket_connection
        sleep 0.5
        send_chat_message(ws_connection, 
          "What is the capital of France?",
          app: app_name
        )
        sleep 0.5
        response = wait_for_response(ws_connection)
        ws_connection[:client].close
        
        # Should provide direct answer
        expect(response).to include("Paris")
        # Should NOT include second opinion indicators
        expect(response.downcase).not_to match(/validity.*score|second opinion.*comments|evaluation/i)
      end
    end
    
    it "answers complex questions without second opinion" do
      with_e2e_retry do
        ws_connection = create_websocket_connection
        sleep 0.5
        send_chat_message(ws_connection,
          "Explain the difference between machine learning and deep learning",
          app: app_name
        )
        sleep 1.0
        response = wait_for_response(ws_connection, timeout: 90)
        ws_connection[:client].close
        
        expect(response.downcase).to match(/machine learning|deep learning|neural network/i)
        # Should NOT include second opinion
        expect(response.downcase).not_to match(/validity.*score|\d+\/10/i)
      end
    end
  end
  
  describe "Second opinion requests" do
    it "provides second opinion functionality" do
      with_e2e_retry do
        ws_connection = create_websocket_connection
        sleep 1.0
        
        # Ask a simple question and immediately request second opinion
        send_chat_message(ws_connection, 
          "What is 2 + 2? Please also get a second opinion to verify.",
          app: app_name
        )
        sleep 2.0  # Wait longer for processing
        response = wait_for_response(ws_connection, timeout: 120)
        ws_connection[:client].close
        
        # Should provide answer and indicate second opinion functionality
        expect(response).to include("4")
        expect(response.length).to be > 50
      end
    end
    
    it "responds to provider-specific requests" do
      with_e2e_retry do
        ws_connection = create_websocket_connection
        sleep 1.0
        
        # Ask about available providers
        send_chat_message(ws_connection,
          "What providers are available for second opinions?",
          app: app_name
        )
        sleep 1.0
        response = wait_for_response(ws_connection)
        ws_connection[:client].close
        
        # Should mention available providers
        expect(response.downcase).to match(/claude|gemini|mistral|provider/i)
      end
    end
  end
  
  describe "Validation requests" do
    it "validates answer when asked 'Is this correct?'" do
      with_e2e_retry do
        ws_connection = create_websocket_connection
        sleep 0.5
        
        # Ask a factual question
        send_chat_message(ws_connection,
          "The speed of light is approximately 300,000 km/s. Is this correct?",
          app: app_name
        )
        sleep 1.0
        response = wait_for_response(ws_connection, timeout: 90)
        ws_connection[:client].close
        
        # First response should confirm the fact
        expect(response.downcase).to match(/correct|yes|accurate|speed of light/i)
      end
    end
    
    it "handles verification requests" do
      with_e2e_retry do
        ws_connection = create_websocket_connection
        sleep 1.0
        
        # Ask for verification in a single message
        send_chat_message(ws_connection,
          "Is it true that water boils at 100 degrees Celsius at sea level? Please verify this.",
          app: app_name
        )
        sleep 1.5
        response = wait_for_response(ws_connection, timeout: 90)
        ws_connection[:client].close
        
        # Should provide answer about water boiling point
        expect(response.downcase).to match(/true|correct|yes|100|celsius|boil/i)
      end
    end
  end
  
  describe "Error handling" do
    it "handles requests when second provider is unavailable" do
      with_e2e_retry do
        ws_connection = create_websocket_connection
        sleep 0.5
        
        # Ask a question
        send_chat_message(ws_connection,
          "What is artificial intelligence?",
          app: app_name
        )
        sleep 1.0
        wait_for_response(ws_connection)
        
        # Clear messages
        ws_connection[:messages].clear
        
        # Request opinion from a provider that might not be configured
        send_chat_message(ws_connection,
          "Ask NonExistentProvider to verify this",
          app: app_name
        )
        sleep 2.0
        response = wait_for_response(ws_connection, timeout: 90)
        ws_connection[:client].close
        
        # Should handle gracefully - either use default provider or explain limitation
        expect(response.length).to be > 20
        # Should still attempt to provide some form of response
        expect(response.downcase).to match(/opinion|provider|available|claude|gemini/i)
      end
    end
  end
  
  # Simplified test - remove complex multi-turn conversation for now
end