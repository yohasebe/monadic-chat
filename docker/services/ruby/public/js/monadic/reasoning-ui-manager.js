/**
 * Provider-specific Reasoning/Thinking UI Manager
 * Manages dynamic UI components for different provider implementations
 */

class ReasoningUIManager {
  constructor() {
    this.currentProvider = null;
    this.currentModel = null;
    this.initialized = false;
  }

  /**
   * Initialize the UI manager
   */
  init() {
    if (this.initialized) return;
    
    // Create additional UI containers
    this.createUIContainers();
    this.initialized = true;
  }

  /**
   * Create provider-specific UI containers
   */
  createUIContainers() {
    const container = document.getElementById('reasoning-effort').parentElement.parentElement;
    
    // Create Claude slider container
    const claudeUI = document.createElement('div');
    claudeUI.id = 'reasoning-ui-claude';
    claudeUI.className = 'reasoning-ui-container';
    claudeUI.style.display = 'none';
    claudeUI.innerHTML = `
      <label class="form-label text-nowrap" data-i18n="ui.thinkingBudget">Thinking Budget</label>
      <div class="d-flex align-items-center gap-2">
        <input type="range" class="form-range flex-fill" id="thinking-budget-slider" 
               min="1024" max="50000" value="10000" step="1000">
        <span id="thinking-budget-value" class="badge bg-secondary" style="min-width: 70px;">10,000</span>
      </div>
    `;
    container.appendChild(claudeUI);

    // Create Gemini detailed settings container
    const geminiUI = document.createElement('div');
    geminiUI.id = 'reasoning-ui-gemini';
    geminiUI.className = 'reasoning-ui-container';
    geminiUI.style.display = 'none';
    geminiUI.innerHTML = `
      <label class="form-label text-nowrap" data-i18n="ui.thinkingMode">Thinking Mode</label>
      <div class="d-flex flex-column gap-2">
        <select class="form-select form-select-sm" id="thinking-mode-preset">
          <option value="auto">Auto (Model decides)</option>
          <option value="minimal">Minimal (Efficiency)</option>
          <option value="low">Low (Balanced)</option>
          <option value="medium">Medium (Quality)</option>
          <option value="high">High (Maximum)</option>
          <option value="custom">Custom...</option>
        </select>
        <div id="thinking-custom-container" style="display: none;">
          <div class="d-flex align-items-center gap-2">
            <input type="number" class="form-control form-control-sm" id="thinking-custom-value" 
                   min="0" max="50000" value="10000" step="1000">
            <span class="text-muted">tokens</span>
          </div>
        </div>
      </div>
    `;
    container.appendChild(geminiUI);

    // Create DeepSeek simple toggle container
    const deepseekUI = document.createElement('div');
    deepseekUI.id = 'reasoning-ui-deepseek';
    deepseekUI.className = 'reasoning-ui-container';
    deepseekUI.style.display = 'none';
    deepseekUI.innerHTML = `
      <label class="form-label text-nowrap" data-i18n="ui.reasoningMode">Reasoning Mode</label>
      <div class="btn-group" role="group">
        <input type="radio" class="btn-check" name="reasoning-mode" id="reasoning-off" value="disabled">
        <label class="btn btn-outline-secondary btn-sm" for="reasoning-off">Off</label>
        
        <input type="radio" class="btn-check" name="reasoning-mode" id="reasoning-on" value="enabled" checked>
        <label class="btn btn-outline-secondary btn-sm" for="reasoning-on">On</label>
      </div>
    `;
    container.appendChild(deepseekUI);

    // Add event listeners
    this.attachEventListeners();
  }

  /**
   * Attach event listeners to UI components
   */
  attachEventListeners() {
    // Claude slider
    const slider = document.getElementById('thinking-budget-slider');
    if (slider) {
      slider.addEventListener('input', (e) => {
        const value = parseInt(e.target.value);
        document.getElementById('thinking-budget-value').textContent = value.toLocaleString();
      });
    }

    // Gemini preset selector
    const presetSelector = document.getElementById('thinking-mode-preset');
    if (presetSelector) {
      presetSelector.addEventListener('change', (e) => {
        const customContainer = document.getElementById('thinking-custom-container');
        customContainer.style.display = e.target.value === 'custom' ? 'block' : 'none';
      });
    }
  }

