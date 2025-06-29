# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/monadic/monadic_provider_interface'
require_relative '../../lib/monadic/monadic_schema_validator'

RSpec.describe MonadicProviderInterface do
  let(:dummy_class) do
    Class.new do
      include MonadicProviderInterface
      attr_accessor :obj

      def initialize(obj = {})
        @obj = obj
      end
    end
  end

  let(:interface) { dummy_class.new("monadic" => "true") }

  describe '#configure_monadic_response' do
    let(:body) { {} }

    context 'with OpenAI provider' do
      it 'sets response_format to json_object' do
        result = interface.configure_monadic_response(body, :openai)
        expect(result["response_format"]).to eq({ "type" => "json_object" })
      end
    end

    context 'with Perplexity provider' do
      it 'sets response_format with json_schema' do
        result = interface.configure_monadic_response(body, :perplexity)
        expect(result["response_format"]["type"]).to eq("json_schema")
        expect(result["response_format"]["json_schema"]).to have_key("schema")
      end

      it 'uses Chat Plus schema for chat_plus apps' do
        result = interface.configure_monadic_response(body, :perplexity, "chat_plus_perplexity")
        schema = result["response_format"]["json_schema"]["schema"]
        expect(schema["properties"]["context"]["properties"]).to have_key("reasoning")
      end
    end

    context 'with Claude provider' do
      it 'does not modify body' do
        result = interface.configure_monadic_response(body, :claude)
        expect(result).to eq({})
      end
    end

    context 'with Gemini provider' do
      it 'sets responseMimeType and responseSchema' do
        result = interface.configure_monadic_response(body, :gemini)
        expect(result["generationConfig"]["responseMimeType"]).to eq("application/json")
        expect(result["generationConfig"]["responseSchema"]).to be_a(Hash)
      end
    end

    context 'with Ollama provider' do
      it 'sets format to json' do
        body["messages"] = [{ "role" => "user", "content" => "Hello" }]
        result = interface.configure_monadic_response(body, :ollama)
        expect(result["format"]).to eq("json")
      end

      it 'adds JSON instructions to system message' do
        body["messages"] = [{ "role" => "system", "content" => "You are helpful" }]
        result = interface.configure_monadic_response(body, :ollama)
        expect(result["messages"].first["content"]).to include("JSON object")
      end
    end

    context 'when not in monadic mode' do
      let(:interface) { dummy_class.new("monadic" => "false") }

      it 'returns body unchanged' do
        result = interface.configure_monadic_response(body, :openai)
        expect(result).to eq({})
      end
    end
  end

  describe '#apply_monadic_transformation' do
    context 'in monadic mode' do
      it 'transforms user messages' do
        allow(APPS).to receive(:[]).and_return(double(monadic_unit: '{"message":"test","context":{}}'))
        
        result = interface.apply_monadic_transformation("Hello", "test_app")
        expect(result).to eq('{"message":"test","context":{}}')
      end

      it 'returns original message for non-user roles' do
        result = interface.apply_monadic_transformation("Hello", "test_app", "assistant")
        expect(result).to eq("Hello")
      end

      it 'uses fallback when APPS not available' do
        result = interface.apply_monadic_transformation("Hello", "test_app")
        parsed = JSON.parse(result)
        expect(parsed["message"]).to eq("Hello")
        expect(parsed["context"]).to eq({})
      end
    end
  end

  describe '#process_monadic_response' do
    context 'with valid JSON response' do
      let(:response) { '{"message":"Hello","context":{"test":"data"}}' }

      it 'processes through monadic_map when available' do
        allow(APPS).to receive(:[]).and_return(double(monadic_map: 'mapped_response'))
        
        result = interface.process_monadic_response(response, "test_app")
        expect(result).to eq('mapped_response')
      end

      it 'validates JSON structure when APPS not available' do
        result = interface.process_monadic_response(response, "test_app")
        expect(result).to eq(response)
      end
    end
  end

  describe '#validate_monadic_response' do
    it 'returns valid JSON unchanged' do
      valid_json = '{"message":"test","context":{}}'
      result = interface.validate_monadic_response(valid_json)
      expect(result).to eq(valid_json)
    end

    it 'wraps non-JSON responses' do
      result = interface.validate_monadic_response("plain text")
      parsed = JSON.parse(result)
      expect(parsed["message"]).to eq("plain text")
      expect(parsed["context"]).to eq({})
    end

    it 'adds missing context field' do
      result = interface.validate_monadic_response('{"message":"test"}')
      parsed = JSON.parse(result)
      expect(parsed["context"]).to eq({})
    end

    it 'handles parse errors gracefully' do
      result = interface.validate_monadic_response("{invalid json")
      parsed = JSON.parse(result)
      expect(parsed["message"]).to eq("{invalid json")
      expect(parsed["context"]["error"]).to eq("Failed to parse response as JSON")
    end
  end
end