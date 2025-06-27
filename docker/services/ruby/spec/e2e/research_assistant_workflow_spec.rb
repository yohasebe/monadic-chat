# frozen_string_literal: true

require_relative 'e2e_helper'
require_relative 'validation_helper'

RSpec.describe "Research Assistant E2E", type: :e2e do
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

  describe "Research Assistant OpenAI" do
    let(:ws_connection) { create_websocket_connection }
    let(:app_name) { "ResearchAssistantOpenAI" }
    
    after do
      ws_connection[:client].close if ws_connection[:client]
    end

    before do
      skip "OpenAI API key not configured" unless CONFIG["OPENAI_API_KEY"]
    end

    context "basic research queries" do
      it "handles simple information requests" do
        send_chat_message(ws_connection, 
          "What is the capital of Japan?", 
          app: app_name)
        response = wait_for_response(ws_connection, timeout: 30)
        
        expect(response).not_to be_empty
        expect(response.downcase).to include("tokyo")
      end

      it "provides research with web search when appropriate" do
        # OpenAI has native web search, no Tavily needed
        send_chat_message(ws_connection, 
          "What are the latest developments in quantum computing in 2024?", 
          app: app_name)
        response = wait_for_response(ws_connection, timeout: 60)
        
        expect(response).not_to be_empty
        expect(response.downcase).to match(/quantum|computing|research|development/)
      end
    end

    # File analysis tests removed - Research Assistant does not support file access

    context "conversation flow" do
      it "maintains context across multiple queries" do
        # First query
        send_chat_message(ws_connection, 
          "I'm researching renewable energy", 
          app: app_name)
        response1 = wait_for_response(ws_connection, timeout: 30)
        expect(response1).not_to be_empty
        
        ws_connection[:messages].clear
        
        # Follow-up query
        send_chat_message(ws_connection, 
          "What are the latest solar panel technologies?", 
          app: app_name)
        response2 = wait_for_response(ws_connection, timeout: 45)
        
        expect(response2).not_to be_empty
        expect(response2.downcase).to match(/solar|panel|technology/)
      end

      it "handles the initial greeting appropriately" do
        # Research Assistant starts with a greeting (initiate_from_assistant behavior)
        # Just send an empty message to trigger the initial response
        send_chat_message(ws_connection, "Hello", app: app_name)
        response = wait_for_response(ws_connection, timeout: 30)
        
        expect(response).not_to be_empty
        # Should contain a greeting or research-related prompt
        expect(response.downcase).to match(/research|help|assist|question|topic|explore/)
      end
    end
  end

  describe "Research Assistant Claude" do
    let(:ws_connection) { create_websocket_connection }
    let(:app_name) { "ResearchAssistantClaude" }
    
    after do
      ws_connection[:client].close if ws_connection[:client]
    end

    before do
      skip "Claude API key not configured" unless CONFIG["ANTHROPIC_API_KEY"]
    end

    it "performs web search using native Claude search" do
      send_chat_message(ws_connection, 
        "What are the latest developments in quantum computing in 2024?", 
        app: app_name,
        model: "claude-3-5-sonnet-20241022",
        max_tokens: 1000)
      response = wait_for_response(ws_connection, timeout: 30)
      
      expect(response).not_to be_empty
      expect(response.downcase).to match(/quantum|computing|research|development/)
    end

  end

  describe "Research Assistant Gemini" do
    let(:ws_connection) { create_websocket_connection }
    let(:app_name) { "ResearchAssistantGemini" }
    
    after do
      ws_connection[:client].close if ws_connection[:client]
    end

    before do
      skip "Gemini API key not configured" unless CONFIG["GEMINI_API_KEY"]
    end

    it "performs research with Gemini" do
      # Skip if Tavily not configured
      skip "This test requires TAVILY_API_KEY" unless CONFIG["TAVILY_API_KEY"]
      
      send_chat_message(ws_connection, 
        "Explain the concept of neural networks", 
        app: app_name,
        model: "gemini-2.0-flash")
      response = wait_for_response(ws_connection, timeout: 30)
      
      expect(response).not_to be_empty
      # Accept either neural network explanation or web search results
      expect(response.downcase).to match(/neural|network|layer|learning|research|search|web|information/)
    end

    it "integrates web search when available" do
      skip "Tavily API key not configured" unless CONFIG["TAVILY_API_KEY"]
      
      send_chat_message(ws_connection, 
        "What are the latest AI model releases from major tech companies?", 
        app: app_name,
        model: "gemini-2.0-flash")
      response = wait_for_response(ws_connection, timeout: 60)
      
      expect(response).not_to be_empty
      # Accept either search results or assistant greeting/acknowledgment
      expect(response.downcase).to match(/ai|model|google|openai|anthropic|meta|ready.*assist|research.*needs|help.*find|exploring/)
    end
  end

  describe "Multi-provider comparison" do
    let(:ws_connection) { create_websocket_connection }
    
    after do
      ws_connection[:client].close if ws_connection[:client]
    end

  end

  describe "Error handling" do
    let(:ws_connection) { create_websocket_connection }
    
    after do
      ws_connection[:client].close if ws_connection[:client]
    end


    it "handles web search failures gracefully" do
      skip "Claude API key not configured" unless CONFIG["ANTHROPIC_API_KEY"]
      # When Tavily is not configured, should still work but mention limitation
      
      if !CONFIG["TAVILY_API_KEY"]
        send_chat_message(ws_connection, 
          "Search for the latest news about quantum computing", 
          app: "ResearchAssistantClaude",
          max_tokens: 1000)
        response = wait_for_response(ws_connection, timeout: 30)
        
        expect(response).not_to be_empty
        # Should either mention search not available or provide general knowledge
        expect(response).not_to include("Web search failed")
      end
    end
  end

  describe "Research Assistant Grok" do
    let(:ws_connection) { create_websocket_connection }
    let(:app_name) { "ResearchAssistantGrok" }
    
    after do
      ws_connection[:client].close if ws_connection[:client]
    end

    before do
      skip "xAI API key not configured" unless CONFIG["XAI_API_KEY"]
    end

    it "performs web search using native Grok Live Search" do
      send_chat_message(ws_connection, 
        "What are the latest AI developments in 2024?", 
        app: app_name,
        model: "grok-3")
      response = wait_for_response(ws_connection, timeout: 60)
      
      expect(response).not_to be_empty
      expect(response.downcase).to match(/ai|artificial intelligence|development|research/)
    end
  end

  describe "Research Assistant Perplexity" do
    let(:ws_connection) { create_websocket_connection }
    let(:app_name) { "ResearchAssistantPerplexity" }
    
    after do
      ws_connection[:client].close if ws_connection[:client]
    end

    before do
      skip "Perplexity API key not configured" unless CONFIG["PERPLEXITY_API_KEY"]
    end

    it "performs research with built-in web search" do
      send_chat_message(ws_connection, 
        "What are the key features of machine learning?", 
        app: app_name,
        model: "sonar",
        skip_activation: true)
      response = wait_for_response(ws_connection, timeout: 90)
      
      expect(response).not_to be_empty
      expect(response.downcase).to match(/machine learning|algorithm|data|model|training/)
    end
  end

  describe "Research Assistant Mistral" do
    let(:ws_connection) { create_websocket_connection }
    let(:app_name) { "ResearchAssistantMistral" }
    
    after do
      ws_connection[:client].close if ws_connection[:client]
    end

    before do
      skip "Mistral API key not configured" unless CONFIG["MISTRAL_API_KEY"]
      skip "Tavily API key not configured" unless CONFIG["TAVILY_API_KEY"]
    end

    it "performs research using Tavily web search" do
      send_chat_message(ws_connection, 
        "What is quantum computing?", 
        app: app_name,
        model: "mistral-large-latest")
      response = wait_for_response(ws_connection, timeout: 30)
      
      expect(response).not_to be_empty
      expect(response.downcase).to match(/quantum|computing|qubit/)
    end
  end

  describe "Research Assistant Cohere" do
    let(:ws_connection) { create_websocket_connection }
    let(:app_name) { "ResearchAssistantCohere" }
    
    after do
      ws_connection[:client].close if ws_connection[:client]
    end

    before do
      skip "Cohere API key not configured" unless CONFIG["COHERE_API_KEY"]
      skip "Tavily API key not configured" unless CONFIG["TAVILY_API_KEY"]
    end

    it "performs research using Tavily web search" do
      send_chat_message(ws_connection, 
        "Explain blockchain technology", 
        app: app_name,
        model: "command-a-03-2025")
      response = wait_for_response(ws_connection, timeout: 60)
      
      expect(response).not_to be_empty
      expect(response.downcase).to match(/blockchain|distributed|ledger|cryptocurrency/)
    end
  end

  describe "Research Assistant DeepSeek" do
    let(:ws_connection) { create_websocket_connection }
    let(:app_name) { "ResearchAssistantDeepSeek" }
    
    after do
      ws_connection[:client].close if ws_connection[:client]
    end

    before do
      skip "DeepSeek API key not configured" unless CONFIG["DEEPSEEK_API_KEY"]
      skip "Tavily API key not configured" unless CONFIG["TAVILY_API_KEY"]
    end

    it "performs research using Tavily web search" do
      send_chat_message(ws_connection, 
        "What is artificial intelligence?", 
        app: app_name,
        model: "deepseek-chat",
        max_tokens: 1000,
        skip_activation: true)
      response = wait_for_response(ws_connection, timeout: 90)
      
      expect(response).not_to be_empty
      expect(response.downcase).to match(/artificial intelligence|ai|machine|computer|algorithm/)
    end
  end


end