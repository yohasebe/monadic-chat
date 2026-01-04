/**
 * Unified Reasoning/Thinking Parameter Mapper
 * Maps UI reasoning_effort values to provider-specific parameter formats
 */

class ReasoningMapper {
  
  /**
   * Maps UI reasoning_effort value to provider-specific parameter
   * @param {string} provider - Provider name (from getProviderFromGroup)
   * @param {string} model - Model name
   * @param {string} uiValue - UI selected value (minimal, low, medium, high)
   * @returns {Object} Mapped parameter object or null if not supported
   */
  static mapToProviderParameter(provider, model, uiValue) {
    try {
      const spec = window.modelSpec ? window.modelSpec[model] : null;
      if (!spec) {
        console.warn(`ReasoningMapper: Model spec not found for model '${model}'`);
        return null;
      }
      
      switch (provider) {
        case 'OpenAI':
          return this._mapOpenAI(spec, uiValue);
        case 'Anthropic':
          return this._mapClaude(spec, uiValue);
        case 'Google':
          return this._mapGemini(spec, uiValue);
        case 'xAI':
          return this._mapGrok(spec, uiValue);
        case 'DeepSeek':
          return this._mapDeepSeek(spec, uiValue);
        case 'Perplexity':
          return this._mapPerplexity(spec, uiValue);
        case 'Cohere':
          return this._mapCohere(spec, uiValue);
        default:
          console.warn(`ReasoningMapper: Unknown provider '${provider}'`);
          return null;
      }
    } catch (error) {
      console.error('ReasoningMapper: Error mapping parameter:', error);
      return null;
    }
  }
  
  /**
   * Checks if provider/model supports reasoning/thinking functionality
   * @param {string} provider - Provider name
   * @param {string} model - Model name
   * @returns {boolean} True if supported
   */
  static isSupported(provider, model) {
    const spec = window.modelSpec ? window.modelSpec[model] : null;
    if (!spec) {
      return false;
    }
    
    switch (provider) {
      case 'OpenAI':
        return spec.hasOwnProperty('reasoning_effort');
      case 'Anthropic':
        return spec.supports_thinking === true && (spec.thinking_budget !== undefined || spec.supports_thinking_level === true);
      case 'Google':
        return spec.hasOwnProperty('reasoning_effort') || spec.supports_thinking_level === true || spec.thinking_budget !== undefined;
      case 'xAI':
        return spec.hasOwnProperty('reasoning_effort');
      case 'DeepSeek':
        return spec.hasOwnProperty('reasoning_content');
      case 'Perplexity':
        return spec.hasOwnProperty('reasoning_effort');
      case 'Cohere':
        return spec.reasoning_model === true || spec.supports_thinking === true;
      default:
        return false;
    }
  }

