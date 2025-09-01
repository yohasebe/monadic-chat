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
        return spec.supports_thinking === true && spec.thinking_budget !== undefined;
      case 'Google':
        return spec.thinking_budget !== undefined;
      case 'xAI':
        return spec.hasOwnProperty('reasoning_effort');
      case 'DeepSeek':
        return spec.hasOwnProperty('reasoning_content');
      case 'Perplexity':
        return spec.hasOwnProperty('reasoning_effort');
      default:
        return false;
    }
  }
  
  /**
   * Gets available options for UI dropdown for given provider/model
   * @param {string} provider - Provider name
   * @param {string} model - Model name
   * @returns {Array} Array of available options or null
   */
  static getAvailableOptions(provider, model) {
    try {
      const spec = window.modelSpec ? window.modelSpec[model] : null;
      if (!spec) {
        console.warn(`ReasoningMapper: Model spec not found for '${model}'`);
        return null;
      }
      
      switch (provider) {
        case 'OpenAI':
          if (spec.reasoning_effort && Array.isArray(spec.reasoning_effort[0])) {
            return spec.reasoning_effort[0]; // ["minimal", "low", "medium", "high"]
          }
          return null;
          
        case 'Anthropic':
          if (spec.supports_thinking === true && spec.thinking_budget) {
            return ['minimal', 'low', 'medium', 'high']; // UI options mapped to budget values
          }
          return null;
          
        case 'Google':
          if (spec.thinking_budget) {
            return spec.thinking_budget.can_disable 
              ? ['minimal', 'low', 'medium', 'high']
              : ['low', 'medium', 'high']; // No minimal if can't disable
          }
          return null;
          
        case 'xAI':
          if (spec.reasoning_effort && Array.isArray(spec.reasoning_effort[0])) {
            return spec.reasoning_effort[0]; // ["low", "medium", "high"] - no minimal
          }
          return null;
          
        case 'DeepSeek':
          if (spec.reasoning_content) {
            return ['minimal', 'medium']; // Only these two options
          }
          return null;
          
        case 'Perplexity':
          if (spec.reasoning_effort && Array.isArray(spec.reasoning_effort[0])) {
            return spec.reasoning_effort[0]; // ["minimal", "low", "medium", "high"]
          }
          return null;
          
        default:
          console.warn(`ReasoningMapper: Unknown provider '${provider}'`);
          return null;
      }
    } catch (error) {
      console.error('ReasoningMapper: Error getting available options:', error);
      return null;
    }
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
    if (!spec.thinking_budget) return null;
    
    // Check if minimal is supported (can_disable = true)
    if (uiValue === 'minimal' && !spec.thinking_budget.can_disable) {
      return null; // Not supported
    }
    
    return { reasoning_effort: uiValue }; // Gemini helper handles the mapping
  }
  
  static _mapGrok(spec, uiValue) {
    if (spec.reasoning_effort && Array.isArray(spec.reasoning_effort[0])) {
      // Grok doesn't support minimal, map it to low
      const mappedValue = uiValue === 'minimal' ? 'low' : uiValue;
      
      if (spec.reasoning_effort[0].includes(mappedValue)) {
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
        
      default:
        return 'medium';
    }
  }
}

// Make available globally
window.ReasoningMapper = ReasoningMapper;