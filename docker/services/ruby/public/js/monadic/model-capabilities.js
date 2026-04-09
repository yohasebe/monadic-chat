/**
 * Model Capability Checks for Monadic Chat
 *
 * Read-only query functions for model and app capabilities:
 * - isPdfSupportedForModel: Check PDF upload support (SSOT-driven)
 * - isImageGenerationApp: Check if app supports image generation
 * - isMaskEditingEnabled: Check if app supports mask editing
 * - isFileInputsSupportedForModel: Check File Inputs API support
 * - isResponsesApiModel: Check if model uses Responses API
 *
 * Extracted from utilities.js for modularity.
 */
(function() {
'use strict';

/**
 * Check if a model supports PDF file uploads (SSOT-driven).
 * If `supports_pdf_upload` is explicitly set, use that.
 * Otherwise, fall back to `supports_pdf` (legacy behavior).
 * @param {string} selectedModel - Model ID
 * @returns {boolean}
 */
function isPdfSupportedForModel(selectedModel) {
  try {
    if (typeof modelSpec !== 'undefined' && modelSpec[selectedModel]) {
      var spec = modelSpec[selectedModel];
      if (spec.hasOwnProperty('supports_pdf_upload')) {
        return spec.supports_pdf_upload === true;
      }
      return !!spec["supports_pdf"];
    }
  } catch (e) {
    // fall through to conservative default
  }
  // Conservative fallback if spec not loaded: disable
  return false;
}

/**
 * Check if the current app supports image generation.
 * @param {string} [appName] - App name (defaults to current selection)
 * @returns {boolean}
 */
function isImageGenerationApp(appName) {
  if (!appName) {
    var appsEl = $id("apps");
    appName = appsEl ? appsEl.value : null;
  }
  var toBool = window.toBool || function(value) {
    if (typeof value === 'boolean') return value;
    if (typeof value === 'string') return value === 'true';
    return !!value;
  };
  return !!(typeof apps !== 'undefined' && apps[appName] && toBool(apps[appName].image_generation));
}

/**
 * Check if the current app supports mask editing.
 * Distinct from basic image generation — Gemini/Grok use semantic masking instead.
 * @param {string} [appName] - App name (defaults to current selection)
 * @returns {boolean}
 */
function isMaskEditingEnabled(appName) {
  if (!appName) {
    var appsEl = $id("apps");
    appName = appsEl ? appsEl.value : null;
  }

  // Disable mask editor for Gemini/Grok Image Generators (use semantic masking instead)
  if (appName && (appName.includes("ImageGeneratorGemini") || appName.includes("ImageGeneratorGrok"))) {
    return false;
  }

  return !!(typeof apps !== 'undefined' && apps[appName] &&
    (apps[appName].image_generation === true ||
     apps[appName].image_generation === "true") &&
    apps[appName].image_generation !== "upload_only");
}

/**
 * Check if the selected model supports OpenAI File Inputs API (XLSX, DOCX, etc.).
 * @param {string} selectedModel - Model ID
 * @returns {boolean}
 */
function isFileInputsSupportedForModel(selectedModel) {
  if (!selectedModel || typeof modelSpec === 'undefined') return false;
  var data = modelSpec[selectedModel];
  return !!(data && data.supports_file_inputs);
}

/**
 * Check if the selected model uses the Responses API.
 * @param {string} selectedModel - Model ID
 * @returns {boolean}
 */
function isResponsesApiModel(selectedModel) {
  if (!selectedModel || typeof modelSpec === 'undefined') return false;
  var data = modelSpec[selectedModel];
  return !!(data && data.api_type === "responses");
}

// Export for browser environment
window.isPdfSupportedForModel = isPdfSupportedForModel;
window.isImageGenerationApp = isImageGenerationApp;
window.isMaskEditingEnabled = isMaskEditingEnabled;
window.isFileInputsSupportedForModel = isFileInputsSupportedForModel;
window.isResponsesApiModel = isResponsesApiModel;

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    isPdfSupportedForModel,
    isImageGenerationApp,
    isMaskEditingEnabled,
    isFileInputsSupportedForModel,
    isResponsesApiModel
  };
}
})();
