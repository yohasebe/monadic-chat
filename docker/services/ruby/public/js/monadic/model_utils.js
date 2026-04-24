// Model utility functions for handling provider-specific model lists

/**
 * Provider-specific configuration for model selection behavior
 * This allows customization without hardcoding in helper files
 */
// Provider-specific model selection behavior.
// showAllModels defaults to true (omitted = true); only set false for exceptions.
const PROVIDER_MODEL_BEHAVIOR = {
  openai:     { modelPattern: /^(gpt-|o[13]|chatgpt-)/ },
  anthropic:  { modelPattern: /^claude-/ },
  claude:     { modelPattern: /^claude-/ },                          // alias for anthropic
  gemini:     { modelPattern: /^(gemini-|gemma-)/ },
  google:     { modelPattern: /^(gemini-|gemma-)/ },                 // alias for gemini
  cohere:     { modelPattern: /^command-/ },
  mistral:    { modelPattern: /^(mistral-|pixtral-|magistral-|ministral-)/ },
  perplexity: { modelPattern: /^(sonar|llama-)/ },
  deepseek:   { modelPattern: /^deepseek-/ },
  xai:        { modelPattern: /^grok-/ },
  grok:       { modelPattern: /^grok-/ },                            // alias for xai
  ollama:     { showAllModels: false, selectFirstModel: true }
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

  // YYMM format (Mistral) - 2509 means 2025-09
  const yymm = modelName.match(/-(\d{4})$/);
  if (yymm) {
    const dateStr = yymm[1];
    const yy = parseInt(dateStr.substring(0, 2));
    const mm = parseInt(dateStr.substring(2, 4));
    // Validate: year 20-30 (2020-2030), month 01-12
    if (yy >= 20 && yy <= 30 && mm >= 1 && mm <= 12) {
      const year = 2000 + yy;
      return {
        dateString: dateStr,
        parsedDate: new Date(year, mm - 1, 1),
        format: 'YYMM'
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
    case 'YYMM':
      return modelName.replace(/-\d{4}$/, '');
    case 'NNN':
      return modelName.replace(/-\d{3}$/, '');
    case 'exp-MMDD':
      return modelName.replace(/-exp-\d{4}$/, '');
    default:
      return modelName;
  }
}

/**
 * Get model spec with fallback to base model name
 * This allows dated models (e.g., gpt-5.2-pro-2025-12-11) to inherit
 * properties from their base model (e.g., gpt-5.2-pro) when not explicitly defined.
 * @param {String} modelName - The model name to look up
 * @param {String} property - Optional: specific property to get (if not specified, returns full spec)
 * @returns {Object|*} The model spec or the specific property value
 */
function getModelSpecWithFallback(modelName, property) {
  const modelSpec = window.modelSpec || {};

  // Try exact match first
  let spec = modelSpec[modelName];

  // If not found or property not in spec, try base model
  if (!spec || (property && !spec.hasOwnProperty(property))) {
    const baseName = getBaseModelName(modelName);
    if (baseName !== modelName && modelSpec[baseName]) {
      spec = modelSpec[baseName];
    }
  }

  if (!spec) return property ? undefined : null;

  return property ? spec[property] : spec;
}

/**
 * Check if a model requires confirmation before use (expensive models)
 * Falls back to base model if dated version is not found
 * @param {String} modelName - The model name to check
 * @returns {Boolean} True if the model requires confirmation
 */
function modelRequiresConfirmation(modelName) {
  return getModelSpecWithFallback(modelName, 'requires_confirmation') === true;
}

/**
 * Check if a model is deprecated and should be hidden from UI
 * Falls back to base model if dated version is not found
 * @param {String} modelName - The model name to check
 * @returns {Boolean} True if the model is deprecated
 */
function isModelDeprecated(modelName) {
  return getModelSpecWithFallback(modelName, 'deprecated') === true;
}

/**
 * Get the successor model for a deprecated model
 * Falls back to base model if dated version is not found
 * @param {String} modelName - The deprecated model name
 * @returns {String|null} Successor model name, or null if not deprecated or no successor
 */
function getModelSuccessor(modelName) {
  if (!isModelDeprecated(modelName)) return null;
  return getModelSpecWithFallback(modelName, 'successor') || null;
}

/**
 * Check if a model should be hidden from the user-facing UI dropdown.
 * Models with ui_hidden are valid for backend/agent use but not appropriate
 * for direct user selection (e.g., agent-optimized variants like customtools).
 * Falls back to base model if dated version is not found.
 * @param {String} modelName - The model name to check
 * @returns {Boolean} True if the model should be hidden from UI
 */
function isModelUiHidden(modelName) {
  return getModelSpecWithFallback(modelName, 'ui_hidden') === true;
}

// Export to window for global access
window.getModelSpecWithFallback = getModelSpecWithFallback;
window.modelRequiresConfirmation = modelRequiresConfirmation;
window.isModelDeprecated = isModelDeprecated;
window.getModelSuccessor = getModelSuccessor;
window.isModelUiHidden = isModelUiHidden;

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
 * Filter models for "All Models" mode.
 *
 * Policy (documented in docs_dev/developer/model_spec_vocabulary.md):
 *  1. requires_confirmation: true  → always excluded (expensive / special models)
 *  2. tool_capability: false       → excluded, EXCEPT for Perplexity whose models
 *     have no tool support at all (excluding them would leave an empty list)
 *  3. Non-chat modality (TTS / embedding) → excluded from chat dropdowns
 *
 * @param {Array}  models      - Array of model name strings
 * @param {String} providerKey - Normalized provider key (e.g. "openai", "perplexity")
 * @returns {Array} Filtered model names
 */
function filterModelsForAllMode(models, providerKey) {
  if (!models || models.length === 0) return models;
  const spec = window.modelSpec || {};
  const skipToolFilter = (providerKey === 'perplexity');

  return models.filter(model => {
    const ms = spec[model];
    if (!ms) return true; // Unknown model — keep (may be user-added or API-only)

    // Exclude models requiring confirmation (expensive / special)
    if (ms.requires_confirmation === true) return false;

    // Exclude non-chat modalities (TTS / embedding)
    if (ms.tts_capability === true) return false;
    if (ms.embedding_dimensions != null) return false;

    // Exclude models without tool capability (Perplexity exempted)
    if (!skipToolFilter && ms.tool_capability === false) return false;

    return true;
  });
}

/**
 * Get all available models for a given app, considering provider-specific behavior.
 *
 * When showAll is false (default), returns the curated list:
 *   MDSL models → providerDefaults → single appConfig["model"]
 * When showAll is true, returns all provider models (with policy filters applied).
 *
 * @param {Object}  appConfig - The app configuration object
 * @param {Boolean} showAll   - When true, show all provider models (default: false)
 * @returns {Array} Array of model names
 */
function getModelsForApp(appConfig, showAll) {
  if (!appConfig) return [];
  if (showAll === undefined) showAll = false;

  const providerKey = getProviderKey(appConfig["group"]);
  const providerConfig = PROVIDER_MODEL_BEHAVIOR[providerKey] || {};
  const canShowAll = providerConfig.showAllModels !== false;

  if (canShowAll && showAll) {
    // === All-models mode (with policy filters) ===
    const allProviderModels = Object.keys(window.modelSpec || {}).filter(model => {
      return providerConfig.modelPattern && providerConfig.modelPattern.test(model)
        && !isModelDeprecated(model)
        && !isModelUiHidden(model);
    });
    const filteredModels = filterToLatestVersions(allProviderModels);
    const policyFiltered = filterModelsForAllMode(filteredModels, providerKey);

    // Prepend MDSL models so they appear first
    if (appConfig["models"] && appConfig["models"].length > 0) {
      try {
        const mdslModels = JSON.parse(appConfig["models"]).filter(m => !isModelDeprecated(m));
        return [...new Set([...mdslModels, ...policyFiltered])];
      } catch (e) { console.warn('[model_utils] Failed to parse MDSL models:', e); }
    }
    return policyFiltered;

  } else if (canShowAll && !showAll) {
    // === Curated mode: MDSL → providerDefaults → single model ===
    if (appConfig["models"] && appConfig["models"].length > 0) {
      try {
        const parsed = JSON.parse(appConfig["models"]).filter(m => !isModelDeprecated(m));
        if (parsed.length > 0) return parsed;
      } catch (e) { console.warn('[model_utils] Failed to parse MDSL models:', e); }
    }
    // providerDefaults fallback
    const defaults = window.providerDefaults || {};
    const pdModels = defaults[providerKey] && defaults[providerKey].chat;
    if (pdModels && pdModels.length > 0) {
      return pdModels.filter(m => !isModelDeprecated(m));
    }
    // Single model fallback
    if (appConfig["model"] && !isModelDeprecated(appConfig["model"])) {
      return [appConfig["model"]];
    }
    return [];

  } else {
    // === Ollama etc.: existing logic unchanged ===
    if (appConfig["models"] && typeof appConfig["models"] === "string") {
      try {
        const parsedModels = JSON.parse(appConfig["models"]).filter(m => !isModelDeprecated(m));
        if (parsedModels.length > 0) {
          return parsedModels;
        }
      } catch (e) {
        console.error(`Failed to parse models JSON:`, e);
      }
    }
    if (appConfig["model"] && !isModelDeprecated(appConfig["model"])) {
      return [appConfig["model"]];
    }
    return [];
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
  
  // Check for Ollama's special behavior: prefer first available model
  // when configured model is absent or not installed
  if (providerConfig.selectFirstModel) {
    if (!appConfig["model"] || !availableModels.includes(appConfig["model"])) {
      return availableModels[0];
    }
    return appConfig["model"];
  }
  
  // Check if provider supports "show all models" toggle
  if (providerConfig.showAllModels !== false) {
    // IMPORTANT: Check single model first - this is the MDSL-specified default
    // appConfig["models"] may contain all provider models from API, not just MDSL models
    if (appConfig["model"] && !isModelDeprecated(appConfig["model"])) {
      return appConfig["model"]; // Use MDSL-specified model as default
    } else if (appConfig["models"] && appConfig["models"].length > 0) {
      let mdslModels = JSON.parse(appConfig["models"]).filter(m => !isModelDeprecated(m));
      if (mdslModels.length > 0) return mdslModels[0];
    }
    return availableModels[0]; // Fallback to first available
  } else {
    // For providers that show only MDSL models
    // Check single model first for consistency
    if (appConfig["model"] && !isModelDeprecated(appConfig["model"])) {
      return appConfig["model"];
    } else if (appConfig["models"] && appConfig["models"].length > 0) {
      try {
        let mdslModels = JSON.parse(appConfig["models"]).filter(m => !isModelDeprecated(m));
        if (mdslModels.length > 0) return mdslModels[0];
      } catch (e) { console.warn('[model_utils] Failed to parse models in getDefaultModelForApp:', e); }
    }
    return availableModels[1] || availableModels[0]; // Skip disabled option if present
  }
}

// Export for use in other modules
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { getModelsForApp, getDefaultModelForApp, isModelDeprecated, getModelSuccessor, isModelUiHidden, filterModelsForAllMode };
}