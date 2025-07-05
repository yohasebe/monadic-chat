/**
 * Fixture Loader for No-Mock UI Testing
 * 
 * Loads HTML fixtures from the actual application views
 * and prepares them for testing.
 */

const fs = require('fs').promises;
const path = require('path');

/**
 * Extract specific sections from the main index.erb file
 * Note: Simplified implementation without cheerio to avoid ESM issues
 * @param {string} sectionId - ID of section to extract
 * @returns {Promise<string>} Extracted HTML
 */
async function extractHTMLSection(sectionId) {
  // For now, return predefined sections
  const sections = {
    'chat-interface': `
      <div id="main-panel">
        <div class="form-group">
          <textarea id="message" class="form-control" rows="4"></textarea>
        </div>
        <div id="discourse"></div>
        <div class="button-container">
          <button id="send" class="btn btn-primary">Send</button>
          <button id="clear" class="btn btn-secondary">Clear</button>
        </div>
      </div>
    `,
    'control-panel': `
      <div id="control-panel">
        <select id="apps" class="form-select"></select>
        <select id="model" class="form-select"></select>
      </div>
    `,
    'settings-modal': `
      <div class="modal" id="settingsModal">
        <div class="modal-dialog">
          <div class="modal-content">
            <div class="modal-body">Settings</div>
          </div>
        </div>
      </div>
    `
  };
  
  if (sections[sectionId]) {
    return sections[sectionId];
  }
  
  throw new Error(`Section ${sectionId} not found`);
}

/**
 * Load a minimal HTML structure for testing
 * @param {Object} options - Configuration options
 * @returns {string} HTML string
 */
function createMinimalFixture(options = {}) {
  const {
    includeMessage = true,
    includeDiscourse = true,
    includeButtons = true,
    includeModals = false,
    customElements = []
  } = options;
  
  let html = '<div id="main">';
  
  if (includeMessage) {
    html += `
      <div class="form-group">
        <textarea id="message" class="form-control" rows="4" placeholder="Type your message..."></textarea>
        <div id="char-counter" style="display: none;">
          <span id="char-count">0</span> / <span id="char-limit">50000</span>
        </div>
      </div>
    `;
  }
  
  if (includeDiscourse) {
    html += `
      <div id="discourse" class="discourse-container">
        <div id="chat-bottom"></div>
      </div>
    `;
  }
  
  if (includeButtons) {
    html += `
      <div class="button-container">
        <button id="send" class="btn btn-primary" disabled>
          <i class="fas fa-paper-plane"></i> Send
        </button>
        <button id="clear" class="btn btn-secondary">
          <i class="fas fa-eraser"></i> Clear
        </button>
        <button id="voice" class="btn btn-info">
          <i class="fas fa-microphone"></i> Voice
        </button>
        <button id="image-file" class="btn btn-info">
          <i class="fas fa-image"></i> Image
        </button>
        <button id="doc" class="btn btn-info">
          <i class="fas fa-file-alt"></i> Doc
        </button>
        <button id="url" class="btn btn-info">
          <i class="fas fa-link"></i> URL
        </button>
        <div class="form-check">
          <input type="checkbox" id="check-easy-submit" class="form-check-input">
          <label class="form-check-label" for="check-easy-submit">Easy Submit</label>
        </div>
      </div>
    `;
  }
  
  // Add custom elements
  customElements.forEach(element => {
    html += element;
  });
  
  if (includeModals) {
    html += `
      <!-- Image Modal -->
      <div class="modal fade" id="imageModal" tabindex="-1">
        <div class="modal-dialog">
          <div class="modal-content">
            <div class="modal-header">
              <h5 class="modal-title" id="imageModalLabel">Select Image</h5>
              <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
            </div>
            <div class="modal-body">
              <input type="file" id="imageFile" accept="image/*" class="form-control">
              <div id="select_image_error" class="text-danger mt-2"></div>
            </div>
            <div class="modal-footer">
              <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Cancel</button>
              <button type="button" id="uploadImage" class="btn btn-primary" disabled>Upload</button>
            </div>
          </div>
        </div>
      </div>
    `;
  }
  
  html += `
    <div id="alert-message" class="alert-message" style="display: none;"></div>
    <div id="monadic-spinner" class="spinner-border" style="display: none;"></div>
  `;
  
  html += '</div>';
  
  return html;
}

/**
 * Load fixture with common UI elements
 * @param {string} fixtureName - Name of the fixture
 * @returns {Promise<string>} HTML content
 */
async function loadCommonFixture(fixtureName) {
  const fixtures = {
    'basic-chat': () => createMinimalFixture({
      includeMessage: true,
      includeDiscourse: true,
      includeButtons: true
    }),
    
    'chat-with-modals': () => createMinimalFixture({
      includeMessage: true,
      includeDiscourse: true,
      includeButtons: true,
      includeModals: true
    }),
    
    'settings-panel': () => createMinimalFixture({
      includeMessage: false,
      includeDiscourse: false,
      includeButtons: false,
      customElements: [
        '<select id="apps" class="form-select"></select>',
        '<select id="model" class="form-select"></select>',
        '<input type="range" id="temperature" min="0" max="2" step="0.1" value="0.3">',
        '<span id="temperature-value">0.3</span>',
        '<input type="checkbox" id="websearch">',
        '<div><input type="checkbox" id="check-easy-submit"> Easy Submit</div>',
        '<input type="checkbox" id="check-auto-speech">'
      ]
    }),
    
    'message-display': () => createMinimalFixture({
      includeMessage: false,
      includeDiscourse: true,
      includeButtons: false,
      customElements: [
        '<div id="stats-message" class="stats-message"></div>'
      ]
    })
  };
  
  if (fixtures[fixtureName]) {
    return fixtures[fixtureName]();
  }
  
  throw new Error(`Fixture ${fixtureName} not found`);
}

/**
 * Prepare DOM for testing by adding required elements
 */
function prepareDOM() {
  // Add Bootstrap classes to body for proper styling
  document.body.className = 'monadic-chat-ui';
  
  // Add viewport meta tag
  const viewport = document.createElement('meta');
  viewport.name = 'viewport';
  viewport.content = 'width=device-width, initial-scale=1';
  document.head.appendChild(viewport);
  
  // Add container div
  const container = document.createElement('div');
  container.className = 'container-fluid';
  document.body.appendChild(container);
  
  return container;
}

/**
 * Load fixture into the test DOM
 * @param {string} fixtureNameOrHTML - Fixture name or HTML string
 */
async function setupFixture(fixtureNameOrHTML) {
  const container = prepareDOM();
  
  let html;
  if (fixtureNameOrHTML.includes('<')) {
    // Direct HTML provided
    html = fixtureNameOrHTML;
  } else {
    // Load named fixture
    html = await loadCommonFixture(fixtureNameOrHTML);
  }
  
  container.innerHTML = html;
  
  // Trigger any initialization that might be needed
  if (window.$ && window.$.fn) {
    window.$(document).trigger('ready');
  }
}

module.exports = {
  extractHTMLSection,
  createMinimalFixture,
  loadCommonFixture,
  prepareDOM,
  setupFixture
};