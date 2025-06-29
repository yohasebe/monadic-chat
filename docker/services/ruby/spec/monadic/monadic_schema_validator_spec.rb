# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/monadic/monadic_provider_interface'
require_relative '../../lib/monadic/monadic_schema_validator'

RSpec.describe MonadicSchemaValidator do
  let(:dummy_class) do
    Class.new do
      include MonadicSchemaValidator
    end
  end

  let(:validator) { dummy_class.new }

  describe '#validate_monadic_response!' do
    context 'with valid monadic response' do
      let(:valid_response) do
        {
          "message" => "Hello",
          "context" => {
            "test" => "data"
          }
        }
      end

      it 'returns validated data' do
        result = validator.validate_monadic_response!(valid_response)
        expect(result).to eq(valid_response)
      end

      it 'validates JSON string' do
        json_string = JSON.generate(valid_response)
        result = validator.validate_monadic_response!(json_string)
        expect(result).to eq(valid_response)
      end
    end

    context 'with missing required fields' do
      it 'auto-fixes missing message field' do
        response = { "context" => {} }
        result = validator.validate_monadic_response!(response)
        expect(result).to have_key("message")
      end

      it 'auto-fixes missing context field' do
        response = { "message" => "Hello" }
        result = validator.validate_monadic_response!(response)
        expect(result).to have_key("context")
        expect(result["context"]).to eq({})
      end
    end

    context 'with Chat Plus schema' do
      let(:chat_plus_response) do
        {
          "message" => "Hello",
          "context" => {
            "reasoning" => "test reasoning",
            "topics" => ["topic1"],
            "people" => ["person1"],
            "notes" => ["note1"]
          }
        }
      end

      it 'validates against Chat Plus schema' do
        result = validator.validate_monadic_response!(chat_plus_response, :chat_plus)
        expect(result).to eq(chat_plus_response)
      end

      it 'reports missing Chat Plus fields' do
        incomplete = {
          "message" => "Hello",
          "context" => {
            "reasoning" => "test"
          }
        }
        result = validator.validate_monadic_response!(incomplete, :chat_plus)
        expect(result["context"]).to have_key("validation_errors")
      end
    end
  end

  describe '#safe_parse_monadic_response' do
    it 'handles direct JSON' do
      json = '{"message":"test","context":{}}'
      result = validator.safe_parse_monadic_response(json)
      expect(result["message"]).to eq("test")
    end

    it 'handles double-encoded JSON' do
      double_encoded = '"{\\"message\\":\\"test\\",\\"context\\":{}}"'
      result = validator.safe_parse_monadic_response(double_encoded)
      expect(result["message"]).to eq("test")
    end

    it 'handles malformed Perplexity JSON' do
      malformed = '{"{"message":"test","context":{}}'
      result = validator.safe_parse_monadic_response(malformed)
      expect(result["message"]).to eq("test")
    end

    it 'wraps unparseable content' do
      result = validator.safe_parse_monadic_response("plain text")
      expect(result["message"]).to eq("plain text")
      expect(result["context"]["parse_error"]).to be true
    end

    it 'handles hash input' do
      hash = { "message" => "test", "context" => {} }
      result = validator.safe_parse_monadic_response(hash)
      expect(result).to eq(hash)
    end
  end

  describe 'field validation' do
    it 'validates string fields' do
      response = {
        "message" => 123,
        "context" => {}
      }
      result = validator.validate_monadic_response!(response)
      expect(result["context"]["validation_errors"]).to include(/must be a string/)
    end

    it 'validates array fields' do
      response = {
        "message" => "test",
        "context" => {
          "topics" => "not an array"
        }
      }
      result = validator.validate_monadic_response!(response, :chat_plus)
      expect(result["context"]["validation_errors"]).to include(/must be an array/)
    end

    it 'validates nested objects' do
      response = {
        "message" => "test",
        "context" => "not an object"
      }
      result = validator.validate_monadic_response!(response)
      expect(result["context"]).to be_a(Hash)
    end
  end

  describe 'error handling' do
    it 'handles parse errors gracefully' do
      result = validator.validate_monadic_response!("{invalid json")
      expect(result["message"]).to eq("Failed to parse response")
      expect(result["context"]["error_type"]).to eq("parse_error")
    end

    it 'handles unexpected errors' do
      allow(validator).to receive(:parse_response).and_raise(StandardError.new("test error"))
      
      result = validator.validate_monadic_response!("test")
      expect(result["message"]).to eq("An unexpected error occurred")
      expect(result["context"]["error_type"]).to eq("unexpected_error")
    end
  end
end