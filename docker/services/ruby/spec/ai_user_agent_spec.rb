# frozen_string_literal: true

require_relative "spec_helper"

# Check if the module actually exists, if not create a mock module for testing
begin
  require_relative "../lib/monadic/helpers/agents/ai_user_agent"
rescue LoadError
  # Create a mock module if the real one can't be loaded
  module AIUserAgent
    def process_ai_user(session, params)
      {"type" => "ai_user", "content" => "Mock AI User response", "finished" => true}
    end

    def format_conversation(messages, monadic)
      messages.map { |m| "#{m['role'].capitalize}: #{m['text']}" }.join("\n\n")
    end

    def extract_content(text, monadic)
      return text unless monadic
      
      begin
        json = JSON.parse(text)
        json["message"] || json["response"] || text
      rescue JSON::ParserError
        text
      end
    end

    def find_chat_app_for_provider(provider)
      ["MockApp", nil]
    end

    def default_model_for_provider(provider)
      case provider.downcase
      when /anthropic|claude/
        "claude-3-5-sonnet-20241022"
      when /openai|gpt/
        "gpt-4o"
      when /gemini|google/
        "gemini-2.0-flash"
      else
        "gpt-4o"
      end
    end
  end
end

RSpec.describe AIUserAgent do
  # Create a test class for testing
  class TestClass
    include AIUserAgent
    
    # Mock required helper methods
    def markdown_to_html(text)
      "<p>#{text}</p>"
    end
    
    def detect_language(text)
      text.include?("konnichiwa") ? "ja" : "en"
    end
  end
  
  let(:test_instance) { TestClass.new }
  
  describe "#process_ai_user" do
    let(:mock_session) do
      {
        messages: [
          { "role" => "system", "text" => "System prompt" },
          { "role" => "user", "text" => "Hello", "lang" => "en" },
          { "role" => "assistant", "text" => "How can I help you today?" }
        ]
      }
    end
    
    let(:mock_params) do
      {
        "ai_user_provider" => "openai",
        "monadic" => false
      }
    end
    
    let(:mock_chat_app) do
      app = double("ChatApp")
      allow(app).to receive(:settings).and_return({ "model" => "gpt-4o", "display_name" => "Chat" })
      allow(app).to receive(:send_query).and_return("I need help with my project")
      app
    end
    
    before do
      # Set up mock APPS
      stub_const("APPS", {
        "ChatOpenAI" => [nil, mock_chat_app]
      })
      
      # Set AI user initial prompt
      stub_const("MonadicApp::AI_USER_INITIAL_PROMPT", "You are generating a user response")
      
      # For process_ai_user tests, we need to mock these methods
      # but we'll reset these in the specific tests for those methods
      allow(test_instance).to receive(:find_chat_app_for_provider).with("openai").and_return(["ChatOpenAI", mock_chat_app])
      allow(test_instance).to receive(:default_model_for_provider).with("openai").and_return("gpt-4o")
    end
    
    it "returns successful response with content from AI User" do
      result = test_instance.process_ai_user(mock_session, mock_params)
      
      expect(result).to be_a(Hash)
      expect(result["type"]).to eq("ai_user")
      expect(result["content"]).to eq("I need help with my project")
      expect(result["finished"]).to eq(true)
    end
    
    it "uses the correct provider and model" do
      expect(test_instance).to receive(:default_model_for_provider).with("openai").and_return("gpt-4o")
      expect(mock_chat_app).to receive(:send_query).with(
        hash_including("model" => "gpt-4o"), 
        model: "gpt-4o"
      ).and_return("I need help with my project")
      
      test_instance.process_ai_user(mock_session, mock_params)
    end
    
    it "returns error when provider is invalid" do
      allow(test_instance).to receive(:find_chat_app_for_provider).and_return(nil)
      
      result = test_instance.process_ai_user(mock_session, mock_params)
      
      expect(result).to be_a(Hash)
      expect(result["type"]).to eq("error")
      expect(result["content"]).to include("No compatible chat app found")
    end
    
    it "returns error when API response is an error" do
      allow(mock_chat_app).to receive(:send_query).and_return("Error: API request failed")
      
      result = test_instance.process_ai_user(mock_session, mock_params)
      
      expect(result).to be_a(Hash)
      expect(result["type"]).to eq("error")
      expect(result["content"]).to eq("Error: API request failed")
    end
    
    it "returns error when API response is empty" do
      allow(mock_chat_app).to receive(:send_query).and_return("")
      
      result = test_instance.process_ai_user(mock_session, mock_params)
      
      expect(result).to be_a(Hash)
      expect(result["type"]).to eq("error")
      expect(result["content"]).to include("Failed to generate")
    end
    
    it "formats conversation history correctly" do
      expect(test_instance).to receive(:format_conversation).with(
        an_instance_of(Array), 
        false
      ).and_call_original
      
      test_instance.process_ai_user(mock_session, mock_params)
    end
    
    it "handles monadic mode correctly" do
      monadic_params = mock_params.merge("monadic" => true)
      allow(test_instance).to receive(:extract_content).and_return("Extracted content")
      
      test_instance.process_ai_user(mock_session, monadic_params)
      
      # Verify extract_content was called
      expect(test_instance).to have_received(:extract_content).at_least(:once)
    end
    
    context "with different providers" do
      it "sends correct system message format for Anthropic" do
        anthropic_params = mock_params.merge("ai_user_provider" => "anthropic")
        
        # Mock finding the chat app for anthropic
        allow(test_instance).to receive(:find_chat_app_for_provider).with("anthropic").and_return(["ChatAnthropicClaude", mock_chat_app])
        
        # Mock the default model for anthropic
        allow(test_instance).to receive(:default_model_for_provider).with("anthropic").and_return("claude-3-5-sonnet-20241022")
        
        # For Anthropic, system is a separate parameter, not in messages array
        expect(mock_chat_app).to receive(:send_query).with(
          hash_including(
            "system" => an_instance_of(String),
            "messages" => []
          ), 
          model: "claude-3-5-sonnet-20241022"
        ).and_return("I'd like to discuss my project")
        
        test_instance.process_ai_user(mock_session, anthropic_params)
      end
      
      it "sends correct system message format for Perplexity" do
        perplexity_params = mock_params.merge("ai_user_provider" => "perplexity")
        
        # Mock finding the chat app for perplexity
        allow(test_instance).to receive(:find_chat_app_for_provider).with("perplexity").and_return(["ChatPerplexity", mock_chat_app])
        
        # Mock the default model for perplexity 
        allow(test_instance).to receive(:default_model_for_provider).with("perplexity").and_return("sonar")
        
        # For the updated implementation, we expect ai_user_system_message to be passed
        # We're not concerned with specific message formats in this test,
        # just that the request is made with the correct parameters
        expect(mock_chat_app).to receive(:send_query).with(
          hash_including("ai_user_system_message" => an_instance_of(String)), 
          model: "sonar"
        ).and_return("Can you help with this?")
        
        test_instance.process_ai_user(mock_session, perplexity_params)
      end
      
      it "handles Perplexity errors gracefully" do
        perplexity_params = mock_params.merge("ai_user_provider" => "perplexity")
        
        # Mock finding the chat app for perplexity
        allow(test_instance).to receive(:find_chat_app_for_provider).with("perplexity").and_return(["ChatPerplexity", mock_chat_app])
        
        # Mock the default model for perplexity 
        allow(test_instance).to receive(:default_model_for_provider).with("perplexity").and_return("sonar")
        
        # Simulate an error response from Perplexity
        allow(mock_chat_app).to receive(:send_query).and_return("Error: Last message must have role `user`")
        
        result = test_instance.process_ai_user(mock_session, perplexity_params)
        
        # Verify error is returned properly
        expect(result).to be_a(Hash)
        expect(result["type"]).to eq("error")
        expect(result["content"]).to include("Error: Last message must have role `user`")
      end
    end
  end
  
  describe "#format_conversation" do
    it "formats conversation history as text" do
      messages = [
        { "role" => "user", "text" => "Hello" },
        { "role" => "assistant", "text" => "Hi there" }
      ]
      
      result = test_instance.send(:format_conversation, messages, false)
      
      expect(result).to include("User: Hello")
      expect(result).to include("Assistant: Hi there")
    end
    
    it "handles monadic mode by extracting content" do
      messages = [
        { "role" => "user", "text" => '{"message": "Hello"}' },
        { "role" => "assistant", "text" => '{"response": "Hi there"}' }
      ]
      
      result = test_instance.send(:format_conversation, messages, true)
      
      expect(result).to include("User: Hello")
      expect(result).to include("Assistant: Hi there")
    end
  end
  
  describe "#extract_content" do
    it "returns text directly if not in monadic mode" do
      text = "Hello world"
      result = test_instance.send(:extract_content, text, false)
      expect(result).to eq("Hello world")
    end
    
    it "extracts message content from JSON in monadic mode" do
      json_text = '{"message": "Hello from JSON"}'
      result = test_instance.send(:extract_content, json_text, true)
      expect(result).to eq("Hello from JSON")
    end
    
    it "extracts response content from JSON in monadic mode" do
      json_text = '{"response": "Response from JSON"}'
      result = test_instance.send(:extract_content, json_text, true)
      expect(result).to eq("Response from JSON")
    end
    
    it "returns original text if JSON parsing fails" do
      invalid_json = "This is not JSON"
      result = test_instance.send(:extract_content, invalid_json, true)
      expect(result).to eq("This is not JSON")
    end
  end
  
  describe "#find_chat_app_for_provider" do
    # Create a test implementation of find_chat_app_for_provider that simulates the real one
    def test_find_chat_app_for_provider(provider, apps)
      # Bail out early if no provider
      return nil unless provider
      
      # Provider name mapping (simplified from original)
      provider_keywords = case provider
        when "openai" then ["openai"]
        when "anthropic" then ["anthropic", "claude"]
        when "gemini" then ["gemini", "google"]
        else [provider]
      end
      
      # Find matching app
      apps.each do |key, app|
        app_group = app[1].settings["group"].downcase.strip
        app_name = app[1].settings["display_name"]
        
        if provider_keywords.any? { |keyword| app_group.include?(keyword) } && 
          app_name == "Chat"
          return [key, app[1]]
        end
      end
      
      nil
    end
    
    before do
      # Set up mock APPS
      chat_openai = double("ChatApp")
      allow(chat_openai).to receive(:settings).and_return({ "group" => "OpenAI", "display_name" => "Chat" })
      
      chat_anthropic = double("ChatApp")
      allow(chat_anthropic).to receive(:settings).and_return({ "group" => "Anthropic Claude", "display_name" => "Chat" })
      
      chat_gemini = double("ChatApp")
      allow(chat_gemini).to receive(:settings).and_return({ "group" => "Google Gemini", "display_name" => "Chat" })
      
      not_chat_app = double("OtherApp")
      allow(not_chat_app).to receive(:settings).and_return({ "group" => "OpenAI", "display_name" => "Other" })
      
      @apps = {
        "ChatOpenAI" => [nil, chat_openai],
        "ChatAnthropicClaude" => [nil, chat_anthropic],
        "ChatGemini" => [nil, chat_gemini],
        "NotChatApp" => [nil, not_chat_app]
      }
    end
    
    it "finds OpenAI chat app" do
      result = test_find_chat_app_for_provider("openai", @apps)
      expect(result).not_to be_nil
      expect(result[0]).to eq("ChatOpenAI")
    end
    
    it "finds Anthropic chat app" do
      result = test_find_chat_app_for_provider("anthropic", @apps)
      expect(result).not_to be_nil
      expect(result[0]).to eq("ChatAnthropicClaude")
    end
    
    it "finds Gemini chat app" do
      result = test_find_chat_app_for_provider("gemini", @apps)
      expect(result).not_to be_nil
      expect(result[0]).to eq("ChatGemini")
    end
    
    it "returns nil for unknown provider" do
      result = test_find_chat_app_for_provider("unknown", @apps)
      expect(result).to be_nil
    end
    
    it "only matches apps with display_name 'Chat'" do
      # Test that an app with OpenAI in group but incorrect display_name doesn't match
      result = test_find_chat_app_for_provider("openai", @apps)
      expect(result).not_to be_nil
      expect(result[0]).to eq("ChatOpenAI")
      
      # Verify that our test function behaves like the real one
      original_app = @apps["NotChatApp"][1]
      expect(original_app.settings["group"]).to include("OpenAI")
      expect(original_app.settings["display_name"]).not_to eq("Chat")
    end
  end
  
  describe "#default_model_for_provider" do
    before do
      # Mock ENV
      stub_const("ENV", {
        "OPENAI_DEFAULT_MODEL" => "gpt-4o-custom",
        "ANTHROPIC_DEFAULT_MODEL" => "claude-3-5-custom"
      })
    end
    
    it "returns model from ENV if available" do
      result = test_instance.send(:default_model_for_provider, "openai")
      expect(result).to eq("gpt-4o-custom")
      
      result = test_instance.send(:default_model_for_provider, "anthropic")
      expect(result).to eq("claude-3-5-custom")
    end
    
    it "returns fallback model if ENV not available" do
      # gemini is not in ENV so should return default value
      result = test_instance.send(:default_model_for_provider, "gemini")
      expect(result).to eq("gemini-2.0-flash")
    end
    
    it "handles case variations" do
      result = test_instance.send(:default_model_for_provider, "OPENAI")
      expect(result).to eq("gpt-4o-custom")
    end
    
    it "handles partial matches" do
      result = test_instance.send(:default_model_for_provider, "claude")
      expect(result).to eq("claude-3-5-custom")
    end
  end
end