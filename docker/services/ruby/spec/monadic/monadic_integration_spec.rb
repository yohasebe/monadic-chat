# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/monadic/monadic_provider_interface'
require_relative '../../lib/monadic/monadic_schema_validator'
require_relative '../../lib/monadic/monadic_performance'

# Mock app for testing
class MockMonadicApp
  attr_reader :name
  
  def initialize(name)
    @name = name
  end
  
  def monadic_unit(message)
    JSON.generate({
      "message" => message,
      "context" => {
        "app" => @name,
        "timestamp" => Time.now.to_i
      }
    })
  end
  
  def monadic_map(content)
    begin
      parsed = JSON.parse(content)
      parsed["context"]["processed"] = true
      JSON.generate(parsed)
    rescue JSON::ParserError
      content
    end
  end
end

# Test class that includes all modules
class IntegratedProvider
  include MonadicProviderInterface
  include MonadicSchemaValidator
  include MonadicPerformance
  
  attr_accessor :obj
  
  def initialize(monadic: true)
    @obj = { "monadic" => monadic.to_s }
  end
end

RSpec.describe 'Monadic System Integration' do
  let(:provider) { IntegratedProvider.new }
  let(:app) { MockMonadicApp.new('test_app') }
  
  before do
    # Mock APPS
    stub_const('APPS', { 'test_app' => app })
  end

  describe 'End-to-end monadic flow' do
    context 'with OpenAI-style provider' do
      it 'configures, transforms, and validates correctly' do
        # 1. Configure request
        body = {}
        configured = provider.configure_monadic_response(body, :openai, 'test_app')
        expect(configured["response_format"]["type"]).to eq("json_object")
        
        # 2. Transform user message
        user_message = "Hello, world!"
        transformed = provider.apply_monadic_transformation(user_message, 'test_app')
        parsed = JSON.parse(transformed)
        expect(parsed["message"]).to eq(user_message)
        expect(parsed["context"]["app"]).to eq('test_app')
        
        # 3. Process response
        api_response = '{"message": "Hello back!", "context": {"ai": true}}'
        processed = provider.process_monadic_response(api_response, 'test_app')
        validated = provider.validate_monadic_response!(processed)
        
        final = JSON.parse(validated)
        expect(final["message"]).to eq("Hello back!")
        expect(final["context"]["processed"]).to be true
      end
    end

    context 'with Gemini-style provider' do
      it 'configures with responseSchema' do
        body = {}
        configured = provider.configure_monadic_response(body, :gemini, 'chat_plus_gemini')
        
        expect(configured["generationConfig"]["responseMimeType"]).to eq("application/json")
        expect(configured["generationConfig"]["responseSchema"]).to be_a(Hash)
        expect(configured["generationConfig"]["responseSchema"]["properties"]).to have_key("context")
      end
    end

    context 'with Claude-style provider' do
      it 'does not modify body directly' do
        body = { "messages" => [] }
        configured = provider.configure_monadic_response(body, :claude, 'test_app')
        
        # Claude uses system prompts, so body should remain mostly unchanged
        expect(configured["messages"]).to eq([])
        expect(configured).not_to have_key("response_format")
      end
    end

    context 'with Ollama-style provider' do
      it 'adds format and system instructions' do
        body = { "messages" => [{ "role" => "user", "content" => "Hi" }] }
        configured = provider.configure_monadic_response(body, :ollama, 'test_app')
        
        expect(configured["format"]).to eq("json")
        expect(configured["messages"].first["role"]).to eq("system")
        expect(configured["messages"].first["content"]).to include("JSON object")
      end
    end
  end

  describe 'Error handling and recovery' do
    it 'handles malformed JSON responses' do
      malformed_responses = [
        '{"message": "incomplete',
        '{"{\"message\":\"test\",\"context\":{}}',  # Perplexity-style
        'Just plain text',
        '{"message": 123, "context": "not an object"}',
        nil,
        ""
      ]
      
      malformed_responses.each do |response|
        validated = provider.validate_monadic_response!(response)
        parsed = JSON.parse(validated)
        
        expect(parsed).to have_key("message")
        expect(parsed).to have_key("context")
        expect(parsed["context"]).to be_a(Hash)
      end
    end

    it 'validates Chat Plus schema' do
      chat_plus_response = {
        "message" => "Test",
        "context" => {
          "reasoning" => "Because",
          "topics" => ["topic1"],
          "people" => [],
          "notes" => ["note1"]
        }
      }
      
      validated = provider.validate_monadic_response!(chat_plus_response, :chat_plus)
      expect(validated).to be_a(Hash)
      expect(validated["context"]).not_to have_key("validation_errors")
    end

    it 'reports missing Chat Plus fields' do
      incomplete_response = {
        "message" => "Test",
        "context" => {
          "reasoning" => "Because"
          # Missing topics, people, notes
        }
      }
      
      validated = provider.validate_monadic_response!(incomplete_response, :chat_plus)
      expect(validated["context"]["validation_errors"]).to include("missing required fields")
    end
  end

  describe 'Performance optimization' do
    before do
      MonadicPerformance.response_cache.clear
    end

    it 'caches responses for identical requests' do
      messages = [{ "role" => "user", "content" => "Test" }]
      cache_key = MonadicPerformance.generate_cache_key("openai", "gpt-4", messages)
      
      # First call
      response = '{"message": "Cached response", "context": {}}'
      result1 = MonadicPerformance.parse_json_with_cache(response, cache_key)
      
      # Second call should hit cache
      result2 = MonadicPerformance.parse_json_with_cache(response, cache_key)
      
      expect(result1).to eq(result2)
      expect(result1["message"]).to eq("Cached response")
    end

    it 'tracks performance metrics' do
      10.times do |i|
        provider.apply_monadic_transformation("Message #{i}", 'test_app')
      end
      
      report = MonadicPerformance.get_performance_report
      expect(report[:operation_stats]).to be_an(Array)
      
      # Check if monadic operations were tracked
      transform_stat = report[:operation_stats].find { |s| s[:operation] == "monadic_transform" }
      expect(transform_stat).not_to be_nil if report[:operation_stats].any?
    end
  end

  describe 'Multi-provider consistency' do
    let(:providers) { [:openai, :claude, :gemini, :mistral, :cohere, :ollama] }
    let(:test_message) { "Test message for all providers" }
    
    it 'produces consistent transformations across providers' do
      results = providers.map do |provider_type|
        # All should produce same basic structure
        transformed = provider.apply_monadic_transformation(test_message, 'test_app')
        JSON.parse(transformed)
      end
      
      # All results should have same structure
      results.each do |result|
        expect(result["message"]).to eq(test_message)
        expect(result["context"]).to be_a(Hash)
      end
    end
    
    it 'validates responses consistently' do
      test_response = '{"message": "AI response", "context": {"data": "test"}}'
      
      validated_responses = providers.map do |provider_type|
        provider.validate_monadic_response(test_response)
      end
      
      # All should produce identical valid JSON
      validated_responses.each do |validated|
        parsed = JSON.parse(validated)
        expect(parsed["message"]).to eq("AI response")
        expect(parsed["context"]["data"]).to eq("test")
      end
    end
  end

  describe 'Edge cases and robustness' do
    it 'handles empty messages gracefully' do
      expect(provider.apply_monadic_transformation("", 'test_app', 'user')).to eq("")
      expect(provider.apply_monadic_transformation(nil, 'test_app', 'user')).to be_nil
    end

    it 'handles non-monadic mode' do
      non_monadic_provider = IntegratedProvider.new(monadic: false)
      
      body = {}
      configured = non_monadic_provider.configure_monadic_response(body, :openai)
      expect(configured).to eq({})
      
      message = "Test"
      transformed = non_monadic_provider.apply_monadic_transformation(message, 'test_app')
      expect(transformed).to eq(message)
    end

    it 'handles missing APPS gracefully' do
      stub_const('APPS', nil)
      
      # Should fall back to basic transformation
      transformed = provider.apply_monadic_transformation("Test", 'unknown_app')
      parsed = JSON.parse(transformed)
      expect(parsed["message"]).to eq("Test")
      expect(parsed["context"]).to eq({})
    end

    it 'handles very large contexts' do
      large_context = {
        "message" => "Response",
        "context" => {
          "data" => "x" * 10000,
          "arrays" => (1..1000).to_a,
          "nested" => 10.times.map { |i| { "level_#{i}" => { "data" => "test" } } }
        }
      }
      
      json = JSON.generate(large_context)
      validated = provider.validate_monadic_response!(json)
      
      # Should handle without errors
      parsed = JSON.parse(validated)
      expect(parsed["message"]).to eq("Response")
    end
  end

  describe 'Streaming support' do
    let(:parser) { MonadicPerformance::LazyJsonParser.new }
    
    it 'handles streaming responses' do
      chunks = [
        '{"mess',
        'age": "Streaming ',
        'response", "con',
        'text": {"stre',
        'aming": true}}'
      ]
      
      chunks.each { |chunk| parser.add_chunk(chunk) }
      result = parser.get_final_result
      
      expect(result["message"]).to eq("Streaming response")
      expect(result["context"]["streaming"]).to be true
    end
  end
end