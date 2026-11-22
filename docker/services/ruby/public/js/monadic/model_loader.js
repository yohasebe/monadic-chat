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

  // Fetch Ollama-specific model capabilities (vision/tools/thinking) from
  // /api/ollama/models. Unlike cloud providers, Ollama models are installed
  // locally by the user and vary per machine, so their capabilities must be
  // queried dynamically from Ollama's /api/show endpoint at runtime.
  // Returns an empty object if Ollama is unreachable — the UI still works,
  // it just won't show vision upload for Ollama models we can't inspect.
  async function loadOllamaCapabilities() {
    try {
      const response = await fetch('/api/ollama/models');
      if (!response.ok) return {};
      const data = await response.json();
      return data.models || {};
    } catch (error) {
      console.warn('[Model Loader] Could not fetch Ollama capabilities:', error.message);
      return {};
    }
  }

  // The Ollama models installed now, for an Ollama app just chosen: models
  // pulled or removed, or Ollama started, after the page loaded. When the
  // list differs from the one the page has, every Ollama app takes the new
  // list and the chosen app is set up again with it.
  let refreshingOllama = false;
  window.refreshOllamaModels = async function refreshOllamaModels(appValue) {
    const apps = window.apps || {};
    const app = apps[appValue];
    if (refreshingOllama || !app || String(app.group || '').toLowerCase() !== 'ollama') return false;
    refreshingOllama = true;
    try {
      const models = await loadOllamaCapabilities();
      const names = Object.keys(models);
      if (names.length === 0) return false;
      let current = [];
      try { current = JSON.parse(app.models || '[]'); } catch (_) { current = []; }
      // What each model can do is taken also when the list is the same: the
      // page may hold the names alone (Ollama could not be asked before).
      const capabilitiesChanged = names.some((name) => {
        return JSON.stringify(window.modelSpec[name]) !== JSON.stringify(models[name]);
      });
      Object.assign(window.modelSpec, models);
      if (JSON.stringify(current) === JSON.stringify(names) && !capabilitiesChanged) return false;
      Object.keys(apps).forEach((key) => {
        if (String(apps[key].group || '').toLowerCase() === 'ollama') apps[key].models = JSON.stringify(names);
      });
      // The app the page shows now is the one set up again: another chosen
      // while Ollama was asked is not set back to this one, and takes the
      // new list when it is an Ollama app too.
      const chosen = typeof $id === 'function' ? $id('apps') : null;
      const shown = chosen && chosen.value !== appValue ? chosen.value : appValue;
      if (String((apps[shown] || {}).group || '').toLowerCase() !== 'ollama') return false;
      if (typeof window.proceedWithAppChange === 'function') window.proceedWithAppChange(shown);
      return true;
    } finally {
      refreshingOllama = false;
    }
  };

  // Initialize model specifications
  async function initializeModels() {
    const models = await loadModelSpec();

    // Merge API models + dynamic Ollama capabilities INTO the existing
    // window.modelSpec object (which is the same reference as the `const modelSpec`
    // in model_spec.js). Replacing with `window.modelSpec = newObj` would break
    // code that captured the original object reference via the const binding.
    const ollamaModels = await loadOllamaCapabilities();
    Object.assign(window.modelSpec, models, ollamaModels);
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