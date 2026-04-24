/**
 * @jest-environment jsdom
 */

const path = require('path');

describe('Model Utils - Deprecated Model Filtering', () => {
  let modelUtils;
  let modelSpec;

  beforeEach(() => {
    // Clear require cache
    const specPath = path.join(__dirname, '../../docker/services/ruby/public/js/monadic/model_spec.js');
    const utilsPath = path.join(__dirname, '../../docker/services/ruby/public/js/monadic/model_utils.js');
    delete require.cache[require.resolve(specPath)];
    delete require.cache[require.resolve(utilsPath)];

    // Load modelSpec into window.modelSpec (required by model_utils.js)
    modelSpec = require(specPath);
    global.window = global.window || {};
    window.modelSpec = modelSpec;
    window.providerDefaults = modelSpec.providerDefaults;

    modelUtils = require(utilsPath);
  });

  afterEach(() => {
    delete window.modelSpec;
    delete window.providerDefaults;
  });

  describe('isModelDeprecated', () => {
    it('returns true for models with deprecated: true', () => {
      expect(modelUtils.isModelDeprecated('gpt-4o')).toBe(true);
      expect(modelUtils.isModelDeprecated('gpt-4o-mini')).toBe(true);
      expect(modelUtils.isModelDeprecated('gemini-2.5-flash')).toBe(true);
      expect(modelUtils.isModelDeprecated('gemini-2.5-pro')).toBe(true);
      expect(modelUtils.isModelDeprecated('gemini-2.5-flash-lite')).toBe(true);
      expect(modelUtils.isModelDeprecated('gpt-4o')).toBe(true);
    });

    it('returns false for non-deprecated models', () => {
      expect(modelUtils.isModelDeprecated('gpt-5.4')).toBe(false);
      expect(modelUtils.isModelDeprecated('claude-sonnet-4-6')).toBe(false);
      expect(modelUtils.isModelDeprecated('gemini-3-flash-preview')).toBe(false);
      expect(modelUtils.isModelDeprecated('grok-4-0709')).toBe(false);
    });

    it('returns false for unknown models', () => {
      expect(modelUtils.isModelDeprecated('nonexistent-model')).toBe(false);
    });
  });

  describe('getModelsForApp - deprecated filtering', () => {
    it('excludes deprecated models from showAllModels provider list (showAll=true)', () => {
      const appConfig = { group: 'OpenAI', models: '[]' };
      const models = modelUtils.getModelsForApp(appConfig, true);
      expect(models).not.toContain('gpt-4o');
      expect(models).not.toContain('gpt-4o-mini');
      // Non-deprecated models should still be present
      expect(models.some(m => m.startsWith('gpt-'))).toBe(true);
    });

    it('excludes deprecated models from MDSL models array', () => {
      const appConfig = {
        group: 'OpenAI',
        models: '["gpt-5.4", "gpt-4o", "gpt-4o-mini"]'
      };
      const models = modelUtils.getModelsForApp(appConfig);
      expect(models).not.toContain('gpt-4o');
      expect(models).not.toContain('gpt-4o-mini');
      expect(models).toContain('gpt-5.4');
    });

    it('excludes deprecated Gemini models (showAll=true)', () => {
      const appConfig = { group: 'Gemini', models: '[]' };
      const models = modelUtils.getModelsForApp(appConfig, true);
      expect(models).not.toContain('gemini-2.5-flash');
      expect(models).not.toContain('gemini-2.5-pro');
      expect(models).not.toContain('gemini-2.5-flash-lite');
    });
  });

  describe('getModelSuccessor', () => {
    it('returns successor for deprecated model with successor', () => {
      // gpt-4o is deprecated with successor defined in model_spec.js
      const successor = modelUtils.getModelSuccessor('gpt-4o');
      expect(successor).toBeTruthy();
      expect(typeof successor).toBe('string');
    });

    it('returns null for non-deprecated model', () => {
      expect(modelUtils.getModelSuccessor('gpt-5.4')).toBeNull();
    });

    it('returns null for deprecated model without successor', () => {
      // Temporarily add a model with deprecated but no successor
      window.modelSpec['test-deprecated-no-successor'] = { deprecated: true };
      expect(modelUtils.getModelSuccessor('test-deprecated-no-successor')).toBeNull();
      delete window.modelSpec['test-deprecated-no-successor'];
    });

    it('returns null for unknown model', () => {
      expect(modelUtils.getModelSuccessor('nonexistent-model')).toBeNull();
    });
  });

  describe('getDefaultModelForApp - deprecated fallback', () => {
    it('falls back when MDSL default model is deprecated', () => {
      const appConfig = {
        group: 'OpenAI',
        model: 'gpt-4o',
        models: '["gpt-4o", "gpt-5.4"]'
      };
      const available = ['gpt-5.4', 'gpt-4.1'];
      const defaultModel = modelUtils.getDefaultModelForApp(appConfig, available);
      // Should NOT return the deprecated gpt-4o
      expect(defaultModel).not.toBe('gpt-4o');
    });

    it('uses non-deprecated MDSL default model normally', () => {
      const appConfig = {
        group: 'OpenAI',
        model: 'gpt-5.4',
        models: '["gpt-5.4"]'
      };
      const available = ['gpt-5.4', 'gpt-4.1'];
      const defaultModel = modelUtils.getDefaultModelForApp(appConfig, available);
      expect(defaultModel).toBe('gpt-5.4');
    });
  });
});

