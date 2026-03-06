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

    modelUtils = require(utilsPath);
  });

  afterEach(() => {
    delete window.modelSpec;
  });

  describe('isModelDeprecated', () => {
    it('returns true for models with deprecated: true', () => {
      expect(modelUtils.isModelDeprecated('gpt-4o')).toBe(true);
      expect(modelUtils.isModelDeprecated('gpt-4o-mini')).toBe(true);
      expect(modelUtils.isModelDeprecated('gemini-2.5-flash')).toBe(true);
      expect(modelUtils.isModelDeprecated('gemini-2.5-pro')).toBe(true);
      expect(modelUtils.isModelDeprecated('gemini-2.5-flash-lite')).toBe(true);
      expect(modelUtils.isModelDeprecated('grok-3')).toBe(true);
      expect(modelUtils.isModelDeprecated('command-r-08-2024')).toBe(true);
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
    it('excludes deprecated models from showAllModels provider list', () => {
      const appConfig = { group: 'OpenAI', models: '[]' };
      const models = modelUtils.getModelsForApp(appConfig);
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

    it('excludes deprecated Gemini models', () => {
      const appConfig = { group: 'Gemini', models: '[]' };
      const models = modelUtils.getModelsForApp(appConfig);
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
