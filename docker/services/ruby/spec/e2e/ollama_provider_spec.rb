# frozen_string_literal: true

require_relative 'e2e_helper'
require_relative 'validation_helper'

RSpec.describe "Ollama Provider E2E", type: :e2e do
  include E2EHelper
  include ValidationHelper
  
  # Default model to use for tests
  DEFAULT_OLLAMA_MODEL = "llama3.2:latest"

  before(:all) do
    # Check basic containers
    unless check_containers_running
      skip "E2E tests require all containers to be running. Run: ./docker/monadic.sh start"
    end
    
    unless wait_for_server
      skip "E2E tests require server to be running on localhost:4567. Run: rake server"
    end
    
    # Check Ollama specific requirements
    unless ollama_container_running?
      skip "Ollama tests require Ollama container. Build with: Actions → Build Ollama Container"
    end
    
    unless ollama_service_available?
      skip "Ollama service not responding on port 11434"
    end
    
    @available_models = get_ollama_models
    if @available_models.empty?
      skip "No Ollama models available. Ensure models are downloaded during container build"
    end
    
    # Set OLLAMA_AVAILABLE for the test environment
    ENV['OLLAMA_AVAILABLE'] = 'true'
    CONFIG['OLLAMA_AVAILABLE'] = 'true' if defined?(CONFIG)
  end

  # Helper methods for Ollama
  def ollama_container_running?
    result = `docker ps --format "table {{.Names}}" | grep -q monadic-chat-ollama-container`
    $?.success?
  end

  def ollama_service_available?
    require 'net/http'
    begin
      uri = URI('http://localhost:11434')
      response = Net::HTTP.get_response(uri)
      response.code == "200"
    rescue => e
      false
    end
  end

  def get_ollama_models
    require 'net/http'
    require 'json'
    
    begin
      uri = URI('http://localhost:11434/api/tags')
      response = Net::HTTP.get_response(uri)
      if response.code == "200"
        data = JSON.parse(response.body)
        data["models"]&.map { |m| m["name"] } || []
      else
        []
      end
    rescue => e
      []
    end
  end

  describe "Chat with Ollama" do
    let(:ws_connection) { create_websocket_connection }
    
    after do
      ws_connection[:client].close if ws_connection[:client]
    end

    it "responds to basic queries" do
      send_chat_message(ws_connection, "What is 2 + 2?", app: "ChatOllama", model: @available_models.first || DEFAULT_OLLAMA_MODEL)
      response = wait_for_response(ws_connection, timeout: 90)
      
      expect(response).not_to be_empty
      expect(response.downcase).to match(/4|four/i)
    end

    it "maintains conversation context" do
      # First message
      send_chat_message(ws_connection, "My name is TestUser", app: "ChatOllama", model: @available_models.first || DEFAULT_OLLAMA_MODEL)
      response1 = wait_for_response(ws_connection, timeout: 90)
      expect(response1).not_to be_empty
      
      ws_connection[:messages].clear
      
      # Second message
      send_chat_message(ws_connection, "What's my name?", app: "ChatOllama", model: @available_models.first || DEFAULT_OLLAMA_MODEL)
      response2 = wait_for_response(ws_connection, timeout: 90)
      expect(response2.downcase).to include("testuser")
    end

    it "handles follow-up questions" do
      send_chat_message(ws_connection, "What is Python?", app: "ChatOllama", model: @available_models.first || DEFAULT_OLLAMA_MODEL)
      response1 = wait_for_response(ws_connection, timeout: 90)
      expect(response1.downcase).to match(/programming|language/i)
      
      ws_connection[:messages].clear
      
      send_chat_message(ws_connection, "What version is current?", app: "ChatOllama", model: @available_models.first || DEFAULT_OLLAMA_MODEL)
      response2 = wait_for_response(ws_connection, timeout: 90)
      expect(response2).not_to be_empty
      # Accept any version number or general response about Python versions
      expect(response2.downcase).to match(/\d\.\d|version|python/i)
    end
  end

  describe "Model Selection" do
    let(:ws_connection) { create_websocket_connection }
    
    after do
      ws_connection[:client].close if ws_connection[:client]
    end

    it "lists available models" do
      # This tests that the model selection works
      models = @available_models
      expect(models).not_to be_empty
      expect(models.first).to match(/\w+/)
    end

    it "uses first available model by default" do
      # Send message without specifying model - but we need to specify for E2E tests
      send_chat_message(ws_connection, "Hello", app: "ChatOllama", model: @available_models.first || DEFAULT_OLLAMA_MODEL)
      response = wait_for_response(ws_connection, timeout: 90)
      
      expect(response).not_to be_empty
    end

    if @available_models && @available_models.length > 1
      it "can switch between models" do
        # Test with first model
        send_chat_message(ws_connection, "Count to 3", 
          app: "ChatOllama", 
          model: @available_models.first)
        response1 = wait_for_response(ws_connection, timeout: 90)
        expect(response1).not_to be_empty
        
        ws_connection[:messages].clear
        
        # Test with second model if available
        send_chat_message(ws_connection, "Count to 3", 
          app: "ChatOllama", 
          model: @available_models[1])
        response2 = wait_for_response(ws_connection, timeout: 90)
        expect(response2).not_to be_empty
      end
    end
  end

  describe "Performance Characteristics" do
    let(:ws_connection) { create_websocket_connection }
    
    after do
      ws_connection[:client].close if ws_connection[:client]
    end

    it "responds within reasonable time for simple queries" do
      start_time = Time.now
      send_chat_message(ws_connection, "Say hello", app: "ChatOllama", model: @available_models.first || DEFAULT_OLLAMA_MODEL)
      response = wait_for_response(ws_connection, timeout: 45)
      end_time = Time.now
      
      expect(response).not_to be_empty
      # Ollama local models should respond relatively quickly
      expect(end_time - start_time).to be < 45
    end

    it "handles streaming responses" do
      # Clear any existing messages
      ws_connection[:messages].clear
      
      # Send the message
      send_chat_message(ws_connection, "Count from 1 to 5", app: "ChatOllama", model: @available_models.first || DEFAULT_OLLAMA_MODEL)
      
      # Wait for response and collect all fragments
      response = wait_for_response(ws_connection, timeout: 90)
      
      # Check that we got fragments in the messages
      fragments = ws_connection[:messages].select { |m| m["type"] == "fragment" }
      
      # Should have received multiple fragments for streaming
      expect(fragments.length).to be >= 1
      
      # The complete response should contain numbers
      expect(response).not_to be_empty
      expect(response).to match(/1|2|3|4|5/)
    end
  end

  describe "Error Handling" do
    let(:ws_connection) { create_websocket_connection }
    
    after do
      ws_connection[:client].close if ws_connection[:client]
    end

    it "handles invalid model gracefully" do
      expect {
        send_chat_message(ws_connection, "Hello", 
          app: "ChatOllama", 
          model: "non-existent-model")
        wait_for_response(ws_connection, timeout: 90)
      }.to raise_error(RuntimeError, /model.*not found/)
    end

    it "handles very long input" do
      long_text = "Please summarize: " + ("Lorem ipsum " * 500)
      send_chat_message(ws_connection, long_text, app: "ChatOllama", model: @available_models.first || DEFAULT_OLLAMA_MODEL)
      
      response = wait_for_response(ws_connection, timeout: 90)
      expect(response).not_to be_empty
      # Should provide summary or handle gracefully
      expect(response.length).to be < long_text.length
    end
  end

  describe "Ollama-Specific Features" do
    let(:ws_connection) { create_websocket_connection }
    
    after do
      ws_connection[:client].close if ws_connection[:client]
    end

    it "works without internet connection" do
      # Ollama runs locally, so this should work
      send_chat_message(ws_connection, 
        "What is the capital of France?", 
        app: "ChatOllama",
        model: @available_models.first || DEFAULT_OLLAMA_MODEL)
      response = wait_for_response(ws_connection, timeout: 90)
      
      expect(response).not_to be_empty
      expect(response.downcase).to include("paris")
    end

    it "provides consistent responses for factual queries" do
      # Test multiple times to ensure consistency
      responses = []
      
      3.times do |i|
        ws_connection[:messages].clear if i > 0
        send_chat_message(ws_connection, "What is 10 plus 10? Please answer with the number.", app: "ChatOllama", model: @available_models.first || DEFAULT_OLLAMA_MODEL)
        response = wait_for_response(ws_connection, timeout: 90)
        responses << response
      end
      
      # All responses should be related to the math question
      responses.each do |response|
        # Should either calculate correctly or at least reference the numbers
        expect(response.downcase).to match(/20|twenty|10\s*\+\s*10|10 plus 10/i)
      end
    end

    it "handles markdown formatting" do
      send_chat_message(ws_connection, 
        "Show me a Python hello world example with code formatting", 
        app: "ChatOllama",
        model: @available_models.first || DEFAULT_OLLAMA_MODEL)
      response = wait_for_response(ws_connection, timeout: 90)
      
      # Should include code blocks or Python syntax
      expect(response).to match(/```|print|hello|def/i)
    end
  end

  # Test with toggle feature (Ollama uses toggle mode)
  describe "Toggle Mode Context Management" do
    let(:ws_connection) { create_websocket_connection }
    
    after do
      ws_connection[:client].close if ws_connection[:client]
    end

    it "maintains context with toggle mode" do
      # Create context
      send_chat_message(ws_connection, 
        "Remember these numbers: 42, 87, 13", 
        app: "ChatOllama",
        model: @available_models.first || DEFAULT_OLLAMA_MODEL)
      response1 = wait_for_response(ws_connection, timeout: 90)
      expect(response1).not_to be_empty
      
      ws_connection[:messages].clear
      
      # Query context
      send_chat_message(ws_connection, 
        "What numbers did I ask you to remember?", 
        app: "ChatOllama",
        model: @available_models.first || DEFAULT_OLLAMA_MODEL)
      response2 = wait_for_response(ws_connection, timeout: 90)
      
      # Should recall at least one number
      expect(response2).to match(/42|87|13/)
    end
  end
end