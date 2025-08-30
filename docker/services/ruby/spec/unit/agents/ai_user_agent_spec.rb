# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monadic/agents/ai_user_agent'

RSpec.describe AIUserAgent do
  # Test class that includes AIUserAgent module
  class TestAIUserAgent
    include AIUserAgent
  end
  
  let(:agent) { TestAIUserAgent.new }
  let(:session) do
    {
      messages: [
        { "role" => "user", "text" => "Hello", "type" => "text" },
        { "role" => "assistant", "text" => "Hi there! How can I help you?", "type" => "text" },
        { "role" => "user", "text" => "What's the weather?", "type" => "text" }
      ]
    }
  end
  
  before do
    # Set up necessary constants and globals
    stub_const('MonadicApp::AI_USER_INITIAL_PROMPT', 'You are simulating a user in a conversation.')
    stub_const('CONFIG', {
      "OPENAI_API_KEY" => "test-key",
      "ANTHROPIC_API_KEY" => "test-key",
      "OPENAI_DEFAULT_MODEL" => "gpt-4",
      "ANTHROPIC_DEFAULT_MODEL" => "claude-3"
    })
    
    # Mock APPS global
    @mock_app = double('app')
    allow(@mock_app).to receive(:settings).and_return({
      "group" => "OpenAI",
      "display_name" => "Chat"
    })
    allow(@mock_app).to receive(:send_query).and_return("This is a simulated user response.")
    
    stub_const('APPS', {
      "ChatOpenAI" => @mock_app
    })
  end
  
  describe '#process_ai_user' do
    context 'with valid parameters' do
      let(:params) do
        {
          "ai_user_provider" => "openai",
          "monadic" => false
        }
      end
      
      it 'generates a user response successfully' do
        result = agent.process_ai_user(session, params)
        
        expect(result["type"]).to eq("ai_user")
        expect(result["content"]).to eq("This is a simulated user response.")
        expect(result["finished"]).to be true
      end
      
      it 'uses default provider when not specified' do
        params_without_provider = params.dup
        params_without_provider.delete("ai_user_provider")
        
        result = agent.process_ai_user(session, params_without_provider)
        
        expect(result["type"]).to eq("ai_user")
      end
      
      it 'limits conversation history to last 5 messages' do
        # Add more messages to session
        10.times do |i|
          session[:messages] << { "role" => "user", "text" => "Message #{i}", "type" => "text" }
        end
        
        # Spy on format_conversation to check message count
        allow(agent).to receive(:format_conversation).and_call_original
        
        agent.process_ai_user(session, params)
        
        # Should only process last 5 non-system messages
        expect(agent).to have_received(:format_conversation) do |messages, _|
          expect(messages.length).to be <= 5
        end
      end
      
      it 'filters out system messages' do
        session[:messages] << { "role" => "system", "text" => "System prompt", "type" => "text" }
        
        allow(agent).to receive(:format_conversation).and_call_original
        
        agent.process_ai_user(session, params)
        
        expect(agent).to have_received(:format_conversation) do |messages, _|
          expect(messages.none? { |m| m["role"] == "system" }).to be true
        end
      end
    end
    
    context 'with different providers' do
      it 'handles anthropic provider correctly' do
        params = { "ai_user_provider" => "anthropic", "monadic" => false }
        
        # Mock anthropic app
        anthropic_app = double('anthropic_app')
        allow(anthropic_app).to receive(:settings).and_return({
          "group" => "Anthropic",
          "display_name" => "Chat"
        })
        allow(anthropic_app).to receive(:send_query).and_return("Anthropic response")
        
        stub_const('APPS', {
          "ChatClaude" => anthropic_app
        })
        
        result = agent.process_ai_user(session, params)
        
        expect(result["type"]).to eq("ai_user")
        expect(result["content"]).to eq("Anthropic response")
      end
      
      it 'handles perplexity provider with special formatting' do
        params = { "ai_user_provider" => "perplexity", "monadic" => false }
        
        # Mock perplexity app
        perplexity_app = double('perplexity_app')
        allow(perplexity_app).to receive(:settings).and_return({
          "group" => "Perplexity",
          "display_name" => "Chat"
        })
        allow(perplexity_app).to receive(:send_query).and_return("Perplexity response")
        
        stub_const('APPS', {
          "ChatPerplexity" => perplexity_app
        })
        stub_const('CONFIG', CONFIG.merge("PERPLEXITY_API_KEY" => "test-key"))
        
        result = agent.process_ai_user(session, params)
        
        expect(result["type"]).to eq("ai_user")
      end
    end
    
    context 'with monadic mode' do
      let(:params) do
        {
          "ai_user_provider" => "openai",
          "monadic" => true
        }
      end
      
      let(:monadic_message) do
        {
          "role" => "assistant",
          "text" => '{"message": "This is from monadic mode", "context": "some data"}',
          "type" => "text"
        }
      end
      
      it 'extracts message from JSON in monadic mode' do
        session[:messages] << monadic_message
        
        allow(agent).to receive(:format_conversation).and_call_original
        
        agent.process_ai_user(session, params)
        
        expect(agent).to have_received(:format_conversation) do |messages, monadic|
          expect(monadic).to be true
        end
      end
    end
    
    context 'with errors' do
      it 'returns error when no compatible app found' do
        stub_const('APPS', {})
        
        params = { "ai_user_provider" => "openai", "monadic" => false }
        result = agent.process_ai_user(session, params)
        
        expect(result["type"]).to eq("error")
        expect(result["content"]).to include("No compatible chat app found")
      end
      
      it 'returns error when API key is missing' do
        stub_const('CONFIG', {})
        
        params = { "ai_user_provider" => "openai", "monadic" => false }
        result = agent.process_ai_user(session, params)
        
        expect(result["type"]).to eq("error")
        expect(result["content"]).to include("No compatible chat app found")
      end
      
      it 'handles API errors gracefully' do
        allow(@mock_app).to receive(:send_query).and_return("ERROR: API rate limit exceeded")
        
        params = { "ai_user_provider" => "openai", "monadic" => false }
        result = agent.process_ai_user(session, params)
        
        expect(result["type"]).to eq("error")
        expect(result["content"]).to include("ERROR: API rate limit exceeded")
      end
      
      it 'handles exceptions gracefully' do
        allow(@mock_app).to receive(:send_query).and_raise(StandardError.new("Network error"))
        
        params = { "ai_user_provider" => "openai", "monadic" => false }
        result = agent.process_ai_user(session, params)
        
        expect(result["type"]).to eq("error")
        expect(result["content"]).to include("AI User error")
        expect(result["content"]).to include("Network error")
      end
      
      it 'handles empty response' do
        allow(@mock_app).to receive(:send_query).and_return("")
        
        params = { "ai_user_provider" => "openai", "monadic" => false }
        result = agent.process_ai_user(session, params)
        
        expect(result["type"]).to eq("error")
        expect(result["content"]).to include("Failed to generate AI User response")
      end
    end
  end
  
  describe '#format_conversation' do
    let(:messages) do
      [
        { "role" => "user", "text" => "Hello" },
        { "role" => "assistant", "text" => "Hi there!" }
      ]
    end
    
    it 'formats messages as conversation text' do
      result = agent.send(:format_conversation, messages, false)
      
      expect(result).to include("User: Hello")
      expect(result).to include("Assistant: Hi there!")
    end
    
    it 'handles monadic mode JSON extraction' do
      monadic_messages = [
        { "role" => "user", "text" => '{"message": "Hello from user"}' },
        { "role" => "assistant", "text" => '{"response": "Hi from assistant"}' }
      ]
      
      result = agent.send(:format_conversation, monadic_messages, true)
      
      expect(result).to include("User: Hello from user")
      expect(result).to include("Assistant: Hi from assistant")
    end
    
    it 'handles invalid JSON in monadic mode' do
      messages_with_invalid = [
        { "role" => "user", "text" => "Not JSON at all" }
      ]
      
      result = agent.send(:format_conversation, messages_with_invalid, true)
      
      expect(result).to include("User: Not JSON at all")
    end
  end
  
  describe '#extract_content' do
    it 'returns text as-is when not in monadic mode' do
      text = "Regular text message"
      result = agent.send(:extract_content, text, false)
      
      expect(result).to eq(text)
    end
    
    it 'extracts message field from JSON in monadic mode' do
      json_text = '{"message": "Hello", "other": "data"}'
      result = agent.send(:extract_content, json_text, true)
      
      expect(result).to eq("Hello")
    end
    
    it 'extracts response field if message not present' do
      json_text = '{"response": "Hi there", "other": "data"}'
      result = agent.send(:extract_content, json_text, true)
      
      expect(result).to eq("Hi there")
    end
    
    it 'returns original text on JSON parse error' do
      invalid_json = '{"broken": json}'
      result = agent.send(:extract_content, invalid_json, true)
      
      expect(result).to eq(invalid_json)
    end
  end
  
  describe '#find_chat_app_for_provider' do
    it 'finds OpenAI app' do
      result = agent.send(:find_chat_app_for_provider, "openai")
      
      expect(result).not_to be_nil
      expect(result[0]).to eq("ChatOpenAI")
    end
    
    it 'handles provider name variations' do
      # Add Claude app
      claude_app = double('claude_app')
      allow(claude_app).to receive(:settings).and_return({
        "group" => "Anthropic Claude",
        "display_name" => "Chat"
      })
      
      stub_const('APPS', APPS.merge("ChatClaude" => claude_app))
      
      result = agent.send(:find_chat_app_for_provider, "anthropic")
      
      expect(result).not_to be_nil
    end
    
    it 'returns nil when API key is missing' do
      stub_const('CONFIG', {})
      
      result = agent.send(:find_chat_app_for_provider, "openai")
      
      expect(result).to be_nil
    end
    
    it 'returns nil for unknown provider' do
      result = agent.send(:find_chat_app_for_provider, "unknown_provider")
      
      expect(result).to be_nil
    end
  end
  
  describe '#default_model_for_provider' do
    it 'returns configured model for provider' do
      model = agent.send(:default_model_for_provider, "openai")
      expect(model).to eq("gpt-4")
      
      model = agent.send(:default_model_for_provider, "anthropic")
      expect(model).to eq("claude-3")
    end
    
    it 'returns default fallback when config not available' do
      stub_const('CONFIG', {})
      
      model = agent.send(:default_model_for_provider, "openai")
      expect(model).to eq("gpt-5")
      
      model = agent.send(:default_model_for_provider, "anthropic")
      expect(model).to eq("claude-sonnet-4-20250514")
    end
    
    it 'handles various provider names' do
      providers_and_defaults = {
        "gemini" => "gemini-2.5-flash",
        "mistral" => "mistral-large-latest",
        "grok" => "grok-4-0709",
        "perplexity" => "sonar",
        "deepseek" => "deepseek-chat",
        "cohere" => "command-a-03-2025"
      }
      
      stub_const('CONFIG', {})
      
      providers_and_defaults.each do |provider, expected_model|
        model = agent.send(:default_model_for_provider, provider)
        expect(model).to eq(expected_model)
      end
    end
  end
end