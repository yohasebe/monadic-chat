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
 * Extract date suffix from model name and parse it
 * @param {String} modelName - The model name
 * @returns {Object|null} Object with {dateString, parsedDate, format} or null if no date
 */
function extractDateSuffix(modelName) {
  if (!modelName || typeof modelName !== 'string') return null;

  // YYYY-MM-DD format (OpenAI, xAI)
  const yyyymmddDash = modelName.match(/-(\d{4})-(\d{2})-(\d{2})$/);
  if (yyyymmddDash) {
    const [_, year, month, day] = yyyymmddDash;
    return {
      dateString: `${year}-${month}-${day}`,
      parsedDate: new Date(parseInt(year), parseInt(month) - 1, parseInt(day)),
      format: 'YYYY-MM-DD'
    };
  }

  // YYYYMMDD format (Claude)
  const yyyymmdd = modelName.match(/-(\d{8})$/);
  if (yyyymmdd) {
    const dateStr = yyyymmdd[1];
    const year = parseInt(dateStr.substring(0, 4));
    const month = parseInt(dateStr.substring(4, 6));
    const day = parseInt(dateStr.substring(6, 8));
    // Validate it's a real date
    if (year >= 2020 && year <= 2030 && month >= 1 && month <= 12 && day >= 1 && day <= 31) {
      return {
        dateString: dateStr,
        parsedDate: new Date(year, month - 1, day),
        format: 'YYYYMMDD'
      };
    }
  }

  // MM-YYYY format (Cohere)
  const mmyyyy = modelName.match(/-(\d{2})-(\d{4})$/);
  if (mmyyyy) {
    const [_, month, year] = mmyyyy;
    const m = parseInt(month);
    const y = parseInt(year);
    if (y >= 2020 && y <= 2030 && m >= 1 && m <= 12) {
      return {
        dateString: `${month}-${year}`,
        parsedDate: new Date(y, m - 1, 1),
        format: 'MM-YYYY'
      };
    }
  }

  // MM-DD format (Gemini) - requires context to distinguish from YYYY suffix
  const mmdd = modelName.match(/-(\d{2})-(\d{2})$/);
  if (mmdd) {
    const [_, first, second] = mmdd;
    const f = parseInt(first);
    const s = parseInt(second);
    // Heuristic: if first number is 01-12 and second is 01-31, likely MM-DD
    if (f >= 1 && f <= 12 && s >= 1 && s <= 31) {
      // Assume current year
      const currentYear = new Date().getFullYear();
      return {
        dateString: `${first}-${second}`,
        parsedDate: new Date(currentYear, f - 1, s),
        format: 'MM-DD'
      };
    }
  }

  // -NNN format (Gemini version numbers like -001, -002)
  const nnn = modelName.match(/-(\d{3})$/);
  if (nnn) {
    const num = parseInt(nnn[1]);
    // This is a version number, not a date, but we treat it as sortable
    return {
      dateString: nnn[1],
      parsedDate: new Date(2020, 0, num), // Pseudo-date for sorting
      format: 'NNN'
    };
  }

  // -exp-MMDD format (Gemini experimental)
  const expMmdd = modelName.match(/-exp-(\d{2})(\d{2})$/);
  if (expMmdd) {
    const [_, month, day] = expMmdd;
    const m = parseInt(month);
    const d = parseInt(day);
    if (m >= 1 && m <= 12 && d >= 1 && d <= 31) {
      const currentYear = new Date().getFullYear();
      return {
        dateString: `exp-${month}${day}`,
        parsedDate: new Date(currentYear, m - 1, d),
        format: 'exp-MMDD'
      };
    }
  }

  return null;
}

/**
 * Get base model name by removing date suffixes
 * @param {String} modelName - The model name to normalize
 * @returns {String} Base model name without date suffix
 */
function getBaseModelName(modelName) {
  if (!modelName || typeof modelName !== 'string') return modelName;

  const dateInfo = extractDateSuffix(modelName);
  if (!dateInfo) return modelName;

  // Remove the date suffix based on format
  switch (dateInfo.format) {
    case 'YYYY-MM-DD':
      return modelName.replace(/-\d{4}-\d{2}-\d{2}$/, '');
    case 'YYYYMMDD':
      return modelName.replace(/-\d{8}$/, '');
    case 'MM-YYYY':
      return modelName.replace(/-\d{2}-\d{4}$/, '');
    case 'MM-DD':
      return modelName.replace(/-\d{2}-\d{2}$/, '');
    case 'NNN':
      return modelName.replace(/-\d{3}$/, '');
    case 'exp-MMDD':
      return modelName.replace(/-exp-\d{4}$/, '');
    default:
      return modelName;
  }
}

/**
 * Get the latest dated model from an array of dated models
 * @param {Array} datedModels - Array of model names with date suffixes
 * @returns {String} The model with the latest date
 */
function getLatestDatedModel(datedModels) {
  if (!datedModels || datedModels.length === 0) return null;
  if (datedModels.length === 1) return datedModels[0];

  // Extract dates and sort
  const modelsWithDates = datedModels.map(model => {
    const dateInfo = extractDateSuffix(model);
    return {
      model,
      dateInfo,
      // If no date found, use epoch (will be sorted last)
      sortDate: dateInfo ? dateInfo.parsedDate : new Date(0)
    };
  });

  // Sort by date (newest first)
  modelsWithDates.sort((a, b) => b.sortDate - a.sortDate);

  return modelsWithDates[0].model;
}

/**
 * Filter models to show only latest versions
 * Keeps: dateless version AND latest dated version for each base model
 * @param {Array} models - Array of model names
 * @returns {Array} Filtered array of model names
 */
function filterToLatestVersions(models) {
  if (!models || !Array.isArray(models)) return [];

  const modelSpec = window.modelSpec || {};
  const groupedModels = {};

  // Group models by base name
  models.forEach(model => {
    const baseName = getBaseModelName(model);
    if (!groupedModels[baseName]) {
      groupedModels[baseName] = [];
    }
    groupedModels[baseName].push(model);
  });

  // For each group, decide which versions to keep
  const result = [];
  Object.keys(groupedModels).forEach(baseName => {
    const versions = groupedModels[baseName];

    if (versions.length === 1) {
      // Only one version, keep it
      result.push(versions[0]);
      return;
    }

    // Separate dated and dateless versions
    const dateless = versions.filter(v => v === baseName);
    const dated = versions.filter(v => v !== baseName);

    if (dateless.length === 0) {
      // No dateless version, keep latest dated
      const latest = getLatestDatedModel(dated);
      result.push(latest);
    } else if (dated.length === 0) {
      // No dated versions, keep dateless
      result.push(dateless[0]);
    } else {
      // Both exist - keep both dateless and latest dated version
      const latest = getLatestDatedModel(dated);
      result.push(dateless[0]);
      result.push(latest);
    }
  });

  return result;
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

    // Filter to latest versions only
    const filteredModels = filterToLatestVersions(allProviderModels);

    // If MDSL specifies models, merge them with filtered provider models
    if (appConfig["models"] && appConfig["models"].length > 0) {
      let mdslModels = JSON.parse(appConfig["models"]);
      // Merge MDSL models with filtered provider models, removing duplicates
      return [...new Set([...mdslModels, ...filteredModels])];
    } else if (appConfig["model"]) {
      // If only a single model is specified, still show all filtered provider models
      return filteredModels;
    } else {
      // No model specified, show filtered provider models
      return filteredModels;
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