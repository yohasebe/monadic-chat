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
  'grok-4.3': {
    reasoning_effort: [['minimal', 'low', 'medium', 'high'], 'medium']
  },
  'grok-4.20-0309-reasoning': {
    reasoning_effort: [['low', 'high'], 'low']
  },
  'gemini-levels': {
    supports_thinking_level: true,
    reasoning_effort: [['low', 'medium', 'high', 'xhigh'], 'low']
  },
  'deepseek-reasoner': {
    reasoning_content: ['disabled', 'enabled'],
    reasoning_effort: [['none', 'low', 'high', 'max'], 'high']
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
      expect(ReasoningMapper.isSupported('xAI', 'grok-4.3')).toBe(true);
    });

    test('DeepSeek is supported', () => {
      expect(ReasoningMapper.isSupported('DeepSeek', 'deepseek-reasoner')).toBe(true);
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
      expect(options).toEqual(['low', 'medium', 'high']);
    });

    test('Gemini with can_disable returns all options', () => {
      const options = ReasoningMapper.getAvailableOptions('Google', 'gemini-2.5-flash');
      expect(options).toEqual(['minimal', 'low', 'medium', 'high']);
    });

    test('Grok returns low and high options', () => {
      const options = ReasoningMapper.getAvailableOptions('xAI', 'grok-4.20-0309-reasoning');
      expect(options).toEqual(['low', 'high']);
    });

    test('DeepSeek returns the levels its spec lists', () => {
      const options = ReasoningMapper.getAvailableOptions('DeepSeek', 'deepseek-reasoner');
      expect(options).toEqual(['none', 'low', 'high', 'max']);
    });
  });

  describe('mapToProviderParameter', () => {
    test('OpenAI maps directly', () => {
      const result = ReasoningMapper.mapToProviderParameter('OpenAI', 'gpt-5', 'low');
      expect(result).toEqual({ reasoning_effort: 'low' });
    });

    test('Claude sends the effort chosen', () => {
      const result = ReasoningMapper.mapToProviderParameter('Anthropic', 'claude-sonnet-4-20250514', 'medium');
      expect(result).toEqual({ reasoning_effort: 'medium' });
    });

    test('Claude sends an effort above high as chosen', () => {
      const result = ReasoningMapper.mapToProviderParameter('Anthropic', 'claude-sonnet-4-20250514', 'max');
      expect(result).toEqual({ reasoning_effort: 'max' });
    });

    test('Gemini maps through reasoning_effort', () => {
      const result = ReasoningMapper.mapToProviderParameter('Google', 'gemini-2.5-flash', 'low');
      expect(result).toEqual({ reasoning_effort: 'low' });
    });

    test('Grok maps reasoning_effort directly', () => {
      const result = ReasoningMapper.mapToProviderParameter('xAI', 'grok-4.20-0309-reasoning', 'low');
      expect(result).toEqual({ reasoning_effort: 'low' });
    });

    test('A DeepSeek chat saved with thinking off restores to off, even with the app effort beside it', () => {
      expect(ReasoningMapper.savedChoice('DeepSeek', { reasoning_content: 'disabled', reasoning_effort: 'low' })).toBe('none');
      expect(ReasoningMapper.savedChoice('DeepSeek', { reasoning_content: 'enabled', reasoning_effort: 'max' })).toBe('max');
      expect(ReasoningMapper.savedChoice('OpenAI', { reasoning_content: 'disabled', reasoning_effort: 'low' })).toBe('low');
    });

    test('Gemini thinking levels carry the choice in both keys, so an app default does not win', () => {
      expect(ReasoningMapper.mapToProviderParameter('Google', 'gemini-levels', 'xhigh'))
        .toEqual({ thinking_level: 'xhigh', reasoning_effort: 'xhigh' });
      expect(ReasoningMapper.mapToProviderParameter('Google', 'gemini-levels', 'minimal')).toBeNull();
    });

    test('DeepSeek turns thinking off for none and on at the chosen level otherwise', () => {
      expect(ReasoningMapper.mapToProviderParameter('DeepSeek', 'deepseek-reasoner', 'low'))
        .toEqual({ reasoning_content: 'enabled', reasoning_effort: 'low' });
      expect(ReasoningMapper.mapToProviderParameter('DeepSeek', 'deepseek-reasoner', 'none'))
        .toEqual({ reasoning_content: 'disabled', reasoning_effort: 'none' });
      expect(ReasoningMapper.mapToProviderParameter('DeepSeek', 'deepseek-reasoner', 'medium')).toBeNull();
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
      const result = ReasoningMapper.getDefaultValue('xAI', 'grok-4.3');
      expect(result).toBe('medium');
    });

    test('DeepSeek returns spec default', () => {
      const result = ReasoningMapper.getDefaultValue('DeepSeek', 'deepseek-reasoner');
      expect(result).toBe('high');
    });

  });
});
