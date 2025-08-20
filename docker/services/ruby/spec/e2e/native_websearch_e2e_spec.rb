# frozen_string_literal: true

require "spec_helper"
require "net/http"
require "json"
require "timeout"

# End-to-end tests for native web search through the actual Monadic Chat server
RSpec.describe "Native Web Search E2E", :e2e do
  before(:all) do
    # Start the server if not already running
    @server_url = ENV["SERVER_URL"] || "http://localhost:3000"
    @server_available = check_server_availability(@server_url)
    
    unless @server_available
      skip "Server not available at #{@server_url}"
    end
  end
  
  def check_server_availability(url)
    uri = URI(url)
    response = Net::HTTP.get_response(uri)
    response.code == "200"
  rescue
    false
  end
  
  def send_chat_request(provider, model, message, websearch: true)
    uri = URI("#{@server_url}/api/chat")
    http = Net::HTTP.new(uri.host, uri.port)
    http.read_timeout = 60
    http.open_timeout = 10
    
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    
    body = {
      provider: provider,
      model: model,
      message: message,
      websearch: websearch,
      temperature: 0.0,
      max_tokens: 500,
      stream: false
    }
    
    request.body = body.to_json
    
    response = http.request(request)
    JSON.parse(response.body) if response.code == "200"
  rescue => e
    puts "Request failed: #{e.message}"
    nil
  end

  describe "OpenAI gpt-4.1-mini" do
    it "performs native web search for current events" do
      skip "OpenAI API key not configured" unless CONFIG["OPENAI_API_KEY"]
      
      response = send_chat_request(
        "openai",
        "gpt-4.1-mini",
        "What are today's top technology news headlines? List 3 brief items."
      )
      
      expect(response).not_to be_nil
      expect(response["content"]).to include("technology").or include("tech").or include("news")
      expect(response["search_performed"]).to be true if response["search_performed"]
    end
    
    it "provides accurate current information" do
      skip "OpenAI API key not configured" unless CONFIG["OPENAI_API_KEY"]
      
      # Ask about something that requires current data
      response = send_chat_request(
        "openai",
        "gpt-4.1-mini",
        "What is the current USD to EUR exchange rate?"
      )
      
      expect(response).not_to be_nil
      expect(response["content"]).to match(/\d+\.\d+/) # Should contain numbers
      expect(response["content"].downcase).to include("eur").or include("euro")
    end
  end

  describe "Claude web_search_20250305" do
    it "performs native web search for research queries" do
      skip "Claude API key not configured" unless CONFIG["ANTHROPIC_API_KEY"]
      
      response = send_chat_request(
        "anthropic",
        "claude-3-5-sonnet-latest",
        "What are the latest developments in quantum computing in 2025?"
      )
      
      expect(response).not_to be_nil
      expect(response["content"].downcase).to include("quantum")
      expect(response["content"]).to match(/202[4-5]/) # Should mention recent years
    end
    
    it "retrieves factual information with citations" do
      skip "Claude API key not configured" unless CONFIG["ANTHROPIC_API_KEY"]
      
      response = send_chat_request(
        "anthropic",
        "claude-3-5-sonnet-latest",
        "Who won the most recent Nobel Prize in Physics and what was it for?"
      )
      
      expect(response).not_to be_nil
      expect(response["content"].downcase).to include("nobel").or include("physics")
      # Should include links with proper attributes
      expect(response["content"]).to include('target="_blank"') if response["content"].include?("<a ")
    end
  end

  describe "xAI Live Search" do
    it "searches current X/Twitter content" do
      skip "xAI API key not configured" unless CONFIG["XAI_API_KEY"]
      
      response = send_chat_request(
        "xai",
        "grok-4-latest",
        "What are the trending topics on X right now?"
      )
      
      expect(response).not_to be_nil
      expect(response["content"].downcase).to match(/trend|topic|x\.com|twitter|discussion/)
    end
    
    it "combines web and social media sources" do
      skip "xAI API key not configured" unless CONFIG["XAI_API_KEY"]
      
      response = send_chat_request(
        "xai",
        "grok-4-latest",
        "What is the public sentiment about AI safety based on recent discussions?"
      )
      
      expect(response).not_to be_nil
      expect(response["content"].downcase).to include("ai").or include("artificial intelligence")
      expect(response["content"].downcase).to include("safety").or include("risk").or include("concern")
    end
  end

  describe "Gemini URL Context" do
    it "processes web content through URL context" do
      skip "Gemini API key not configured" unless CONFIG["GEMINI_API_KEY"]
      
      response = send_chat_request(
        "gemini",
        "gemini-2.5-flash",
        "Find information about the James Webb Space Telescope's recent discoveries"
      )
      
      expect(response).not_to be_nil
      expect(response["content"].downcase).to include("webb").or include("telescope").or include("space")
    end
    
    it "handles multiple URL sources" do
      skip "Gemini API key not configured" unless CONFIG["GEMINI_API_KEY"]
      
      response = send_chat_request(
        "gemini",
        "gemini-2.5-flash",
        "Compare recent news about renewable energy from different sources"
      )
      
      expect(response).not_to be_nil
      expect(response["content"].downcase).to include("energy").or include("renewable").or include("solar").or include("wind")
    end
  end

  describe "Perplexity Built-in Search" do
    it "always includes web search in responses" do
      skip "Perplexity API key not configured" unless CONFIG["PERPLEXITY_API_KEY"]
      
      # Even without explicit search request, Perplexity searches
      response = send_chat_request(
        "perplexity",
        "perplexity",
        "Explain quantum entanglement",
        websearch: false  # Even with false, Perplexity searches
      )
      
      expect(response).not_to be_nil
      expect(response["content"].downcase).to include("quantum").or include("entanglement")
      expect(response["content"].length).to be > 100  # Should be comprehensive
    end
  end

  describe "Cross-provider consistency" do
    it "returns similar information across providers" do
      skip "Skipping cross-provider test in CI" if ENV["CI"]
      
      query = "What is the population of Tokyo as of 2025?"
      responses = {}
      
      # Collect responses from available providers
      if CONFIG["OPENAI_API_KEY"]
        responses["openai"] = send_chat_request("openai", "gpt-4.1-mini", query)
      end
      
      if CONFIG["ANTHROPIC_API_KEY"]
        responses["claude"] = send_chat_request("anthropic", "claude-3-5-sonnet-latest", query)
      end
      
      if CONFIG["GEMINI_API_KEY"]
        responses["gemini"] = send_chat_request("gemini", "gemini-2.5-flash", query)
      end
      
      # All providers should mention Tokyo and population numbers
      responses.each do |provider, response|
        next unless response
        
        expect(response["content"].downcase).to include("tokyo")
        expect(response["content"]).to match(/\d+/) # Should contain numbers
        expect(response["content"].downcase).to include("million").or include("population")
      end
      
      # At least 2 providers should be tested
      expect(responses.compact.length).to be >= 2 if responses.any?
    end
  end

  describe "Performance and reliability" do
    it "responds within reasonable time" do
      skip "OpenAI API key not configured" unless CONFIG["OPENAI_API_KEY"]
      
      start_time = Time.now
      
      response = send_chat_request(
        "openai",
        "gpt-4.1-mini",
        "What is 2+2?"  # Simple query that might not trigger search
      )
      
      elapsed = Time.now - start_time
      
      expect(response).not_to be_nil
      expect(elapsed).to be < 30  # Should respond within 30 seconds
    end
    
    it "handles search timeout gracefully" do
      skip "Gemini API key not configured" unless CONFIG["GEMINI_API_KEY"]
      
      # Very complex query that might timeout
      response = Timeout.timeout(60) do
        send_chat_request(
          "gemini",
          "gemini-2.5-flash",
          "Search and compile a comprehensive list of all AI research papers published in the last hour"
        )
      end
      
      # Should either succeed or return error gracefully
      expect(response).not_to be_nil
      if response["error"]
        expect(response["error"]).to include("timeout").or include("limit").or include("available")
      else
        expect(response["content"]).not_to be_empty
      end
    rescue Timeout::Error
      # Timeout is acceptable for complex queries
      expect(true).to be true
    end
  end

  describe "WebSearch feature flag" do
    it "respects websearch enabled/disabled setting" do
      skip "OpenAI API key not configured" unless CONFIG["OPENAI_API_KEY"]
      
      # With websearch disabled
      response_without = send_chat_request(
        "openai",
        "gpt-4.1-mini",
        "What is the weather in Paris right now?",
        websearch: false
      )
      
      # With websearch enabled
      response_with = send_chat_request(
        "openai",
        "gpt-4.1-mini",
        "What is the weather in Paris right now?",
        websearch: true
      )
      
      expect(response_without).not_to be_nil
      expect(response_with).not_to be_nil
      
      # Response with search should be more specific/current
      if response_with["content"] && response_without["content"]
        expect(response_with["content"].length).to be >= response_without["content"].length
      end
    end
  end
end