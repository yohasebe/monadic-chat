// Model utility functions for handling provider-specific model lists

/**
 * Get all available models for a given app, considering provider-specific behavior
 * @param {Object} appConfig - The app configuration object
 * @returns {Array} Array of model names
 */
function getModelsForApp(appConfig) {
  if (!appConfig) return [];
  
  const isOpenAI = appConfig["group"] && appConfig["group"].toLowerCase() === "openai";
  
  if (isOpenAI) {
    // For OpenAI apps, get all OpenAI models from modelSpec
    const allOpenAIModels = Object.keys(window.modelSpec || {}).filter(model => {
      // OpenAI models include: gpt-*, o1*, o3*, chatgpt-*
      return model.startsWith('gpt-') || 
             model.startsWith('o1') || 
             model.startsWith('o3') || 
             model.startsWith('chatgpt-');
    });
    
    // If MDSL specifies models, merge them with all OpenAI models
    if (appConfig["models"] && appConfig["models"].length > 0) {
      let mdslModels = JSON.parse(appConfig["models"]);
      // Merge MDSL models with all OpenAI models, removing duplicates
      return [...new Set([...mdslModels, ...allOpenAIModels])];
    } else if (appConfig["model"]) {
      // If only a single model is specified, still show all OpenAI models
      return allOpenAIModels;
    } else {
      // No model specified, show all OpenAI models
      return allOpenAIModels;
    }
  } else {
    // For non-OpenAI providers, use MDSL-specified models only
    if (appConfig["models"] && appConfig["models"].length > 0) {
      return JSON.parse(appConfig["models"]);
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
  
  const isOpenAI = appConfig["group"] && appConfig["group"].toLowerCase() === "openai";
  const isOllama = appConfig["group"] && appConfig["group"].toLowerCase() === "ollama";
  
  if (isOllama && !appConfig["model"]) {
    return availableModels[0]; // Select first available model for Ollama
  } else if (isOpenAI) {
    // For OpenAI, prefer the first MDSL model if available
    if (appConfig["models"] && appConfig["models"].length > 0) {
      let mdslModels = JSON.parse(appConfig["models"]);
      return mdslModels[0]; // Use first MDSL model as default
    } else if (appConfig["model"]) {
      return appConfig["model"]; // Use single specified model
    } else {
      return availableModels[0]; // Fallback to first available
    }
  } else {
    // For other providers
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