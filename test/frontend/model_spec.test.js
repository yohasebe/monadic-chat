/**
 * @jest-environment jsdom
 */

const fs = require('fs');
const path = require('path');

describe('Model Specification', () => {
  // We'll extract the modelSpec object by requiring the file directly
  let modelSpec;
  
  beforeEach(() => {
    // Clear the require cache to ensure fresh loading
    const filePath = path.join(__dirname, '../../docker/services/ruby/public/js/monadic/model_spec.js');
    delete require.cache[require.resolve(filePath)];
    
    // Require the modelSpec directly - it exports via module.exports
    modelSpec = require(filePath);
  });
  
  it('should be defined as an object', () => {
    expect(modelSpec).toBeDefined();
    expect(typeof modelSpec).toBe('object');
  });
  
  it('should contain major AI models', () => {
    // Test for some key model categories
    expect(modelSpec['gpt-4.1']).toBeDefined();
    expect(modelSpec['claude-sonnet-4-6']).toBeDefined();
    expect(modelSpec['gemini-2.5-flash']).toBeDefined();
    expect(modelSpec['command-a-vision-07-2025']).toBeDefined();
    expect(modelSpec['command-a-reasoning-08-2025']).toBeDefined();
    expect(modelSpec['grok-4-1-fast-reasoning']).toBeDefined();
  });
  
  describe('OpenAI Models', () => {
    it('should have correct parameters for GPT-4.1 model', () => {
      const model = modelSpec['gpt-4.1'];
      
      // Check essential parameters
      expect(model.context_window).toEqual([1, 1047576]);
      expect(model.max_output_tokens).toEqual([1, 32768]);
      expect(model.temperature).toEqual([[0.0, 2.0], 1.0]);
      expect(model.top_p).toEqual([[0.0, 1.0], 1.0]);
      expect(model.vision_capability).toBe(true);
    });
    
    it('should have the correct capabilities for GPT models', () => {
      // Check vision capabilities for various models
      expect(modelSpec['gpt-4.1'].vision_capability).toBe(true);

      // Check tool capabilities
      expect(modelSpec['gpt-4.1'].tool_capability).toBe(true);
    });

    it('should have correct parameters for GPT-5.4-mini', () => {
      const model = modelSpec['gpt-5.4-mini'];
      expect(model).toBeDefined();
      expect(model.context_window).toEqual([1, 400000]);
      expect(model.max_output_tokens).toEqual([1, 128000]);
      expect(model.reasoning_effort[0]).toEqual(expect.arrayContaining(['low', 'medium', 'high']));
      expect(model.reasoning_effort[1]).toBe('low');
      expect(model.tool_capability).toBe(true);
      expect(model.vision_capability).toBe(true);
      expect(model.api_type).toBe('responses');
      expect(model.supports_web_search).toBe(true);
      expect(model.supports_pdf_upload).toBe(true);
      expect(model.supports_file_inputs).toBe(true);
      expect(model.skip_in_progress_events).toBe(true);
    });

    it('should have correct parameters for GPT-5.4-nano', () => {
      const model = modelSpec['gpt-5.4-nano'];
      expect(model).toBeDefined();
      expect(model.context_window).toEqual([1, 400000]);
      expect(model.max_output_tokens).toEqual([1, 128000]);
      expect(model.reasoning_effort[0]).toEqual(expect.arrayContaining(['low', 'medium', 'high']));
      expect(model.reasoning_effort[1]).toBe('low');
      expect(model.tool_capability).toBe(true);
      expect(model.vision_capability).toBe(true);
      expect(model.api_type).toBe('responses');
      expect(model.supports_web_search).toBe(true);
      expect(model.skip_in_progress_events).toBe(true);
      // Nano does not support PDF upload or file inputs
      expect(model.supports_pdf_upload).toBeUndefined();
      expect(model.supports_file_inputs).toBeUndefined();
    });
  });
  
  describe('Anthropic Models', () => {
    it('should have correct parameters for Claude Sonnet 4.6', () => {
      const model = modelSpec['claude-sonnet-4-6'];

      // Check essential parameters
      expect(model.context_window).toEqual([1, 1000000]);
      expect(model.max_output_tokens).toEqual([[1, 64000], 64000]);
      expect(model.thinking_budget).toEqual({
        min: 1024,
        default: 10000,
        max: null
      });
      expect(model.supports_thinking).toBe(true);
      expect(model.supports_adaptive_thinking).toBe(true);
      expect(model.tool_capability).toBe(true);
      expect(model.vision_capability).toBe(true);
    });

    it('should have 1M context for Claude Opus 4.6', () => {
      const model = modelSpec['claude-opus-4-6'];
      expect(model.context_window).toEqual([1, 1000000]);
      expect(model.beta_flags).toEqual([]);
    });

    it('should have 1M context for Claude Sonnet 4.6', () => {
      const model = modelSpec['claude-sonnet-4-6'];
      expect(model.context_window).toEqual([1, 1000000]);
      expect(model.beta_flags).toEqual([]);
    });

    it('should not have pdfs beta header on any Claude model', () => {
      const claudeModels = Object.keys(modelSpec).filter(k => k.startsWith('claude-'));
      claudeModels.forEach(modelName => {
        const model = modelSpec[modelName];
        if (model.beta_flags) {
          expect(model.beta_flags).not.toContain('pdfs-2024-09-25');
        }
      });
    });

    it('should not have structured_output_beta on GA models', () => {
      // These models have structured outputs GA (Jan 29, 2026)
      const gaModels = ['claude-sonnet-4-5-20250929', 'claude-opus-4-5-20251101', 'claude-haiku-4-5-20251001'];
      gaModels.forEach(modelName => {
        const model = modelSpec[modelName];
        if (model) {
          expect(model.structured_output_beta).toBeUndefined();
        }
      });
    });

    it('should have different vision capabilities for different Claude models', () => {
      // Claude Sonnet 4.6 should have vision support
      expect(modelSpec['claude-sonnet-4-6'].vision_capability).toBe(true);

      // Claude Haiku 4.5 has vision support
      expect(modelSpec['claude-haiku-4-5-20251001'].vision_capability).toBe(true);
    });

    it('should mark Opus 4.6 as supporting adaptive thinking', () => {
      expect(modelSpec['claude-opus-4-6'].supports_adaptive_thinking).toBe(true);
    });

    it('should mark Sonnet 4.6 as supporting adaptive thinking', () => {
      expect(modelSpec['claude-sonnet-4-6'].supports_adaptive_thinking).toBe(true);
    });

    it('should not mark older Claude models as supporting adaptive thinking', () => {
      expect(modelSpec['claude-haiku-4-5-20251001'].supports_adaptive_thinking).toBeUndefined();
    });
  });
  
  describe('Cohere Models', () => {
    it('should have correct parameters for Cohere models', () => {
      const model = modelSpec['command-a-vision-07-2025'];

      // Check essential parameters
      expect(model.context_window).toEqual([1, 128000]);
      expect(model.max_output_tokens).toEqual([1, 8000]);
      expect(model.temperature).toEqual([[0.0, 1.0], 0.3]);
      expect(model.top_p).toEqual([[0.01, 0.99], 0.75]);
    });

    it('should have different tool capabilities for different Cohere models', () => {
      // Newer model with tool support
      expect(modelSpec['command-a-vision-07-2025'].tool_capability).toBe(true);
      expect(modelSpec['command-a-reasoning-08-2025'].tool_capability).toBe(true);
    });
  });
  
  describe('Parameter Validation', () => {
    it('should have valid temperature ranges for all models', () => {
      // Check a sample of models to ensure temperature ranges are valid
      Object.keys(modelSpec).forEach(modelName => {
        const model = modelSpec[modelName];
        if (model.temperature) {
          if (Array.isArray(model.temperature[0])) {
            // Format is [[min, max], default]
            expect(model.temperature[0][0]).toBeLessThanOrEqual(model.temperature[0][1]);
            expect(model.temperature[1]).toBeGreaterThanOrEqual(model.temperature[0][0]);
            expect(model.temperature[1]).toBeLessThanOrEqual(model.temperature[0][1]);
          }
        }
      });
    });
    
    it('should have valid context window values', () => {
      // Check a sample of models to ensure context window values are valid
      Object.keys(modelSpec).forEach(modelName => {
        const model = modelSpec[modelName];
        if (model.context_window) {
          // Check if context_window is an array with at least 2 elements
          if (Array.isArray(model.context_window) && model.context_window.length >= 2) {
            expect(model.context_window[0]).toBeLessThanOrEqual(model.context_window[1]);
            expect(model.context_window[0]).toBeGreaterThan(0);
          }
        }
      });
    });
  });
  
  describe('Model Properties', () => {
    it('should have consistent property structure', () => {
      // Define common properties that most models should have
      const commonProperties = [
        'context_window',
        'max_output_tokens'
      ];
      
      // Check that at least a majority of models have these properties
      let propertyCount = {};
      commonProperties.forEach(prop => propertyCount[prop] = 0);
      
      Object.keys(modelSpec).forEach(modelName => {
        const model = modelSpec[modelName];
        commonProperties.forEach(prop => {
          if (model[prop]) propertyCount[prop]++;
        });
      });
      
      // Most models should have these properties
      const modelCount = Object.keys(modelSpec).length;
      commonProperties.forEach(prop => {
        expect(propertyCount[prop]).toBeGreaterThan(modelCount * 0.5);
      });
    });
    
    it('should have boolean value for capability properties', () => {
      // Check capability properties are boolean
      const capabilityProps = ['vision_capability', 'tool_capability'];
      
      Object.keys(modelSpec).forEach(modelName => {
        const model = modelSpec[modelName];
        capabilityProps.forEach(prop => {
          if (model[prop] !== undefined) {
            expect(typeof model[prop]).toBe('boolean');
          }
        });
      });
    });
  });
});
