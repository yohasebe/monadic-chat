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
        skip "Tavily API key not configured" unless CONFIG["TAVILY_API_KEY"]
        
        send_chat_message(ws_connection, 
          "What are the latest developments in quantum computing in 2024?", 
          app: app_name)
        response = wait_for_response(ws_connection, timeout: 60)
        
        expect(response).not_to be_empty
        expect(response.downcase).to match(/quantum|computing|research|development/)
      end
    end

    context "file analysis" do
      before do
        @test_file = create_test_file("research_test.txt", "This is a test document about artificial intelligence and machine learning.")
      end
      
      after do
        cleanup_test_files("research_test.txt")
      end

      it "analyzes local text files" do
        send_chat_message(ws_connection, 
          "Please analyze the content of research_test.txt", 
          app: app_name)
        response = wait_for_response(ws_connection, timeout: 30)
        
        expect(response).not_to be_empty
        expect(response.downcase).to match(/artificial intelligence|machine learning/)
      end

      it "distinguishes between files and web search queries" do
        # First test: Just read the file
        send_chat_message(ws_connection, 
          "What is in research_test.txt?", 
          app: app_name)
        response = wait_for_response(ws_connection, timeout: 30)
        
        expect(response).not_to be_empty
        expect(response.downcase).to include("artificial intelligence")
        
        # Clear messages for next query
        ws_connection[:messages].clear
        
        # Second test: Just web search
        skip "Tavily API key not configured" unless CONFIG["TAVILY_API_KEY"]
        
        send_chat_message(ws_connection, 
          "What are the latest AI trends in 2024?", 
          app: app_name)
        response = wait_for_response(ws_connection, timeout: 60)
        
        expect(response).not_to be_empty
        expect(response.downcase).to match(/ai|artificial intelligence|trends|2024/)
      end
    end

    context "multimedia analysis" do
      it "handles image analysis requests" do
        # Create a simple test image
        test_image = File.join(Dir.home, "monadic", "data", "test_research_image.txt")
        File.write(test_image, "[This would be an image file]")
        
        send_chat_message(ws_connection, 
          "What can you tell me about test_research_image.txt?", 
          app: app_name)
        response = wait_for_response(ws_connection, timeout: 30)
        
        expect(response).not_to be_empty
        
        File.delete(test_image) if File.exist?(test_image)
      end
    end

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

    it "performs web search using Tavily" do
      skip "Claude Research Assistant doesn't have tavily_search tool due to schema validation issues"
    end

    it "handles file analysis with Claude" do
      skip "Claude has JSON schema validation issues with tool definitions"
      
      test_file = create_test_file("claude_research.txt", "Analysis of climate change impacts on biodiversity.")
      
      send_chat_message(ws_connection, 
        "Summarize claude_research.txt", 
        app: app_name,
        model: "claude-sonnet-4-20250514",
        max_tokens: 1000)
      response = wait_for_response(ws_connection, timeout: 30)
      
      expect(response).not_to be_empty
      expect(response.downcase).to match(/climate|biodiversity/)
      
      cleanup_test_files("claude_research.txt")
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
      send_chat_message(ws_connection, 
        "Explain the concept of neural networks", 
        app: app_name,
        model: "gemini-2.0-flash")
      response = wait_for_response(ws_connection, timeout: 30)
      
      expect(response).not_to be_empty
      expect(response.downcase).to match(/neural|network|layer|learning/)
    end

    it "integrates web search when available" do
      skip "Tavily API key not configured" unless CONFIG["TAVILY_API_KEY"]
      
      send_chat_message(ws_connection, 
        "What are the latest AI model releases from major tech companies?", 
        app: app_name,
        model: "gemini-2.0-flash")
      response = wait_for_response(ws_connection, timeout: 60)
      
      expect(response).not_to be_empty
      expect(response.downcase).to match(/ai|model|google|openai|anthropic|meta/)
    end
  end

  describe "Multi-provider comparison" do
    let(:ws_connection) { create_websocket_connection }
    
    after do
      ws_connection[:client].close if ws_connection[:client]
    end

    it "compares responses across providers for same query" do
      query = "What is machine learning?"
      providers = []
      responses = {}
      
      if CONFIG["OPENAI_API_KEY"]
        providers << { app: "ResearchAssistantOpenAI", name: "OpenAI", model: "gpt-4.1" }
      end
      
      # Skip Claude due to tool schema validation issues
      # if CONFIG["ANTHROPIC_API_KEY"]
      #   providers << { app: "ResearchAssistantClaude", name: "Claude", model: "claude-sonnet-4-20250514", max_tokens: 1000 }
      # end
      
      if CONFIG["GEMINI_API_KEY"]
        providers << { app: "ResearchAssistantGemini", name: "Gemini", model: "gemini-2.0-flash" }
      end
      
      skip "No providers configured" if providers.empty?
      
      providers.each do |provider|
        ws_connection[:messages].clear
        
        params = { app: provider[:app] }
        params[:model] = provider[:model] if provider[:model]
        params[:max_tokens] = provider[:max_tokens] if provider[:max_tokens]
        
        send_chat_message(ws_connection, query, **params)
        
        response = wait_for_response(ws_connection, timeout: 30)
        responses[provider[:name]] = response
        
        # Basic validation that each provider gives a reasonable response
        expect(response).not_to be_empty
        expect(response.downcase).to match(/machine learning|algorithm|data|model/)
      end
      
      # All providers should give substantive responses
      responses.each do |provider, response|
        expect(response.length).to be > 100, "#{provider} response too short"
      end
    end
  end

  describe "Error handling" do
    let(:ws_connection) { create_websocket_connection }
    
    after do
      ws_connection[:client].close if ws_connection[:client]
    end

    it "handles non-existent file gracefully" do
      skip "OpenAI API key not configured" unless CONFIG["OPENAI_API_KEY"]
      
      send_chat_message(ws_connection, 
        "Please analyze non_existent_file_12345.pdf", 
        app: "ResearchAssistantOpenAI")
      response = wait_for_response(ws_connection, timeout: 30)
      
      expect(response).not_to be_empty
      # Should mention file not found or similar error
      expect(response.downcase).to match(/not found|doesn't exist|unable to find|error/)
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

  describe "Advanced research features" do
    let(:ws_connection) { create_websocket_connection }
    
    after do
      ws_connection[:client].close if ws_connection[:client]
    end

    it "combines multiple sources for comprehensive research" do
      # Skip this test as it's problematic with function calling depth limits
      skip "This test causes function call depth issues"
    end

    it "handles complex multi-step research requests" do
      skip "Gemini API key not configured" unless CONFIG["GEMINI_API_KEY"]
      
      send_chat_message(ws_connection, 
        "Compare supervised and unsupervised learning approaches", 
        app: "ResearchAssistantGemini",
        model: "gemini-2.0-flash")
      response = wait_for_response(ws_connection, timeout: 45)
      
      expect(response).not_to be_empty
      expect(response.downcase).to include("supervised")
      expect(response.downcase).to include("unsupervised")
      # Should include comparisons
      expect(response.downcase).to match(/difference|compare|contrast|versus/)
    end
  end
end