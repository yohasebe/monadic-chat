# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/monadic/monadic_provider_interface'
require_relative '../../lib/monadic/monadic_schema_validator'
require_relative '../../lib/monadic/monadic_performance'

RSpec.describe 'Unified Monadic Interface' do
  # Create a test class that includes all modules
  let(:test_class) do
    Class.new do
      include MonadicProviderInterface
      include MonadicSchemaValidator
      include MonadicPerformance
      
      attr_accessor :obj
      
      def initialize(monadic: true)
        @obj = { "monadic" => monadic.to_s }
      end
    end
  end
  
  let(:provider) { test_class.new }

  describe 'Core functionality' do
    it 'configures providers correctly' do
      # Test each provider configuration
      providers = {
        openai: { "response_format" => { "type" => "json_object" } },
        claude: {},  # Claude doesn't modify body
        gemini: { "generationConfig" => { "responseMimeType" => "application/json" } },
        mistral: { "response_format" => { "type" => "json_schema" } },
        ollama: { "format" => "json" }
      }
      
      providers.each do |provider_type, expected|
        body = {}
        result = provider.configure_monadic_response(body, provider_type)
        
        expected.each do |key, value|
          if value.is_a?(Hash)
            expect(result.dig(*key.split('.'))).to include(value)
          else
            expect(result[key]).to eq(value)
          end
        end
      end
    end
    
    it 'transforms messages consistently' do
      message = "Test message"
      
      # Without APPS, should use fallback
      result = provider.apply_monadic_transformation(message, 'test_app')
      parsed = JSON.parse(result)
      
      expect(parsed["message"]).to eq(message)
      expect(parsed["context"]).to be_a(Hash)
    end
    
    it 'validates and corrects malformed responses' do
      test_cases = [
        # Valid JSON
        { 
          input: '{"message": "Valid", "context": {}}',
          expected_message: "Valid"
        },
        # Missing context
        {
          input: '{"message": "No context"}',
          expected_message: "No context"
        },
        # Plain text
        {
          input: "Just plain text",
          expected_message: "Just plain text"
        }
      ]
      
      test_cases.each do |test_case|
        result = provider.validate_monadic_response!(test_case[:input])
        
        if result.is_a?(String)
          parsed = JSON.parse(result)
        else
          parsed = result
        end
        
        expect(parsed["message"]).to eq(test_case[:expected_message])
        expect(parsed).to have_key("context")
      end
    end
  end

  describe 'Chat Plus support' do
    it 'validates Chat Plus schema correctly' do
      valid_chat_plus = {
        "message" => "Response",
        "context" => {
          "reasoning" => "My reasoning",
          "topics" => ["topic1", "topic2"],
          "people" => ["person1"],
          "notes" => ["note1", "note2"]
        }
      }
      
      result = provider.validate_monadic_response!(valid_chat_plus, :chat_plus)
      expect(result["context"]).not_to have_key("validation_errors")
    end
    
    it 'handles incomplete Chat Plus responses' do
      incomplete = {
        "message" => "Response",
        "context" => {
          "reasoning" => "My reasoning"
          # Missing other required fields
        }
      }
      
      result = provider.validate_monadic_response!(incomplete, :chat_plus)
      # Should either fix or report errors
      expect(result).to have_key("message")
      expect(result).to have_key("context")
    end
  end

  describe 'Performance features' do
    before do
      MonadicPerformance.response_cache.clear
    end
    
    it 'generates consistent cache keys' do
      key1 = MonadicPerformance.generate_cache_key(
        "openai", 
        "gpt-4", 
        [{ "role" => "user", "content" => "Hi" }]
      )
      
      key2 = MonadicPerformance.generate_cache_key(
        "openai", 
        "gpt-4", 
        [{ "role" => "user", "content" => "Hi" }]
      )
      
      expect(key1).to eq(key2)
    end
    
    it 'tracks performance metrics' do
      # Perform some operations
      5.times do
        provider.validate_monadic_response!('{"message": "test", "context": {}}')
      end
      
      report = MonadicPerformance.get_performance_report
      expect(report).to have_key(:operation_stats)
      expect(report[:operation_stats]).to be_an(Array)
    end
  end

  describe 'Provider integration' do
    it 'handles provider-specific response formats' do
      # Simulate different provider response styles
      responses = {
        # OpenAI style
        openai: '{"message": "Openai response", "context": {"model": "gpt-4"}}',
        # Claude style (sometimes has extra fields)
        claude: '{"message": "Claude response", "context": {"thinking": "process"}}',
        # Gemini style
        gemini: '{"message": "Gemini response", "context": {"confidence": 0.95}}',
        # Perplexity style (sometimes malformed)
        perplexity: '{"message": "Perplexity response", "context": {"sources": []}}',
      }
      
      responses.each do |provider_name, response|
        result = provider.validate_monadic_response!(response)
        
        if result.is_a?(String)
          parsed = JSON.parse(result)
        else
          parsed = result
        end
        
        expect(parsed["message"]).to include("#{provider_name.to_s.capitalize} response")
        expect(parsed["context"]).to be_a(Hash)
      end
    end
  end

  describe 'Error handling' do
    it 'handles various error conditions gracefully' do
      error_cases = [
        nil,
        "",
        "{}",
        '{"incomplete": ',
        '{"message": null, "context": null}',
        '[]',
        'true',
        '42'
      ]
      
      error_cases.each do |error_case|
        expect {
          result = provider.validate_monadic_response!(error_case)
          # Should not raise errors
          expect(result).to be_truthy
        }.not_to raise_error
      end
    end
  end

  describe 'Non-monadic mode' do
    let(:non_monadic_provider) { test_class.new(monadic: false) }
    
    it 'bypasses processing when monadic mode is disabled' do
      # Configuration should not modify body
      body = { "test" => "data" }
      result = non_monadic_provider.configure_monadic_response(body, :openai)
      expect(result).to eq(body)
      
      # Transformation should return original
      message = "Original message"
      result = non_monadic_provider.apply_monadic_transformation(message, 'app')
      expect(result).to eq(message)
      
      # Validation should return original
      response = "Plain response"
      result = non_monadic_provider.validate_monadic_response(response)
      expect(result).to eq(response)
    end
  end
end