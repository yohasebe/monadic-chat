# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/monadic/monadic_provider_interface'
require_relative '../../lib/monadic/monadic_schema_validator'

RSpec.describe 'Real-world Monadic Scenarios' do
  let(:test_class) do
    Class.new do
      include MonadicProviderInterface
      include MonadicSchemaValidator
      attr_accessor :obj
      
      def initialize
        @obj = { "monadic" => "true" }
      end
    end
  end
  
  let(:handler) { test_class.new }

  describe 'Perplexity malformed JSON handling' do
    it 'handles double-encoded JSON' do
      # Perplexity sometimes returns double-encoded JSON
      double_encoded = '"{\\\"message\\\":\\\"Test response\\\",\\\"context\\\":{\\\"data\\\":\\\"value\\\"}}"'
      
      result = handler.safe_parse_monadic_response(double_encoded)
      expect(result["message"]).to eq("Test response")
      expect(result["context"]["data"]).to eq("value")
    end
    
    it 'handles JSON with extra braces' do
      # Sometimes Perplexity adds extra characters
      malformed = '{"{\"message\":\"Test\",\"context\":{}}'
      
      result = handler.safe_parse_monadic_response(malformed)
      expect(result["message"]).to eq("Test")
      expect(result["context"]).to eq({})
    end
    
    it 'handles escaped quotes in content' do
      json_with_quotes = '{"message": "She said \\"Hello\\" to me", "context": {"quoted": true}}'
      
      result = handler.safe_parse_monadic_response(json_with_quotes)
      expect(result["message"]).to include('She said "Hello" to me')
    end
  end

  describe 'Chat Plus complex responses' do
    it 'handles deeply nested context' do
      complex_response = {
        "message" => "Analysis complete",
        "context" => {
          "reasoning" => "Multi-step analysis performed",
          "topics" => ["AI", "Machine Learning", "Neural Networks"],
          "people" => ["Alan Turing", "Geoffrey Hinton"],
          "notes" => [
            "Important discovery about backpropagation",
            "New optimization technique found"
          ],
          "additional_data" => {
            "metrics" => {
              "accuracy" => 0.95,
              "loss" => 0.05
            },
            "references" => ["paper1", "paper2"]
          }
        }
      }
      
      validated = handler.validate_monadic_response!(complex_response, :chat_plus)
      expect(validated["context"]["additional_data"]["metrics"]["accuracy"]).to eq(0.95)
    end
    
    it 'handles arrays with mixed types' do
      response = {
        "message" => "Mixed data",
        "context" => {
          "reasoning" => "Testing mixed arrays",
          "topics" => ["topic1", nil, "", "topic2"],
          "people" => [],
          "notes" => ["note1", 123, { "nested" => "object" }]
        }
      }
      
      validated = handler.validate_monadic_response!(response, :chat_plus)
      # Should handle without crashing
      expect(validated["context"]["topics"]).to include("topic1")
    end
  end

  describe 'Unicode and special characters' do
    it 'handles emoji and unicode' do
      unicode_response = {
        "message" => "Hello 👋 世界 🌍",
        "context" => {
          "emoji" => "🤖💬",
          "japanese" => "こんにちは",
          "special" => "café ñoño"
        }
      }
      
      json = JSON.generate(unicode_response)
      validated = handler.validate_monadic_response!(json)
      
      parsed = JSON.parse(validated)
      expect(parsed["message"]).to include("👋")
      expect(parsed["context"]["japanese"]).to eq("こんにちは")
    end
    
    it 'handles control characters' do
      response_with_control = {
        "message" => "Line 1\nLine 2\tTabbed",
        "context" => {
          "formatted" => "Some\r\nWindows\r\nText"
        }
      }
      
      validated = handler.validate_monadic_response!(response_with_control)
      parsed = JSON.parse(validated)
      expect(parsed["message"]).to include("\n")
    end
  end

  describe 'Error recovery scenarios' do
    it 'recovers from truncated JSON' do
      truncated = '{"message": "This is a long message that got cut off...", "context": {"data": "incomple'
      
      result = handler.safe_parse_monadic_response(truncated)
      expect(result["message"]).to eq(truncated)
      expect(result["context"]["parse_error"]).to be true
    end
    
    it 'handles responses with syntax errors' do
      syntax_error = '{"message": "Test", "context": {missing_quotes: value}}'
      
      result = handler.safe_parse_monadic_response(syntax_error)
      expect(result["message"]).to eq(syntax_error)
      expect(result["context"]["parse_error"]).to be true
    end
    
    it 'handles responses with trailing commas' do
      trailing_comma = '{"message": "Test", "context": {"key": "value",},}'
      
      result = handler.safe_parse_monadic_response(trailing_comma)
      # Should either parse successfully or wrap as error
      expect(result).to have_key("message")
      expect(result).to have_key("context")
    end
  end

  describe 'Large response handling' do
    it 'handles very long messages' do
      long_message = "x" * 10000
      response = {
        "message" => long_message,
        "context" => {}
      }
      
      validated = handler.validate_monadic_response!(response)
      parsed = JSON.parse(validated)
      expect(parsed["message"].length).to eq(10000)
    end
    
    it 'handles many context fields' do
      large_context = {
        "message" => "Test",
        "context" => {}
      }
      
      # Add 1000 fields to context
      1000.times do |i|
        large_context["context"]["field_#{i}"] = "value_#{i}"
      end
      
      validated = handler.validate_monadic_response!(large_context)
      parsed = JSON.parse(validated)
      expect(parsed["context"]["field_999"]).to eq("value_999")
    end
  end

  describe 'Type coercion and validation' do
    it 'handles numeric messages' do
      response = {
        "message" => 42,
        "context" => {}
      }
      
      validated = handler.validate_monadic_response!(response)
      expect(validated).to include("must be a string")
    end
    
    it 'handles boolean contexts' do
      response = {
        "message" => "Test",
        "context" => true
      }
      
      validated = handler.validate_monadic_response!(response)
      parsed = JSON.parse(validated)
      expect(parsed["context"]).to be_a(Hash)
    end
    
    it 'preserves null values appropriately' do
      response = {
        "message" => "Test",
        "context" => {
          "null_field" => nil,
          "empty_string" => "",
          "false_value" => false
        }
      }
      
      validated = handler.validate_monadic_response!(response)
      parsed = JSON.parse(validated)
      expect(parsed["context"]["null_field"]).to be_nil
      expect(parsed["context"]["empty_string"]).to eq("")
      expect(parsed["context"]["false_value"]).to be false
    end
  end

  describe 'Streaming response assembly' do
    it 'handles responses split across chunks' do
      chunks = [
        '{"message": "Part 1',
        ' of the message", "context": {',
        '"streaming": true, "chunk_count": 3}}'
      ]
      
      # Simulate assembling chunks
      full_response = chunks.join("")
      validated = handler.validate_monadic_response!(full_response)
      
      parsed = JSON.parse(validated)
      expect(parsed["message"]).to eq("Part 1 of the message")
      expect(parsed["context"]["chunk_count"]).to eq(3)
    end
  end

  describe 'Provider-specific quirks' do
    it 'handles OpenAI function call responses mixed with content' do
      # Sometimes OpenAI returns both content and function calls
      mixed_response = {
        "message" => "I'll help you with that",
        "context" => {
          "function_call" => {
            "name" => "search_web",
            "arguments" => '{"query": "latest news"}'
          }
        }
      }
      
      validated = handler.validate_monadic_response!(mixed_response)
      parsed = JSON.parse(validated)
      expect(parsed["context"]["function_call"]["name"]).to eq("search_web")
    end
    
    it 'handles Claude thinking tags in responses' do
      # Claude sometimes includes thinking in responses
      claude_response = {
        "message" => "Here's my answer",
        "context" => {
          "thinking" => "Let me think about this...",
          "confidence" => 0.9
        }
      }
      
      validated = handler.validate_monadic_response!(claude_response)
      parsed = JSON.parse(validated)
      expect(parsed["context"]["thinking"]).to include("think about this")
    end
  end
end