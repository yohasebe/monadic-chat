/**
 * @jest-environment jsdom
 */

const path = require('path');

describe('providerDefaults', () => {
  let modelSpec;
  let providerDefaults;

  beforeEach(() => {
    const filePath = path.join(__dirname, '../../docker/services/ruby/public/js/monadic/model_spec.js');
    delete require.cache[require.resolve(filePath)];

    modelSpec = require(filePath);
    providerDefaults = modelSpec.providerDefaults;
  });

  it('should be defined', () => {
    expect(providerDefaults).toBeDefined();
    expect(typeof providerDefaults).toBe('object');
  });

  it('should not appear in Object.keys(module.exports)', () => {
    // providerDefaults is non-enumerable to preserve backward compatibility
    expect(Object.keys(modelSpec)).not.toContain('providerDefaults');
  });

  it('should be accessible via property access', () => {
    expect(modelSpec.providerDefaults).toBeDefined();
    expect(modelSpec.providerDefaults).toBe(providerDefaults);
  });

  describe('provider coverage', () => {
    const expectedProviders = [
      'openai', 'anthropic', 'gemini', 'cohere',
      'mistral', 'xai', 'perplexity', 'deepseek', 'ollama'
    ];

    expectedProviders.forEach(provider => {
      it(`should include ${provider}`, () => {
        expect(providerDefaults[provider]).toBeDefined();
        expect(providerDefaults[provider].chat).toBeDefined();
        expect(Array.isArray(providerDefaults[provider].chat)).toBe(true);
        expect(providerDefaults[provider].chat.length).toBeGreaterThan(0);
      });
    });
  });

  describe('category structure', () => {
    it('openai should have chat, code, vision, and audio_transcription', () => {
      const openai = providerDefaults.openai;
      expect(openai.chat).toBeDefined();
      expect(openai.code).toBeDefined();
      expect(openai.vision).toBeDefined();
      expect(openai.audio_transcription).toBeDefined();
    });

    it('anthropic should have chat, code, and vision', () => {
      const anthropic = providerDefaults.anthropic;
      expect(anthropic.chat).toBeDefined();
      expect(anthropic.code).toBeDefined();
      expect(anthropic.vision).toBeDefined();
    });

    it('gemini should have chat, vision, and audio_transcription', () => {
      const gemini = providerDefaults.gemini;
      expect(gemini.chat).toBeDefined();
      expect(gemini.vision).toBeDefined();
      expect(gemini.audio_transcription).toBeDefined();
    });
  });

  describe('default model values (first element)', () => {
    it('openai chat default is gpt-5.4', () => {
      expect(providerDefaults.openai.chat[0]).toBe('gpt-5.4');
    });

    it('anthropic chat default is claude-sonnet-4-6', () => {
      expect(providerDefaults.anthropic.chat[0]).toBe('claude-sonnet-4-6');
    });

    it('gemini chat default is gemini-3-flash-preview', () => {
      expect(providerDefaults.gemini.chat[0]).toBe('gemini-3-flash-preview');
    });

    it('xai code default is grok-code-fast-1', () => {
      expect(providerDefaults.xai.code[0]).toBe('grok-code-fast-1');
    });
  });

  describe('all listed models exist in modelSpec', () => {
    // Some models are intentionally absent from modelSpec:
    // - Ollama models are dynamic/local and not registered in the static spec
    // - Audio transcription models use dedicated API endpoints, not the chat completions spec
    const skipProviders = new Set(['ollama']);
    const skipCategories = new Set(['audio_transcription']);

    Object.entries(require(path.join(__dirname, '../../docker/services/ruby/public/js/monadic/model_spec.js')).providerDefaults || {}).forEach(([provider, categories]) => {
      if (skipProviders.has(provider)) return;
      Object.entries(categories).forEach(([category, models]) => {
        if (skipCategories.has(category)) return;
        models.forEach(model => {
          it(`${provider}/${category}: ${model} should exist in modelSpec`, () => {
            expect(modelSpec[model]).toBeDefined();
          });
        });
      });
    });
  });

  describe('window.providerDefaults in browser environment', () => {
    it('should set window.providerDefaults when window is defined', () => {
      // jsdom provides window, so the file should set it
      const filePath = path.join(__dirname, '../../docker/services/ruby/public/js/monadic/model_spec.js');
      delete require.cache[require.resolve(filePath)];

      // Execute in a fresh context that has window
      require(filePath);
      expect(window.providerDefaults).toBeDefined();
      expect(window.providerDefaults.openai).toBeDefined();
    });
  });
});