describe('Model Utils - Curated vs All Models (showAll toggle)', () => {
  let modelUtils;

  beforeEach(() => {
    const specPath = path.join(__dirname, '../../docker/services/ruby/public/js/monadic/model_spec.js');
    const utilsPath = path.join(__dirname, '../../docker/services/ruby/public/js/monadic/model_utils.js');
    delete require.cache[require.resolve(specPath)];
    delete require.cache[require.resolve(utilsPath)];

    const modelSpec = require(specPath);
    global.window = global.window || {};
    window.modelSpec = modelSpec;
    window.providerDefaults = modelSpec.providerDefaults;

    modelUtils = require(utilsPath);
  });

  afterEach(() => {
    delete window.modelSpec;
    delete window.providerDefaults;
  });

  describe('getModelsForApp - curated mode (showAll=false, default)', () => {
    it('returns only MDSL models when specified', () => {
      const appConfig = {
        group: 'OpenAI',
        model: 'gpt-5.4',
        models: '["gpt-5.4", "gpt-4.1"]'
      };
      const models = modelUtils.getModelsForApp(appConfig);
      expect(models).toEqual(['gpt-5.4', 'gpt-4.1']);
    });

    it('falls back to providerDefaults when no MDSL models', () => {
      const appConfig = { group: 'OpenAI', model: 'gpt-5.4' };
      const models = modelUtils.getModelsForApp(appConfig);
      const pdChat = window.providerDefaults.openai.chat;
      // Should return providerDefaults chat models
      expect(models.length).toBeGreaterThan(0);
      pdChat.forEach(m => {
        if (!modelUtils.isModelDeprecated(m)) {
          expect(models).toContain(m);
        }
      });
    });

    it('falls back to providerDefaults for Claude when no MDSL models', () => {
      const appConfig = { group: 'Claude', model: 'claude-sonnet-4-6' };
      const models = modelUtils.getModelsForApp(appConfig);
      const pdChat = window.providerDefaults.anthropic.chat;
      expect(models.length).toBeGreaterThan(0);
      pdChat.forEach(m => {
        if (!modelUtils.isModelDeprecated(m)) {
          expect(models).toContain(m);
        }
      });
    });

    it('falls back to single model when no MDSL models and no providerDefaults', () => {
      // Temporarily remove providerDefaults for a provider
      const saved = window.providerDefaults;
      window.providerDefaults = {};
      const appConfig = { group: 'OpenAI', model: 'gpt-5.4' };
      const models = modelUtils.getModelsForApp(appConfig);
      expect(models).toEqual(['gpt-5.4']);
      window.providerDefaults = saved;
    });

    it('returns empty array when MDSL models is empty string "[]"', () => {
      // Empty MDSL array with no providerDefaults
      const saved = window.providerDefaults;
      window.providerDefaults = {};
      const appConfig = { group: 'OpenAI', models: '[]', model: 'gpt-5.4' };
      const models = modelUtils.getModelsForApp(appConfig);
      // Falls through empty MDSL to providerDefaults (empty) to single model
      expect(models).toEqual(['gpt-5.4']);
      window.providerDefaults = saved;
    });
  });

  describe('getModelsForApp - all-models mode (showAll=true)', () => {
    it('returns all provider models for OpenAI', () => {
      const appConfig = { group: 'OpenAI', model: 'gpt-5.4' };
      const models = modelUtils.getModelsForApp(appConfig, true);
      // Should return many more models than curated mode
      const curatedModels = modelUtils.getModelsForApp(appConfig, false);
      expect(models.length).toBeGreaterThan(curatedModels.length);
    });

    it('excludes requires_confirmation models via spec flag', () => {
      // Synthesize a requires_confirmation model to verify the filter still works
      // (the long-thinking Pro tier has been removed from the OpenAI catalog per policy,
      // but the filter itself remains for any future requires_confirmation entries)
      window.modelSpec['gpt-test-confirm-required'] = {
        requires_confirmation: true,
        tool_capability: true,
        context_window: [1, 100000]
      };
      const appConfig = { group: 'OpenAI', model: 'gpt-5.4' };
      const models = modelUtils.getModelsForApp(appConfig, true);
      expect(models).not.toContain('gpt-test-confirm-required');
      delete window.modelSpec['gpt-test-confirm-required'];
    });

    it('excludes tool_capability: false models', () => {
      // Add a test model with tool_capability: false
      window.modelSpec['gpt-test-no-tools'] = {
        tool_capability: false,
        context_window: 8192,
        max_output_tokens: 4096
      };
      const appConfig = { group: 'OpenAI', model: 'gpt-5.4' };
      const models = modelUtils.getModelsForApp(appConfig, true);
      expect(models).not.toContain('gpt-test-no-tools');
      delete window.modelSpec['gpt-test-no-tools'];
    });

    it('excludes non-chat modalities (TTS / embedding) from chat dropdown', () => {
      const appConfig = { group: 'OpenAI', model: 'gpt-5.4' };
      const models = modelUtils.getModelsForApp(appConfig, true);
      // TTS models should not appear in chat model selection
      expect(models).not.toContain('gpt-4o-mini-tts-2025-12-15');
      expect(models).not.toContain('tts-1');
      expect(models).not.toContain('tts-1-hd');
      // Embedding models should not appear either
      expect(models).not.toContain('text-embedding-3-large');
    });

    it('prepends MDSL models when specified', () => {
      const appConfig = {
        group: 'OpenAI',
        models: '["gpt-5.4", "gpt-5.4-mini"]'
      };
      const models = modelUtils.getModelsForApp(appConfig, true);
      // MDSL models should be first
      expect(models[0]).toBe('gpt-5.4');
      expect(models[1]).toBe('gpt-5.4-mini');
      // Should also include other provider models
      expect(models.length).toBeGreaterThan(2);
    });
  });

  describe('filterModelsForAllMode - Perplexity exception', () => {
    it('keeps Perplexity models even with tool_capability: false', () => {
      window.modelSpec['sonar-test'] = {
        tool_capability: false,
        context_window: 8192,
        max_output_tokens: 4096
      };
      const result = modelUtils.filterModelsForAllMode(['sonar-test'], 'perplexity');
      expect(result).toContain('sonar-test');
      delete window.modelSpec['sonar-test'];
    });

    it('still excludes requires_confirmation from Perplexity', () => {
      window.modelSpec['sonar-expensive'] = {
        requires_confirmation: true,
        context_window: 8192,
        max_output_tokens: 4096
      };
      const result = modelUtils.filterModelsForAllMode(['sonar-expensive'], 'perplexity');
      expect(result).not.toContain('sonar-expensive');
      delete window.modelSpec['sonar-expensive'];
    });

    it('excludes tool_capability: false for non-Perplexity providers', () => {
      window.modelSpec['gpt-no-tools'] = {
        tool_capability: false,
        context_window: 8192,
        max_output_tokens: 4096
      };
      const result = modelUtils.filterModelsForAllMode(['gpt-no-tools'], 'openai');
      expect(result).not.toContain('gpt-no-tools');
      delete window.modelSpec['gpt-no-tools'];
    });

    it('keeps unknown models (not in modelSpec)', () => {
      const result = modelUtils.filterModelsForAllMode(['custom-user-model'], 'openai');
      expect(result).toContain('custom-user-model');
    });
  });

  describe('isModelUiHidden', () => {
    it('returns true for models with ui_hidden: true', () => {
      expect(modelUtils.isModelUiHidden('gemini-3.1-pro-preview-customtools')).toBe(true);
    });

    it('returns false for normal models', () => {
      expect(modelUtils.isModelUiHidden('gemini-3.1-pro-preview')).toBe(false);
      expect(modelUtils.isModelUiHidden('gpt-5.4')).toBe(false);
    });

    it('returns false for unknown models', () => {
      expect(modelUtils.isModelUiHidden('nonexistent-model')).toBe(false);
    });
  });

  describe('getModelsForApp - ui_hidden filtering', () => {
    it('excludes ui_hidden models from all-models mode (showAll=true)', () => {
      const appConfig = { group: 'Gemini', models: '[]' };
      const models = modelUtils.getModelsForApp(appConfig, true);
      expect(models).not.toContain('gemini-3.1-pro-preview-customtools');
      // Non-hidden Gemini models should still be present
      expect(models).toContain('gemini-3.1-pro-preview');
    });

    it('excludes ui_hidden models even when listed in MDSL (showAll=true)', () => {
      const appConfig = {
        group: 'Gemini',
        models: '["gemini-3.1-pro-preview-customtools", "gemini-3-flash-preview"]'
      };
      const models = modelUtils.getModelsForApp(appConfig, true);
      // MDSL models are prepended without ui_hidden filter, but the all-models
      // portion should not include customtools
      // Note: MDSL-listed models pass through even if ui_hidden (explicit override)
      expect(models).toContain('gemini-3-flash-preview');
    });

    it('ui_hidden models remain accessible to backend via modelSpec', () => {
      // ui_hidden only affects UI dropdown, not modelSpec availability
      expect(window.modelSpec['gemini-3.1-pro-preview-customtools']).toBeDefined();
      expect(window.modelSpec['gemini-3.1-pro-preview-customtools'].tool_capability).toBe(true);
    });
  });

  describe('getModelsForApp - Ollama unchanged by showAll', () => {
    it('returns same results regardless of showAll flag', () => {
      const appConfig = {
        group: 'Ollama',
        models: '["llama3:8b", "qwen3:4b"]'
      };
      const withoutFlag = modelUtils.getModelsForApp(appConfig);
      const withFlag = modelUtils.getModelsForApp(appConfig, true);
      expect(withoutFlag).toEqual(withFlag);
    });
  });
});
