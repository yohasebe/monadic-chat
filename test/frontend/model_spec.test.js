/**
 * @jest-environment jsdom
 */

const fs = require('fs');
const path = require('path');

describe('Model Specification', () => {
  // We'll extract the modelSpec object by evaluating the source file
  let modelSpec;
  
  beforeEach(() => {
    // Read the file content
    const filePath = path.join(__dirname, '../../docker/services/ruby/public/js/monadic/model_spec.js');
    const fileContent = fs.readFileSync(filePath, 'utf8');
    
    // Execute the file content in a controlled way to extract modelSpec
    try {
      // Create a function that will evaluate the file in a scope where we can capture modelSpec
      const createModelSpec = new Function(`
        ${fileContent}
        return modelSpec;
      `);
      
      // Execute the function to get modelSpec
      modelSpec = createModelSpec();
    } catch (e) {
      console.error('Error loading model_spec.js:', e);
      throw e;
    }
  });
  
  it('should be defined as an object', () => {
    expect(modelSpec).toBeDefined();
    expect(typeof modelSpec).toBe('object');
  });
  
  it('should contain major AI models', () => {
    // Test for some key model categories
    expect(modelSpec['gpt-4.1']).toBeDefined();
    expect(modelSpec['claude-sonnet-4-20250514']).toBeDefined();
    expect(modelSpec['gemini-2.5-flash-preview-05-20']).toBeDefined();
    expect(modelSpec['command-r-plus-08-2024']).toBeDefined();
    expect(modelSpec['grok-2']).toBeDefined();
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
  });
  
  describe('Anthropic Models', () => {
    it('should have correct parameters for Claude models', () => {
      const model = modelSpec['claude-sonnet-4-20250514'];
      
      // Check essential parameters
      expect(model.context_window).toEqual([1, 200000]);
      expect(model.max_output_tokens).toEqual([[1, 64000], 64000]);
      expect(model.reasoning_effort).toEqual([["none", "low", "medium", "high"], "low"]);
      expect(model.tool_capability).toBe(true);
      expect(model.vision_capability).toBe(true);
    });
    
    it('should have different vision capabilities for different Claude models', () => {
      // Claude Sonnet should have vision
      expect(modelSpec['claude-3-5-sonnet-20241022'].vision_capability).toBe(true);
      
      // Claude Haiku shouldn't have vision (at least one version)
      expect(modelSpec['claude-3-5-haiku-20241022'].vision_capability).toBe(false);
    });
  });
  
  describe('Cohere Models', () => {
    it('should have correct parameters for Cohere models', () => {
      const model = modelSpec['command-r-plus-08-2024'];
      
      // Check essential parameters
      expect(model.context_window).toEqual([1, 128000]);
      expect(model.max_output_tokens).toEqual([1, 4000]);
      expect(model.temperature).toEqual([[0.0, 1.0], 0.3]);
      expect(model.top_p).toEqual([[0.01, 0.09], 0.75]);
    });
    
    it('should have different tool capabilities for different Cohere models', () => {
      // Newer model with tool support
      expect(modelSpec['command-r-plus-08-2024'].tool_capability).toBe(true);
      
      // Check another Cohere model
      if (modelSpec['command']) {
        expect(modelSpec['command'].tool_capability).toBe(true);
      }
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
