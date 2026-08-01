# frozen_string_literal: true

require_relative '../../spec_helper'
require 'monadic/utils/mdsl_validator'

# Guards MDSLValidator.validate_reasoning_parameters for DeepSeek.
#
# Context: DeepSeek V4 exposes two INDEPENDENT reasoning controls in its model
# spec — reasoning_content ("disabled"/"enabled", the On/Off toggle) and
# reasoning_effort ("high"/"max", the depth used when thinking is on). The
# retired pre-V4 generation exposed only the former. The validator must accept
# valid values for each, flag invalid values as errors, and warn (not error)
# when a model simply doesn't support the parameter. An earlier version
# rejected reasoning_effort on DeepSeek outright, which was wrong for V4.
RSpec.describe Monadic::Utils::MDSLValidator do
  describe '.validate_reasoning_parameters (DeepSeek)' do
    def validate(config, model = 'deepseek-v4-pro')
      described_class.validate_reasoning_parameters(config, 'DeepSeek', model)
    end

    it 'accepts reasoning_content "disabled" on V4' do
      result = validate(reasoning_content: 'disabled')
      expect(result[:errors]).to be_empty
    end

    it 'accepts reasoning_content "enabled" on V4' do
      result = validate(reasoning_content: 'enabled')
      expect(result[:errors]).to be_empty
    end

    it 'rejects an invalid reasoning_content value' do
      result = validate(reasoning_content: 'sometimes')
      expect(result[:errors]).to include(a_string_matching(/Invalid reasoning_content 'sometimes'/))
    end

    it 'accepts reasoning_effort "high" on V4' do
      result = validate(reasoning_effort: 'high')
      expect(result[:errors]).to be_empty
    end

    it 'rejects reasoning_effort "low" on V4 (only high/max are valid)' do
      result = validate(reasoning_effort: 'low')
      expect(result[:errors]).to include(a_string_matching(/Invalid reasoning_effort 'low'.*high, max/))
    end

    it 'accepts both reasoning_content and reasoning_effort together' do
      result = validate(reasoning_content: 'disabled', reasoning_effort: 'high')
      expect(result[:errors]).to be_empty
    end

    # The retired 2026-07-24 generation (deepseek-chat) had reasoning_content
    # but no reasoning_effort; its entries are gone from model_spec, so the
    # shape is pinned via a stub — the validator behavior (warn, not error)
    # must survive for any future model with that spec shape.
    it 'warns (not errors) when a model lacks reasoning_effort in its spec' do
      allow(Monadic::Utils::ModelSpec).to receive(:get_model_spec)
        .with('deepseek-legacy-shape').and_return({ 'reasoning_content' => %w[disabled enabled] })
      result = validate({ reasoning_effort: 'low' }, 'deepseek-legacy-shape')
      expect(result[:errors]).to be_empty
      expect(result[:warnings]).to include(a_string_matching(/doesn't support reasoning_effort/))
    end

    it 'still accepts reasoning_content on a model whose spec carries only that key' do
      allow(Monadic::Utils::ModelSpec).to receive(:get_model_spec)
        .with('deepseek-legacy-shape').and_return({ 'reasoning_content' => %w[disabled enabled] })
      result = validate({ reasoning_content: 'disabled' }, 'deepseek-legacy-shape')
      expect(result[:errors]).to be_empty
    end

    it 'produces no errors or warnings when neither parameter is set' do
      result = validate({})
      expect(result[:errors]).to be_empty
      expect(result[:warnings]).to be_empty
    end
  end
end
