// Model Specification Loader
// Loads model specifications from API with fallback to static file

(function() {
  'use strict';

  // Store the original static modelSpec as fallback
  const staticModelSpec = window.modelSpec || {};

  // Load model specifications from API
  async function loadModelSpec() {
    try {
      const response = await fetch('/api/models');
      
      if (!response.ok) {
        console.warn('Failed to load models from API, using static fallback');
        return staticModelSpec;
      }
      
      const models = await response.json();
      
      // Log if custom models were loaded
      const staticKeys = Object.keys(staticModelSpec);
      const loadedKeys = Object.keys(models);
      const newModels = loadedKeys.filter(key => !staticKeys.includes(key));
      const modifiedModels = staticKeys.filter(key => 
        loadedKeys.includes(key) && 
        JSON.stringify(models[key]) !== JSON.stringify(staticModelSpec[key])
      );
      
      if (newModels.length > 0) {
        console.log(`[Model Loader] Loaded ${newModels.length} custom models:`, newModels);
      }
      
      if (modifiedModels.length > 0) {
        console.log(`[Model Loader] Modified ${modifiedModels.length} existing models:`, modifiedModels);
      }
      
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

  // Export for manual use if needed
  window.loadModelSpec = loadModelSpec;
  window.initializeModels = initializeModels;
})();