/**
 * @jest-environment jsdom
 */

const fs = require('fs');
const path = require('path');

// Mock modelSpec
global.modelSpec = {
  'claude-sonnet-4-20250514': {
    supports_thinking: true,
    thinking_budget: { min: 1024, default: 10000, max: null }
  },
  'gemini-2.5-flash': {
    thinking_budget: { min: 128, max: 20000, can_disable: true }
  },
  'grok-4-0709': {
    reasoning_effort: [['low', 'medium', 'high'], 'low']
  },
  'deepseek-reasoner': {
    reasoning_content: ['disabled', 'enabled']
  },
  'sonar-reasoning': {
    reasoning_effort: [['minimal', 'low', 'medium', 'high'], 'medium']
  }
};

// Load ReasoningLabels
const labelsPath = path.join(__dirname, '../../docker/services/ruby/public/js/monadic/reasoning-labels.js');
const labelsCode = fs.readFileSync(labelsPath, 'utf8');
eval(labelsCode);

describe('ReasoningLabels', () => {
  beforeEach(() => {
    expect(ReasoningLabels).toBeDefined();
  });

  describe('getLabel', () => {
    test('returns appropriate label for Claude thinking model', () => {
      expect(ReasoningLabels.getLabel('Anthropic', 'claude-sonnet-4-20250514')).toBe('Thinking Level');
    });

    test('returns appropriate label for Gemini', () => {
      expect(ReasoningLabels.getLabel('Google', 'gemini-2.5-flash')).toBe('Thinking Mode');
    });

    test('returns appropriate label for Grok', () => {
      expect(ReasoningLabels.getLabel('xAI', 'grok-4-0709')).toBe('Reasoning Effort');
    });

    test('returns appropriate label for DeepSeek', () => {
      expect(ReasoningLabels.getLabel('DeepSeek', 'deepseek-reasoner')).toBe('Reasoning Mode');
    });

    test('returns appropriate label for Perplexity', () => {
      expect(ReasoningLabels.getLabel('Perplexity', 'sonar-reasoning')).toBe('Research Depth');
    });
  });

  describe('getDescription', () => {
    test('returns description for Claude', () => {
      const desc = ReasoningLabels.getDescription('Anthropic', 'claude-sonnet-4-20250514');
      expect(desc).toBe('Controls how deeply Claude thinks through problems');
    });

    test('returns description for Gemini', () => {
      const desc = ReasoningLabels.getDescription('Google', 'gemini-2.5-flash');
      expect(desc).toBe('Balances response quality with processing time');
    });

    test('returns description for DeepSeek', () => {
      const desc = ReasoningLabels.getDescription('DeepSeek', 'deepseek-reasoner');
      expect(desc).toBe('Enable or disable step-by-step reasoning');
    });
  });

  describe('getOptionLabel', () => {
    test('returns custom labels for Claude options', () => {
      expect(ReasoningLabels.getOptionLabel('Anthropic', 'minimal')).toBe('Minimal (Fast)');
      expect(ReasoningLabels.getOptionLabel('Anthropic', 'medium')).toBe('Medium (Balanced)');
      expect(ReasoningLabels.getOptionLabel('Anthropic', 'high')).toBe('High (Thorough)');
    });

    test('returns custom labels for DeepSeek options', () => {
      expect(ReasoningLabels.getOptionLabel('DeepSeek', 'minimal')).toBe('Off');
      expect(ReasoningLabels.getOptionLabel('DeepSeek', 'medium')).toBe('On');
    });

    test('returns custom labels for Perplexity options', () => {
      expect(ReasoningLabels.getOptionLabel('Perplexity', 'minimal')).toBe('Quick Search');
      expect(ReasoningLabels.getOptionLabel('Perplexity', 'high')).toBe('Comprehensive Analysis');
    });

    test('returns default label for unknown provider', () => {
      expect(ReasoningLabels.getOptionLabel('Unknown', 'medium')).toBe('Medium');
    });
  });
});