  /**
   * Gets available options for UI dropdown for given provider/model
   * @param {string} provider - Provider name
   * @param {string} model - Model name
   * @param {Object} currentSettings - Current UI settings (e.g., {web_search: true})
   * @returns {Array} Array of available options or null
   */
  static getAvailableOptions(provider, model, currentSettings = {}) {
    try {
      const spec = window.modelSpec ? window.modelSpec[model] : null;
      if (!spec) {
        console.warn(`ReasoningMapper: Model spec not found for '${model}'`);
        return null;
      }

      let options = null;

      switch (provider) {
        case 'OpenAI':
          if (spec.reasoning_effort && Array.isArray(spec.reasoning_effort[0])) {
            options = spec.reasoning_effort[0]; // ["minimal", "low", "medium", "high"]
          }
          break;
          
        case 'Anthropic':
          if (spec.supports_thinking === true && (spec.thinking_budget || spec.supports_thinking_level)) {
            options = spec.reasoning_effort && Array.isArray(spec.reasoning_effort[0]) ? spec.reasoning_effort[0] : ['low', 'high'];
          }
          break;

        case 'Google':
          if (spec.supports_thinking_level || spec.reasoning_effort) {
            if (spec.reasoning_effort && Array.isArray(spec.reasoning_effort[0])) {
              options = spec.reasoning_effort[0];
            }
          } else if (spec.thinking_budget) {
            options = spec.thinking_budget.can_disable
              ? ['minimal', 'low', 'medium', 'high']
              : ['low', 'medium', 'high']; // No minimal if can't disable
          }
          break;

        case 'xAI':
          if (spec.reasoning_effort && Array.isArray(spec.reasoning_effort[0])) {
            options = spec.reasoning_effort[0];
          }
          break;

        case 'DeepSeek':
          if (spec.reasoning_content) {
            options = ['minimal', 'medium']; // Only these two options
          }
          break;

        case 'Perplexity':
          if (spec.reasoning_effort && Array.isArray(spec.reasoning_effort[0])) {
            options = spec.reasoning_effort[0]; // ["minimal", "low", "medium", "high"]
          }
          break;

        case 'Cohere':
          // Cohere reasoning models use ["disabled", "enabled"]
          if (spec.reasoning_effort && Array.isArray(spec.reasoning_effort[0])) {
            options = spec.reasoning_effort[0];
          }
          break;

        default:
          console.warn(`ReasoningMapper: Unknown provider '${provider}'`);
          return null;
      }

      // Apply feature constraints if they exist
      if (options && spec.feature_constraints && spec.feature_constraints.reasoning_effort) {
        options = this._applyFeatureConstraints(
          options,
          spec.feature_constraints.reasoning_effort,
          currentSettings
        );
      }

      return options;
    } catch (error) {
      console.error('ReasoningMapper: Error getting available options:', error);
      return null;
    }
  }

  /**
   * Apply feature constraints to filter incompatible options
   * @param {Array} options - Available options
   * @param {Object} constraints - Feature constraints from model_spec
   * @param {Object} currentSettings - Current UI settings
   * @returns {Array} Filtered options
   */
  static _applyFeatureConstraints(options, constraints, currentSettings) {
    if (!constraints.incompatible_with) return options;

    let filteredOptions = [...options];

    // Check each feature in incompatible_with
    for (const [feature, incompatibleValues] of Object.entries(constraints.incompatible_with)) {
      // If the feature is currently enabled
      if (currentSettings[feature] === true) {
        // Remove incompatible values from options
        filteredOptions = filteredOptions.filter(opt => !incompatibleValues.includes(opt));
      }
    }

    return filteredOptions;
  }
  
  // Provider-specific mapping functions
  
  static _mapOpenAI(spec, uiValue) {
    if (spec.reasoning_effort && Array.isArray(spec.reasoning_effort[0]) && 
        spec.reasoning_effort[0].includes(uiValue)) {
      return { reasoning_effort: uiValue };
    }
    return null;
  }
  
  static _mapClaude(spec, uiValue) {
    try {
      if (spec.supports_thinking !== true) {
        console.warn('ReasoningMapper: Claude model does not support thinking');
        return null;
      }
      
      if (!spec.thinking_budget) {
        console.warn('ReasoningMapper: Claude model missing thinking_budget specification');
        return null;
      }
      
      // Map UI values to thinking budget tokens
      const budgetMap = {
        'minimal': spec.thinking_budget.min || 1024,
        'low': 5000,
        'medium': spec.thinking_budget.default || 10000,
        'high': 25000
      };
      
      const budgetValue = budgetMap[uiValue];
      if (budgetValue !== undefined) {
        return { thinking_budget: budgetValue };
      }
      
      console.warn(`ReasoningMapper: Invalid UI value '${uiValue}' for Claude`);
      return null;
    } catch (error) {
      console.error('ReasoningMapper: Error in _mapClaude:', error);
      return null;
    }
  }
  