  /**
   * Update UI based on provider and model
   */
  updateUI(provider, model) {
    if (!this.initialized) this.init();
    
    this.currentProvider = provider;
    this.currentModel = model;

    // Hide all provider-specific UIs
    this.hideAllUIs();

    // Get the default select element
    const defaultSelect = document.getElementById('reasoning-effort');
    const defaultContainer = defaultSelect.parentElement.parentElement;

    // Determine which UI to show
    if (!window.ReasoningMapper || !ReasoningMapper.isSupported(provider, model)) {
      // Not supported - hide everything
      defaultContainer.style.display = 'none';
      return;
    }

    // By default, show the standard dropdown
    defaultContainer.style.display = 'block';
    
    // Show provider-specific UI when appropriate
    switch (provider) {
      case 'Anthropic':
        // Only use special UI for thinking models with budget
        if (this.isThinkingModel(model) && false) { // Disabled for now - use standard UI
          defaultContainer.style.display = 'none';
          document.getElementById('reasoning-ui-claude').style.display = 'block';
        }
        break;

      case 'Google':
        // Standard UI works well for Gemini
        break;

      case 'DeepSeek':
        // Standard UI with limited options works for DeepSeek
        break;
        
      case 'xAI':
        // Standard UI for Grok
        break;
        
      case 'Perplexity':
        // Standard UI for Perplexity
        break;

      default:
        // Use default UI for all other providers
        break;
    }
  }

  /**
   * Hide all provider-specific UIs
   */
  hideAllUIs() {
    const containers = document.querySelectorAll('.reasoning-ui-container');
    containers.forEach(container => {
      container.style.display = 'none';
    });
  }

  /**
   * Check if model supports thinking
   */
  isThinkingModel(model) {
    const spec = window.modelSpec && window.modelSpec[model];
    return spec && (spec.supports_thinking === true || spec.thinking_budget);
  }

  /**
   * Get current UI value based on active UI
   */
  getValue() {
    // Claude slider
    if (document.getElementById('reasoning-ui-claude').style.display !== 'none') {
      return {
        type: 'thinking_budget',
        value: parseInt(document.getElementById('thinking-budget-slider').value)
      };
    }

    // Gemini detailed settings
    if (document.getElementById('reasoning-ui-gemini').style.display !== 'none') {
      const preset = document.getElementById('thinking-mode-preset').value;
      if (preset === 'custom') {
        return {
          type: 'thinking_budget',
          value: parseInt(document.getElementById('thinking-custom-value').value)
        };
      } else {
        return {
          type: 'preset',
          value: preset
        };
      }
    }

    // DeepSeek toggle
    if (document.getElementById('reasoning-ui-deepseek').style.display !== 'none') {
      const value = document.querySelector('input[name="reasoning-mode"]:checked').value;
      return {
        type: 'reasoning_content',
        value: value
      };
    }

    // Default select
    const defaultValue = document.getElementById('reasoning-effort').value;
    return {
      type: 'reasoning_effort',
      value: defaultValue
    };
  }

  /**
   * Set UI value
   */
  setValue(value, type) {
    switch (type) {
      case 'thinking_budget':
        const slider = document.getElementById('thinking-budget-slider');
        if (slider) {
          slider.value = value;
          document.getElementById('thinking-budget-value').textContent = value.toLocaleString();
        }
        break;

      case 'reasoning_content':
        const radio = document.querySelector(`input[name="reasoning-mode"][value="${value}"]`);
        if (radio) {
          radio.checked = true;
        }
        break;

      default:
        const select = document.getElementById('reasoning-effort');
        if (select) {
          select.value = value;
        }
        break;
    }
  }
}

// Create global instance
window.reasoningUIManager = new ReasoningUIManager();