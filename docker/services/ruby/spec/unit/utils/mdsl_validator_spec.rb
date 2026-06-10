# frozen_string_literal: true

require_relative '../../spec_helper'
require 'monadic/utils/mdsl_validator'

# Guards MDSLValidator.validate_reasoning_parameters for DeepSeek.
#
# Context: DeepSeek V4 exposes two INDEPENDENT reasoning controls in its model
# spec — reasoning_content ("disabled"/"enabled", the On/Off toggle) and
# reasoning_effort ("high"/"max", the depth used when thinking is on). Older
# DeepSeek models (deepseek-chat) expose neither. The validator must accept
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

    it 'warns (not errors) when a legacy model lacks reasoning_effort in its spec' do
      # deepseek-chat has reasoning_content but no reasoning_effort.
      result = validate({ reasoning_effort: 'low' }, 'deepseek-chat')
      expect(result[:errors]).to be_empty
      expect(result[:warnings]).to include(a_string_matching(/doesn't support reasoning_effort/))
    end

    it 'still accepts reasoning_content on a legacy model that supports it' do
      result = validate({ reasoning_content: 'disabled' }, 'deepseek-chat')
      expect(result[:errors]).to be_empty
    end

    it 'produces no errors or warnings when neither parameter is set' do
      result = validate({})
      expect(result[:errors]).to be_empty
      expect(result[:warnings]).to be_empty
    end
  end
end
