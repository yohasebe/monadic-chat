# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monadic/utils/usage_normalizer'

# Contract for UsageNormalizer.extract: each provider's real response shape maps
# to the common {input, output, reasoning, cached, total} schema. Synthetic
# responses only (no network / no API keys) so it is CI-safe.
RSpec.describe Monadic::Utils::UsageNormalizer do
  describe '.extract' do
    it 'maps OpenAI chat-completions usage (incl reasoning + cached)' do
      raw = { 'usage' => {
        'prompt_tokens' => 1200, 'completion_tokens' => 800, 'total_tokens' => 2000,
        'completion_tokens_details' => { 'reasoning_tokens' => 512 },
        'prompt_tokens_details' => { 'cached_tokens' => 256 }
      } }
      expect(described_class.extract('openai', raw)).to eq(
        input: 1200, output: 800, reasoning: 512, cached: 256, total: 2000
      )
    end

    it 'maps OpenAI/Grok Responses-API usage (input_tokens/output_tokens)' do
      raw = { 'usage' => {
        'input_tokens' => 7000, 'output_tokens' => 1500, 'total_tokens' => 8500,
        'output_tokens_details' => { 'reasoning_tokens' => 900 }
      } }
      expect(described_class.extract('grok', raw)).to eq(
        input: 7000, output: 1500, reasoning: 900, cached: nil, total: 8500
      )
    end

    it 'maps Anthropic/Claude usage with cache read' do
      raw = { 'usage' => {
        'input_tokens' => 3000, 'output_tokens' => 400, 'cache_read_input_tokens' => 2000
      } }
      # No total from Claude -> computed input+output.
      expect(described_class.extract('anthropic', raw)).to eq(
        input: 3000, output: 400, reasoning: nil, cached: 2000, total: 3400
      )
    end

    it 'maps Anthropic thinking_tokens as reasoning (Claude names it thinking, not reasoning)' do
      raw = { 'usage' => {
        'input_tokens' => 2000, 'output_tokens' => 700,
        'output_tokens_details' => { 'thinking_tokens' => 480 }
      } }
      expect(described_class.extract('anthropic', raw)).to eq(
        input: 2000, output: 700, reasoning: 480, cached: nil, total: 2700
      )
    end

    it 'maps Gemini usageMetadata (thoughts + cached)' do
      raw = { 'usageMetadata' => {
        'promptTokenCount' => 5000, 'candidatesTokenCount' => 600,
        'thoughtsTokenCount' => 300, 'cachedContentTokenCount' => 1000,
        'totalTokenCount' => 5600
      } }
      expect(described_class.extract('gemini', raw)).to eq(
        input: 5000, output: 600, reasoning: 300, cached: 1000, total: 5600
      )
    end

    it 'maps Cohere v2 usage nested under "tokens"' do
      raw = { 'usage' => { 'tokens' => { 'input_tokens' => 900, 'output_tokens' => 120 } } }
      expect(described_class.extract('cohere', raw)).to eq(
        input: 900, output: 120, reasoning: nil, cached: nil, total: 1020
      )
    end

    it 'maps Mistral usage' do
      raw = { 'usage' => { 'prompt_tokens' => 400, 'completion_tokens' => 200, 'total_tokens' => 600 } }
      expect(described_class.extract('mistral', raw)).to eq(
        input: 400, output: 200, reasoning: nil, cached: nil, total: 600
      )
    end

    it 'maps DeepSeek usage with cache-hit tokens (the previously-unwired provider)' do
      raw = { 'usage' => {
        'prompt_tokens' => 500, 'completion_tokens' => 300, 'total_tokens' => 800,
        'prompt_cache_hit_tokens' => 128
      } }
      expect(described_class.extract('deepseek', raw)).to eq(
        input: 500, output: 300, reasoning: nil, cached: 128, total: 800
      )
    end

    it 'maps Ollama top-level eval counts' do
      raw = { 'prompt_eval_count' => 350, 'eval_count' => 90, 'done' => true }
      expect(described_class.extract('ollama', raw)).to eq(
        input: 350, output: 90, reasoning: nil, cached: nil, total: 440
      )
    end

    it 'is case-insensitive on the provider name and accepts a bare usage object' do
      raw = { 'input_tokens' => 10, 'output_tokens' => 5 }
      expect(described_class.extract('Claude', raw)[:total]).to eq(15)
    end

    it 'returns an all-nil schema for missing/garbage usage' do
      expect(described_class.extract('openai', nil)).to eq(described_class::EMPTY)
      expect(described_class.extract('openai', {})).to eq(
        input: nil, output: nil, reasoning: nil, cached: nil, total: nil
      )
    end

    it 'coerces stringified numbers (providers sometimes quote counts)' do
      raw = { 'usage' => { 'prompt_tokens' => '120', 'completion_tokens' => '30' } }
      expect(described_class.extract('openai', raw)).to include(input: 120, output: 30, total: 150)
    end
  end
end
