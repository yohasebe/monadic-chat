# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monadic/utils/response_evaluator'

RSpec.describe Monadic::Utils::ResponseEvaluator do
  describe '.evaluate' do
    context 'without API key' do
      it 'returns error result when API key is not configured' do
        # Temporarily remove the ENV variable
        original_key = ENV['OPENAI_API_KEY']
        ENV['OPENAI_API_KEY'] = nil

        begin
          result = described_class.evaluate(
            response: 'Test response',
            expectation: 'Should contain something',
            api_key: nil
          )

          expect(result.match).to be_nil
          expect(result.confidence).to eq(0.0)
          expect(result.reasoning).to include('API key not configured')
        ensure
          ENV['OPENAI_API_KEY'] = original_key
        end
      end
    end

    context 'with API key', :api do
      before do
        skip 'OPENAI_API_KEY not set' unless ENV['OPENAI_API_KEY']
      end

      it 'evaluates a clearly matching response' do
        result = described_class.evaluate(
          response: 'The validation was successful. Your ABC notation is syntactically correct.',
          expectation: 'The response indicates that validation succeeded',
          prompt: 'Please validate my ABC notation using the validate_abc_syntax tool.',
          criteria: 'Tool execution success'
        )

        expect(result.match).to be true
        expect(result.confidence).to be >= 0.8
        expect(result.reasoning).to be_a(String)
        expect(result.reasoning.length).to be > 10
      end

      it 'evaluates a clearly non-matching response' do
        result = described_class.evaluate(
          response: 'I apologize, but I cannot access that tool.',
          expectation: 'The response indicates that the tool was successfully invoked',
          prompt: 'Please use the validate_abc_syntax tool to check this notation.',
          criteria: 'Tool invocation'
        )

        expect(result.match).to be false
        # With prompt provided, should have higher confidence in the non-match determination
        expect(result.confidence).to be >= 0.6
      end

      it 'handles ambiguous responses appropriately' do
        result = described_class.evaluate(
          response: 'I processed your request.',
          expectation: 'The response explicitly mentions validate_abc_syntax tool was called and shows the exact output',
          criteria: 'Explicit tool mention with output'
        )

        # The response doesn't mention the tool, so match should be false
        # Confidence may vary but the evaluator should recognize the mismatch
        expect(result).to be_a(described_class::EvaluationResult)
        expect(result.reasoning).to be_a(String)
        expect(result.reasoning.length).to be > 0
      end

      it 'uses context for better evaluation' do
        result = described_class.evaluate(
          response: 'The chord progression C-Am-F-G is valid in the key of C major.',
          expectation: 'The AI used music theory knowledge to validate the chords',
          prompt: 'Validate chords C, Am, F, G in key of C',
          criteria: 'Music theory validation',
          context: { tool_name: 'validate_chord_progression' }
        )

        expect(result.match).to be true
        expect(result.confidence).to be >= 0.7
      end
    end
  end

  describe '.matches?' do
    before do
      skip 'OPENAI_API_KEY not set' unless ENV['OPENAI_API_KEY']
    end

    it 'returns true for matching response above threshold', :api do
      result = described_class.matches?(
        response: 'Successfully validated the notation.',
        expectation: 'Response indicates success',
        prompt: 'Please validate this ABC notation.',
        threshold: 0.7
      )

      expect(result).to be true
    end

    it 'returns false for non-matching response', :api do
      result = described_class.matches?(
        response: 'Error: undefined method call_claude',
        expectation: 'Response indicates successful tool execution',
        prompt: 'Please run the validation tool.',
        threshold: 0.7
      )

      expect(result).to be false
    end
  end

  describe '.batch_evaluate' do
    before do
      skip 'OPENAI_API_KEY not set' unless ENV['OPENAI_API_KEY']
    end

    it 'evaluates multiple expectations against one response', :api do
      response = 'I validated your ABC notation using the validate_abc_syntax tool. The syntax is correct.'

      results = described_class.batch_evaluate(
        response: response,
        expectations: [
          { expectation: 'Tool was invoked', criteria: 'Tool usage' },
          { expectation: 'Validation succeeded', criteria: 'Success status' },
          { expectation: 'Response mentions Python code', criteria: 'Python mention' }
        ],
        prompt: 'Please validate my ABC notation using the validate_abc_syntax tool.'
      )

      expect(results.length).to eq(3)
      expect(results[0].match).to be true  # Tool was invoked
      expect(results[1].match).to be true  # Validation succeeded
      expect(results[2].match).to be false # No Python mention
    end
  end

  describe 'EvaluationResult' do
    describe '#success?' do
      it 'returns true for match with high confidence' do
        result = described_class::EvaluationResult.new(match: true, confidence: 0.9, reasoning: 'test')
        expect(result.success?).to be true
      end

      it 'returns false for match with low confidence' do
        result = described_class::EvaluationResult.new(match: true, confidence: 0.5, reasoning: 'test')
        expect(result.success?).to be false
      end

      it 'returns false for non-match regardless of confidence' do
        result = described_class::EvaluationResult.new(match: false, confidence: 0.9, reasoning: 'test')
        expect(result.success?).to be false
      end
    end

    describe '#likely?' do
      it 'returns true when confidence >= 0.5' do
        result = described_class::EvaluationResult.new(match: true, confidence: 0.5, reasoning: 'test')
        expect(result.likely?).to be true
      end

      it 'returns false when confidence < 0.5' do
        result = described_class::EvaluationResult.new(match: true, confidence: 0.4, reasoning: 'test')
        expect(result.likely?).to be false
      end
    end

    describe '#to_h' do
      it 'converts to hash' do
        result = described_class::EvaluationResult.new(match: true, confidence: 0.85, reasoning: 'Looks good')
        hash = result.to_h

        expect(hash).to eq({ match: true, confidence: 0.85, reasoning: 'Looks good' })
      end
    end
  end
end
