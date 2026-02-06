/**
 * @jest-environment jsdom
 */

describe('WebSearch Tavily Check Module', () => {
  beforeEach(() => {
    jest.resetModules();
    delete window.websearchTavilyCheck;
    require('../../docker/services/ruby/public/js/monadic/websearch_tavily_check.js');
  });

  afterEach(() => {
    delete window.websearchTavilyCheck;
  });

  describe('requiresTavilyAPI', () => {
    const requiresTavilyAPI = () => window.websearchTavilyCheck.requiresTavilyAPI;

    it('returns false for null/undefined provider', () => {
      expect(requiresTavilyAPI()(null)).toBe(false);
      expect(requiresTavilyAPI()(undefined)).toBe(false);
      expect(requiresTavilyAPI()('')).toBe(false);
    });

    it('returns false for native web search providers', () => {
      expect(requiresTavilyAPI()('openai')).toBe(false);
      expect(requiresTavilyAPI()('perplexity')).toBe(false);
      expect(requiresTavilyAPI()('grok')).toBe(false);
      expect(requiresTavilyAPI()('xai')).toBe(false);
      expect(requiresTavilyAPI()('gemini')).toBe(false);
      expect(requiresTavilyAPI()('google')).toBe(false);
      expect(requiresTavilyAPI()('claude')).toBe(false);
      expect(requiresTavilyAPI()('anthropic')).toBe(false);
    });

    it('returns true for providers requiring Tavily', () => {
      expect(requiresTavilyAPI()('deepseek')).toBe(true);
      expect(requiresTavilyAPI()('mistral')).toBe(true);
      expect(requiresTavilyAPI()('cohere')).toBe(true);
      expect(requiresTavilyAPI()('ollama')).toBe(true);
    });

    it('is case-insensitive', () => {
      expect(requiresTavilyAPI()('OpenAI')).toBe(false);
      expect(requiresTavilyAPI()('DeepSeek')).toBe(true);
      expect(requiresTavilyAPI()('MISTRAL')).toBe(true);
    });

    it('matches partial provider names', () => {
      expect(requiresTavilyAPI()('openai-gpt4')).toBe(false);
      expect(requiresTavilyAPI()('deepseek-chat')).toBe(true);
    });

    it('returns false for unknown providers', () => {
      expect(requiresTavilyAPI()('unknown-provider')).toBe(false);
    });
  });

  describe('updateWebSearchState', () => {
    it('is exported as a function', () => {
      expect(typeof window.websearchTavilyCheck.updateWebSearchState).toBe('function');
    });
  });
});
