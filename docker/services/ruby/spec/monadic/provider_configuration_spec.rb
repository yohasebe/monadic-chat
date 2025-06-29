# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/monadic/monadic_provider_interface'

RSpec.describe 'Provider Configuration' do
  let(:provider_class) do
    Class.new do
      include MonadicProviderInterface
      attr_accessor :obj
      
      def initialize(monadic = true)
        @obj = { "monadic" => monadic.to_s }
      end
    end
  end
  
  let(:provider) { provider_class.new }

  describe 'OpenAI/DeepSeek/Grok configuration' do
    [:openai, :deepseek, :grok].each do |provider_type|
      context "for #{provider_type}" do
        it 'sets response_format to json_object' do
          body = {}
          result = provider.configure_monadic_response(body, provider_type)
          
          expect(result["response_format"]).to eq({ "type" => "json_object" })
        end
        
        it 'does not modify body when not in monadic mode' do
          provider.obj["monadic"] = "false"
          body = {}
          result = provider.configure_monadic_response(body, provider_type)
          
          expect(result).to eq({})
        end
      end
    end
  end

  describe 'Perplexity configuration' do
    it 'uses json_schema format for basic apps' do
      body = {}
      result = provider.configure_monadic_response(body, :perplexity, 'basic_app')
      
      expect(result["response_format"]["type"]).to eq("json_schema")
      expect(result["response_format"]["json_schema"]["schema"]).to be_a(Hash)
      expect(result["response_format"]["json_schema"]["schema"]["properties"]).to have_key("message")
      expect(result["response_format"]["json_schema"]["schema"]["properties"]).to have_key("context")
    end
    
    it 'uses Chat Plus schema for chat_plus apps' do
      body = {}
      result = provider.configure_monadic_response(body, :perplexity, 'chat_plus_perplexity')
      
      schema = result["response_format"]["json_schema"]["schema"]
      context_props = schema["properties"]["context"]["properties"]
      
      expect(context_props).to have_key("reasoning")
      expect(context_props).to have_key("topics")
      expect(context_props).to have_key("people")
      expect(context_props).to have_key("notes")
    end
  end

  describe 'Claude configuration' do
    it 'does not modify body' do
      body = { "messages" => [{ "role" => "user", "content" => "test" }] }
      original = body.dup
      result = provider.configure_monadic_response(body, :claude)
      
      expect(result).to eq(original)
    end
  end

  describe 'Gemini configuration' do
    it 'sets responseMimeType and responseSchema' do
      body = {}
      result = provider.configure_monadic_response(body, :gemini)
      
      expect(result["generationConfig"]["responseMimeType"]).to eq("application/json")
      expect(result["generationConfig"]["responseSchema"]).to be_a(Hash)
      expect(result["generationConfig"]["responseSchema"]["type"]).to eq("object")
    end
    
    it 'preserves existing generationConfig' do
      body = { "generationConfig" => { "temperature" => 0.7 } }
      result = provider.configure_monadic_response(body, :gemini)
      
      expect(result["generationConfig"]["temperature"]).to eq(0.7)
      expect(result["generationConfig"]["responseMimeType"]).to eq("application/json")
    end
  end

  describe 'Mistral/Cohere configuration' do
    [:mistral, :cohere].each do |provider_type|
      context "for #{provider_type}" do
        it 'uses json_schema format with name' do
          body = {}
          result = provider.configure_monadic_response(body, provider_type)
          
          expect(result["response_format"]["type"]).to eq("json_schema")
          expect(result["response_format"]["json_schema"]["name"]).to eq("monadic_response")
          expect(result["response_format"]["json_schema"]["schema"]).to be_a(Hash)
        end
      end
    end
  end

  describe 'Ollama configuration' do
    it 'sets format to json and adds system instruction' do
      body = { "messages" => [{ "role" => "user", "content" => "Hello" }] }
      result = provider.configure_monadic_response(body, :ollama)
      
      expect(result["format"]).to eq("json")
      expect(result["messages"].first["role"]).to eq("system")
      expect(result["messages"].first["content"]).to include("JSON object")
    end
    
    it 'appends to existing system message' do
      body = { 
        "messages" => [
          { "role" => "system", "content" => "You are helpful" },
          { "role" => "user", "content" => "Hello" }
        ]
      }
      result = provider.configure_monadic_response(body, :ollama)
      
      expect(result["format"]).to eq("json")
      expect(result["messages"].first["content"]).to include("You are helpful")
      expect(result["messages"].first["content"]).to include("JSON object")
    end
    
    it 'includes Chat Plus structure for chat_plus apps' do
      body = { "messages" => [] }
      result = provider.configure_monadic_response(body, :ollama, 'chat_plus_ollama')
      
      system_content = result["messages"].first["content"]
      expect(system_content).to include("reasoning")
      expect(system_content).to include("topics")
      expect(system_content).to include("people")
      expect(system_content).to include("notes")
    end
  end

  describe 'Unknown provider handling' do
    it 'returns body unchanged for unknown providers' do
      body = { "test" => "data" }
      result = provider.configure_monadic_response(body, :unknown_provider)
      
      expect(result).to eq(body)
    end
  end
end