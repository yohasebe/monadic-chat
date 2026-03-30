// Model Specification Loader
// Loads model specifications from API with fallback to static file

(function() {
  'use strict';

  // Store the original static modelSpec as fallback
  const staticModelSpec = window.modelSpec || {};

  // Track if models have been loaded
  window.modelsLoaded = false;

  // Load model specifications from API
  async function loadModelSpec() {
    try {
      const response = await fetch('/api/models');

      if (!response.ok) {
        console.warn('Failed to load models from API, using static fallback');
        return staticModelSpec;
      }

      const models = await response.json();
      return models;

    } catch (error) {
      console.error('[Model Loader] Error loading models:', error);
      return staticModelSpec;
    }
  }

  // Initialize model specifications
  async function initializeModels() {
    const models = await loadModelSpec();

    // Replace global modelSpec with loaded specifications
    window.modelSpec = models;
    window.modelsLoaded = true;

    // Dispatch event to notify that models are loaded
    window.dispatchEvent(new CustomEvent('modelsLoaded', { detail: models }));

    return models;
  }

  // Auto-initialize when DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initializeModels);
  } else {
    // DOM is already loaded
    initializeModels();
  }

  // Listen for modelsLoaded and refresh model selector if empty
  // This handles race condition where WebSocket "apps" message arrives
  // before model specifications are loaded from API
  window.addEventListener('modelsLoaded', function() {
    // Check if model selector exists and is empty
    const modelSelect = $id('model');
    if (modelSelect && modelSelect.options.length === 0) {
      // Model selector is empty, need to repopulate
      // Trigger app change to rebuild model list
      const appsSelect = $id('apps');
      if (appsSelect && appsSelect.value) {
        $dispatch(appsSelect, 'change');
      }
    }
  });

  // Export for manual use if needed
  window.loadModelSpec = loadModelSpec;
  window.initializeModels = initializeModels;
})();