  static _mapGemini(spec, uiValue) {
    // Gemini 3: thinking level
    if (spec.supports_thinking_level) {
      if (spec.reasoning_effort && Array.isArray(spec.reasoning_effort[0]) && spec.reasoning_effort[0].includes(uiValue)) {
        return { thinking_level: uiValue };
      }
      return null;
    }

    // Gemini 2.5: thinking budget
    if (!spec.thinking_budget) return null;
    
    // Check if minimal is supported (can_disable = true)
    if (uiValue === 'minimal' && !spec.thinking_budget.can_disable) {
      return null; // Not supported
    }
    
    return { reasoning_effort: uiValue }; // Gemini helper handles the mapping for budget
  }
  
  static _mapGrok(spec, uiValue) {
    if (spec.reasoning_effort && Array.isArray(spec.reasoning_effort[0])) {
      const supported = spec.reasoning_effort[0];
      let mappedValue = uiValue;

      if (!supported.includes(mappedValue) && uiValue === 'minimal' && supported.includes('low')) {
        mappedValue = 'low';
      }

      if (supported.includes(mappedValue)) {
        return { reasoning_effort: mappedValue };
      }
    }
    return null;
  }
  
  static _mapDeepSeek(spec, uiValue) {
    if (!spec.reasoning_content) return null;
    
    // DeepSeek: medium -> "enabled", minimal -> "disabled"
    if (uiValue === 'medium' || uiValue === 'high') {
      return { reasoning_content: 'enabled' };
    } else if (uiValue === 'minimal' || uiValue === 'low') {
      return { reasoning_content: 'disabled' };
    }
    return null;
  }
  
  static _mapPerplexity(spec, uiValue) {
    if (spec.reasoning_effort && Array.isArray(spec.reasoning_effort[0]) &&
        spec.reasoning_effort[0].includes(uiValue)) {
      return { reasoning_effort: uiValue };
    }
    return null;
  }

  static _mapCohere(spec, uiValue) {
    // Cohere reasoning models use "disabled" and "enabled"
    if (spec.reasoning_effort && Array.isArray(spec.reasoning_effort[0]) &&
        spec.reasoning_effort[0].includes(uiValue)) {
      return { reasoning_effort: uiValue };
    }
    return null;
  }

  /**
   * Gets default value for provider/model
   * @param {string} provider - Provider name
   * @param {string} model - Model name
   * @returns {string} Default UI value or null
   */
  static getDefaultValue(provider, model) {
    const spec = window.modelSpec ? window.modelSpec[model] : null;
    if (!spec) return null;
    
    switch (provider) {
      case 'OpenAI':
        if (spec.reasoning_effort && Array.isArray(spec.reasoning_effort) && spec.reasoning_effort.length >= 2) {
          return spec.reasoning_effort[1]; // Default value
        }
        return 'medium';
        
      case 'Anthropic':
        return 'medium'; // Maps to default thinking_budget
        
      case 'Google':
        return spec.thinking_budget && spec.thinking_budget.can_disable ? 'low' : 'medium';
        
      case 'xAI':
        if (spec.reasoning_effort && Array.isArray(spec.reasoning_effort) && spec.reasoning_effort.length >= 2) {
          return spec.reasoning_effort[1]; // Default value
        }
        return 'low';
        
      case 'DeepSeek':
        return 'medium'; // Maps to "enabled"
        
      case 'Perplexity':
        if (spec.reasoning_effort && Array.isArray(spec.reasoning_effort) && spec.reasoning_effort.length >= 2) {
          return spec.reasoning_effort[1]; // Default value
        }
        return 'medium';

      case 'Cohere':
        // Cohere reasoning models default to "enabled"
        if (spec.reasoning_effort && Array.isArray(spec.reasoning_effort) && spec.reasoning_effort.length >= 2) {
          return spec.reasoning_effort[1]; // Default value from spec
        }
        return 'enabled';

      default:
        return 'medium';
    }
  }
}

// Make available globally
window.ReasoningMapper = ReasoningMapper;
