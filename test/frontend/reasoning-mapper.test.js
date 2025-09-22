/**
 * @jest-environment jsdom
 */

// Load the ReasoningMapper and model_spec
const fs = require('fs');
const path = require('path');

// Mock model_spec
global.modelSpec = {
  'gpt-5': {
    reasoning_effort: [['minimal', 'low', 'medium', 'high'], 'low']
  },
  'claude-sonnet-4-20250514': {
    supports_thinking: true,
    thinking_budget: {
      min: 1024,
      default: 10000,
      max: null
    }
  },
  'gemini-2.5-flash': {
    thinking_budget: {
      min: 128,
      max: 20000,
      can_disable: true
    }
  },
  'grok-4-fast-reasoning': {
    reasoning_effort: [['minimal', 'low', 'medium', 'high'], 'medium']
  },
  'deepseek-reasoner': {
    reasoning_content: ['disabled', 'enabled']
  },
  'sonar-reasoning': {
    reasoning_effort: [['minimal', 'low', 'medium', 'high'], 'medium']
  }
};

// Load ReasoningMapper
const reasoningMapperPath = path.join(__dirname, '../../docker/services/ruby/public/js/monadic/reasoning-mapper.js');
const reasoningMapperCode = fs.readFileSync(reasoningMapperPath, 'utf8');

// Execute the code to make ReasoningMapper available
eval(reasoningMapperCode);

describe('ReasoningMapper', () => {
  beforeEach(() => {
    // Make sure ReasoningMapper is available
    expect(ReasoningMapper).toBeDefined();
  });

  describe('isSupported', () => {
    test('OpenAI GPT-5 is supported', () => {
      expect(ReasoningMapper.isSupported('OpenAI', 'gpt-5')).toBe(true);
    });

    test('Claude Sonnet 4 is supported', () => {
      expect(ReasoningMapper.isSupported('Anthropic', 'claude-sonnet-4-20250514')).toBe(true);
    });

    test('Gemini 2.5 Flash is supported', () => {
      expect(ReasoningMapper.isSupported('Google', 'gemini-2.5-flash')).toBe(true);
    });

    test('Grok is supported', () => {
      expect(ReasoningMapper.isSupported('xAI', 'grok-4-fast-reasoning')).toBe(true);
    });

    test('DeepSeek is supported', () => {
      expect(ReasoningMapper.isSupported('DeepSeek', 'deepseek-reasoner')).toBe(true);
    });

    test('Perplexity is supported', () => {
      expect(ReasoningMapper.isSupported('Perplexity', 'sonar-reasoning')).toBe(true);
    });

    test('Unsupported provider returns false', () => {
      expect(ReasoningMapper.isSupported('Unsupported', 'model')).toBe(false);
    });
  });

  describe('getAvailableOptions', () => {
    test('OpenAI returns all options', () => {
      const options = ReasoningMapper.getAvailableOptions('OpenAI', 'gpt-5');
      expect(options).toEqual(['minimal', 'low', 'medium', 'high']);
    });

    test('Claude returns mapped options', () => {
      const options = ReasoningMapper.getAvailableOptions('Anthropic', 'claude-sonnet-4-20250514');
      expect(options).toEqual(['minimal', 'low', 'medium', 'high']);
    });

    test('Gemini with can_disable returns all options', () => {
      const options = ReasoningMapper.getAvailableOptions('Google', 'gemini-2.5-flash');
      expect(options).toEqual(['minimal', 'low', 'medium', 'high']);
    });

    test('Grok returns options without minimal', () => {
      const options = ReasoningMapper.getAvailableOptions('xAI', 'grok-4-fast-reasoning');
      expect(options).toEqual(['minimal', 'low', 'medium', 'high']);
    });

    test('DeepSeek returns limited options', () => {
      const options = ReasoningMapper.getAvailableOptions('DeepSeek', 'deepseek-reasoner');
      expect(options).toEqual(['minimal', 'medium']);
    });
  });

  describe('mapToProviderParameter', () => {
    test('OpenAI maps directly', () => {
      const result = ReasoningMapper.mapToProviderParameter('OpenAI', 'gpt-5', 'low');
      expect(result).toEqual({ reasoning_effort: 'low' });
    });

    test('Claude maps to thinking_budget', () => {
      const result = ReasoningMapper.mapToProviderParameter('Anthropic', 'claude-sonnet-4-20250514', 'medium');
      expect(result).toEqual({ thinking_budget: 10000 });
    });

    test('Gemini maps through reasoning_effort', () => {
      const result = ReasoningMapper.mapToProviderParameter('Google', 'gemini-2.5-flash', 'low');
      expect(result).toEqual({ reasoning_effort: 'low' });
    });

    test('Grok maps minimal to low', () => {
      const result = ReasoningMapper.mapToProviderParameter('xAI', 'grok-4-fast-reasoning', 'minimal');
      expect(result).toEqual({ reasoning_effort: 'minimal' });
    });

    test('DeepSeek maps to enabled/disabled', () => {
      const mediumResult = ReasoningMapper.mapToProviderParameter('DeepSeek', 'deepseek-reasoner', 'medium');
      expect(mediumResult).toEqual({ reasoning_content: 'enabled' });

      const minimalResult = ReasoningMapper.mapToProviderParameter('DeepSeek', 'deepseek-reasoner', 'minimal');
      expect(minimalResult).toEqual({ reasoning_content: 'disabled' });
    });

    test('Unsupported combinations return null', () => {
      const result = ReasoningMapper.mapToProviderParameter('Unsupported', 'model', 'medium');
      expect(result).toBeNull();
    });
  });

  describe('getDefaultValue', () => {
    test('OpenAI returns spec default', () => {
      const result = ReasoningMapper.getDefaultValue('OpenAI', 'gpt-5');
      expect(result).toBe('low');
    });

    test('Claude returns medium', () => {
      const result = ReasoningMapper.getDefaultValue('Anthropic', 'claude-sonnet-4-20250514');
      expect(result).toBe('medium');
    });

    test('Grok returns spec default', () => {
      const result = ReasoningMapper.getDefaultValue('xAI', 'grok-4-fast-reasoning');
      expect(result).toBe('medium');
    });

    test('DeepSeek returns medium', () => {
      const result = ReasoningMapper.getDefaultValue('DeepSeek', 'deepseek-reasoner');
      expect(result).toBe('medium');
    });

    test('Perplexity returns spec default', () => {
      const result = ReasoningMapper.getDefaultValue('Perplexity', 'sonar-reasoning');
      expect(result).toBe('medium');
    });
  });
});
