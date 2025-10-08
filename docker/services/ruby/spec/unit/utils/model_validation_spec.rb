# frozen_string_literal: true

require_relative '../../../lib/monadic/utils/model_spec'

RSpec.describe 'Model Validation' do
  describe 'MDSL model validation' do
    it 'validates models defined in model_spec.js' do
      # Valid models
      expect(Monadic::Utils::ModelSpec.model_exists?('gpt-5')).to be true
      expect(Monadic::Utils::ModelSpec.model_exists?('claude-3-7-sonnet-20250219')).to be true
      expect(Monadic::Utils::ModelSpec.model_exists?('gemini-2.5-flash')).to be true
    end

    it 'resolves dated versions to base models' do
      # Dated versions should resolve to base models
      normalized = Monadic::Utils::ModelSpec.normalize_model_name('gpt-5-2025-08-07')
      resolved = Monadic::Utils::ModelSpec.resolve_model_alias('gpt-5-2025-08-07')

      expect(normalized).to eq('gpt-5')
      expect(resolved).to eq('gpt-5')
      expect(Monadic::Utils::ModelSpec.model_exists?(resolved)).to be true
    end

    it 'detects invalid model names' do
      # Invalid models that don't exist in model_spec.js
      expect(Monadic::Utils::ModelSpec.model_exists?('gpt-99-ultra')).to be false
      expect(Monadic::Utils::ModelSpec.model_exists?('nonexistent-model')).to be false
    end

    it 'handles models with valid date suffixes' do
      # Models with date suffixes that resolve to existing base models
      # Note: For models that exist with dates, use actual model names from model_spec.js
      valid_dated_models = {
        'gpt-5-2025-01-15' => 'gpt-5',  # Date suffix, resolves to base
        'gemini-2.5-flash-2025-02-01' => 'gemini-2.5-flash',  # Date suffix, resolves to base
        'claude-3-7-sonnet-20250219' => 'claude-3-7-sonnet-20250219'  # Exact match in spec
      }

      valid_dated_models.each do |model, expected_base|
        resolved = Monadic::Utils::ModelSpec.resolve_model_alias(model)
        expect(Monadic::Utils::ModelSpec.model_exists?(resolved)).to(
          be(true),
          "Expected #{model} to resolve to valid model #{resolved}"
        )
      end
    end

    it 'rejects models with invalid date suffixes that do not resolve' do
      # These should not resolve to any valid model
      invalid_models = [
        'unknown-model-2025-01-01',
        'gpt-99-2025-12-31'
      ]

      invalid_models.each do |model|
        resolved = Monadic::Utils::ModelSpec.resolve_model_alias(model)
        expect(Monadic::Utils::ModelSpec.model_exists?(resolved)).to(
          be(false),
          "Expected #{model} (resolved: #{resolved}) to be invalid"
        )
      end
    end
  end

  describe 'Model normalization' do
    it 'removes various date formats' do
      test_cases = {
        'gpt-5-2025-08-07' => 'gpt-5',
        'claude-3-7-sonnet-20250219' => 'claude-3-7-sonnet',
        'command-r7b-12-2024' => 'command-r7b',
        'magistral-small-2509' => 'magistral-small',
        'gemini-2.5-flash-lite-06-17' => 'gemini-2.5-flash-lite',
        'gemini-2.0-flash-001' => 'gemini-2.0-flash'
      }

      test_cases.each do |input, expected|
        result = Monadic::Utils::ModelSpec.normalize_model_name(input)
        expect(result).to eq(expected), "Expected #{input} to normalize to #{expected}, got #{result}"
      end
    end

    it 'preserves non-dated model names' do
      test_cases = [
        'gpt-5',
        'gpt-4.1',
        'claude-3-7-sonnet',
        'gemini-2.5-flash'
      ]

      test_cases.each do |model|
        result = Monadic::Utils::ModelSpec.normalize_model_name(model)
        expect(result).to eq(model), "Expected #{model} to remain unchanged, got #{result}"
      end
    end
  end
end
