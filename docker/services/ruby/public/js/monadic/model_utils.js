// Model utility functions for handling provider-specific model lists

/**
 * Provider-specific configuration for model selection behavior
 * This allows customization without hardcoding in helper files
 */
const PROVIDER_MODEL_BEHAVIOR = {
  openai: {
    showAllModels: true,  // Show all available models from modelSpec
    modelPattern: /^(gpt-|o[13]|chatgpt-)/  // Pattern to identify provider's models
  },
  anthropic: {
    showAllModels: true,  // Show all available Claude models
    modelPattern: /^claude-/  // Pattern to identify Claude models
  },
  claude: {
    showAllModels: true,  // Alias for anthropic
    modelPattern: /^claude-/  // Pattern to identify Claude models
  },
  gemini: {
    showAllModels: true,  // Show all available Gemini models
    modelPattern: /^(gemini-|gemma-)/  // Pattern to identify Gemini/Gemma models
  },
  google: {
    showAllModels: true,  // Alias for gemini
    modelPattern: /^(gemini-|gemma-)/  // Pattern to identify Gemini/Gemma models
  },
  cohere: {
    showAllModels: true,  // Show all available Cohere models
    modelPattern: /^command-/  // Pattern to identify Cohere models
  },
  mistral: {
    showAllModels: true,  // Show all available Mistral models
    modelPattern: /^(mistral-|pixtral-|magistral-|ministral-)/  // Pattern to identify Mistral models
  },
  perplexity: {
    showAllModels: true,  // Show all available Perplexity models
    modelPattern: /^(sonar|llama-)/  // Pattern to identify Perplexity models
  },
  deepseek: {
    showAllModels: true,  // Show all available DeepSeek models
    modelPattern: /^deepseek-/  // Pattern to identify DeepSeek models
  },
  xai: {
    showAllModels: true,  // Show all available xAI models
    modelPattern: /^grok-/  // Pattern to identify xAI models
  },
  grok: {
    showAllModels: true,  // Alias for xai
    modelPattern: /^grok-/  // Pattern to identify xAI models
  },
  ollama: {
    showAllModels: false,
    selectFirstModel: true  // Special behavior for Ollama
  }
};

/**
 * Get provider key from app group
 * @param {String} group - The app group string
 * @returns {String} The provider key for configuration lookup
 */
function getProviderKey(group) {
  if (!group) return 'default';
  
  const groupLower = group.toLowerCase();
  
  // Map various group names to provider keys
  if (groupLower === 'openai') return 'openai';
  if (groupLower.includes('anthropic') || groupLower.includes('claude')) return 'anthropic';
  if (groupLower.includes('gemini') || groupLower.includes('google')) return 'gemini';
  if (groupLower.includes('cohere')) return 'cohere';
  if (groupLower.includes('mistral')) return 'mistral';
  if (groupLower.includes('perplexity')) return 'perplexity';
  if (groupLower.includes('deepseek')) return 'deepseek';
  if (groupLower.includes('grok') || groupLower.includes('xai')) return 'xai';
  if (groupLower.includes('ollama')) return 'ollama';
  
  return 'default';
}

/**
 * Get all available models for a given app, considering provider-specific behavior
 * @param {Object} appConfig - The app configuration object
 * @returns {Array} Array of model names
 */
function getModelsForApp(appConfig) {
  if (!appConfig) return [];
  
  const providerKey = getProviderKey(appConfig["group"]);
  const providerConfig = PROVIDER_MODEL_BEHAVIOR[providerKey] || { showAllModels: false };
  
  if (providerConfig.showAllModels) {
    // Get all models from modelSpec that match the provider's pattern
    const allProviderModels = Object.keys(window.modelSpec || {}).filter(model => {
      return providerConfig.modelPattern && providerConfig.modelPattern.test(model);
    });
    
    // If MDSL specifies models, merge them with all provider models
    if (appConfig["models"] && appConfig["models"].length > 0) {
      let mdslModels = JSON.parse(appConfig["models"]);
      // Merge MDSL models with all provider models, removing duplicates
      return [...new Set([...mdslModels, ...allProviderModels])];
    } else if (appConfig["model"]) {
      // If only a single model is specified, still show all provider models
      return allProviderModels;
    } else {
      // No model specified, show all provider models
      return allProviderModels;
    }
  } else {
    // For providers that don't show all models, use MDSL-specified models only
    if (appConfig["models"] && typeof appConfig["models"] === "string") {
      // models is a JSON string from server
      try {
        const parsedModels = JSON.parse(appConfig["models"]);
        return parsedModels;
      } catch (e) {
        console.error(`Failed to parse models JSON:`, e);
        return [];
      }
    } else if (appConfig["model"]) {
      return [appConfig["model"]];
    } else {
      return [];
    }
  }
}

/**
 * Get the default model for a given app
 * @param {Object} appConfig - The app configuration object
 * @param {Array} availableModels - Array of available models
 * @returns {String} The default model name
 */
function getDefaultModelForApp(appConfig, availableModels) {
  if (!appConfig || !availableModels || availableModels.length === 0) return null;
  
  const providerKey = getProviderKey(appConfig["group"]);
  const providerConfig = PROVIDER_MODEL_BEHAVIOR[providerKey] || {};
  
  // Check for Ollama's special behavior
  if (providerConfig.selectFirstModel && !appConfig["model"]) {
    return availableModels[0]; // Select first available model for Ollama
  }
  
  // Check if provider shows all models (like OpenAI)
  if (providerConfig.showAllModels) {
    // Prefer the first MDSL model if available
    if (appConfig["models"] && appConfig["models"].length > 0) {
      let mdslModels = JSON.parse(appConfig["models"]);
      return mdslModels[0]; // Use first MDSL model as default
    } else if (appConfig["model"]) {
      return appConfig["model"]; // Use single specified model
    } else {
      return availableModels[0]; // Fallback to first available
    }
  } else {
    // For providers that show only MDSL models
    if (appConfig["models"] && appConfig["models"].length > 0) {
      let mdslModels = JSON.parse(appConfig["models"]);
      return mdslModels[0];
    } else if (appConfig["model"]) {
      return appConfig["model"];
    } else {
      return availableModels[1] || availableModels[0]; // Skip disabled option if present
    }
  }
}

// Export for use in other modules
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { getModelsForApp, getDefaultModelForApp };
}