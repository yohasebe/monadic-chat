/**
 * Common Test Utilities for Monadic Chat
 *
 * This file provides shared utilities for Jest tests including:
 * - Test environment setup and teardown
 * - Common mock factories
 */

// Import core dependencies
const fs = require('fs');
const path = require('path');

/**
 * Common mock factory for consistent WebSocket simulation
 *
 * @returns {Object} - Mock WebSocket object with event tracking
 */
function createWebSocketMock() {
  const events = {};

  const wsConnection = {
    readyState: 1, // WebSocket.OPEN
    events,
    send: jest.fn(),
    close: jest.fn(),

    // Event handlers
    onopen: null,
    onclose: null,
    onmessage: null,
    onerror: null,

    // Event simulation methods
    _simulateOpen: function() {
      if (this.onopen) this.onopen({ type: 'open' });
      if (events.open) events.open.forEach(handler => handler({ type: 'open' }));
    },

    _simulateMessage: function(data) {
      const messageEvent = {
        type: 'message',
        data: typeof data === 'object' ? JSON.stringify(data) : data
      };

      if (this.onmessage) this.onmessage(messageEvent);
      if (events.message) events.message.forEach(handler => handler(messageEvent));
    },

    _simulateClose: function(code = 1000, reason = '') {
      const closeEvent = {
        type: 'close',
        code,
        reason,
        wasClean: code === 1000
      };

      if (this.onclose) this.onclose(closeEvent);
      if (events.close) events.close.forEach(handler => handler(closeEvent));
    },

    _simulateError: function(error = 'Connection error') {
      const errorEvent = {
        type: 'error',
        error,
        message: error.toString()
      };

      if (this.onerror) this.onerror(errorEvent);
      if (events.error) events.error.forEach(handler => handler(errorEvent));
    },

    // EventTarget interface
    addEventListener: jest.fn().mockImplementation((event, handler) => {
      if (!events[event]) events[event] = [];
      events[event].push(handler);
    }),

    removeEventListener: jest.fn().mockImplementation((event, handler) => {
      if (!events[event]) return;
      const idx = events[event].indexOf(handler);
      if (idx !== -1) events[event].splice(idx, 1);
    })
  };

  return wsConnection;
}

/**
 * Creates a mock window object with common properties and methods
 *
 * @param {Object} options - Customization options
 * @returns {Object} - Mock window object
 */
function createWindowMock(options = {}) {
  return {
    // Properties
    innerWidth: options.innerWidth || 1024,
    innerHeight: options.innerHeight || 768,
    location: {
      href: options.href || 'http://localhost:8080/',
      hostname: options.hostname || 'localhost',
      pathname: options.pathname || '/',
      search: options.search || '',
      hash: options.hash || ''
    },

    // Event handling
    addEventListener: jest.fn(),
    removeEventListener: jest.fn(),

    // Storage
    localStorage: {
      getItem: jest.fn().mockImplementation(key => options.localStorage?.[key] || null),
      setItem: jest.fn(),
      removeItem: jest.fn()
    },

    sessionStorage: {
      getItem: jest.fn().mockImplementation(key => options.sessionStorage?.[key] || null),
      setItem: jest.fn(),
      removeItem: jest.fn()
    },

    // Dialog methods
    alert: jest.fn(),
    confirm: jest.fn().mockReturnValue(true),
    prompt: jest.fn().mockReturnValue(''),

    // Timeout/interval handling
    setTimeout: jest.fn().mockImplementation((cb, ms) => {
      if (options.executeTimeouts) setTimeout(cb, ms);
      return Math.floor(Math.random() * 1000);
    }),
    clearTimeout: jest.fn(),
    setInterval: jest.fn().mockReturnValue(Math.floor(Math.random() * 1000)),
    clearInterval: jest.fn(),

    // Focus management
    focus: jest.fn(),
    blur: jest.fn(),

    // Navigation
    open: jest.fn(),
    close: jest.fn(),
    history: {
      back: jest.fn(),
      forward: jest.fn(),
      pushState: jest.fn(),
      replaceState: jest.fn()
    }
  };
}

/**
 * Setup a standard test environment for a single test
 *
 * @param {Object} options - Configuration options for the environment
 * @returns {Object} - Environment control methods and mocks
 */
function setupTestEnvironment(options = {}) {
  // Store originals
  const originalConsole = global.console;
  const originalDocument = global.document;
  const originalWindow = global.window;
  const originalNavigator = global.navigator;

  // Setup standard mocks
  global.console = {
    ...console,
    log: jest.fn(),
    error: jest.fn(),
    warn: jest.fn(),
    info: jest.fn(),
  };

  // Setup WebSocket
  global.ws = createWebSocketMock();

  // Setup window
  global.window = createWindowMock(options.window);

  // Setup common message objects
  global.messages = options.messages || [];
  global.mids = options.mids || new Set();

  // Setup event tracking
  const eventListeners = {};

  // Setup common helper functions
  global.setAlert = jest.fn();
  global.setStats = jest.fn();
  global.setInputFocus = jest.fn();
  global.formatInfo = jest.fn().mockReturnValue('');
  global.createCard = jest.fn().mockImplementation((role, badge, html, lang, mid) => {
    const card = document.createElement('div');
    card.className = 'card';
    if (mid) {
      card.id = mid;
      global.mids.add(mid);
    }
    card.innerHTML = `<div class="card-text"><div class="role-${role}">${html}</div></div>`;
    return card;
  });

  // Setup browser detection flags
  global.runningOnChrome = options.chrome || false;
  global.runningOnEdge = options.edge || false;
  global.runningOnFirefox = options.firefox || false;
  global.runningOnSafari = options.safari || false;

  // Setup common constants
  global.DEFAULT_MAX_INPUT_TOKENS = 4000;
  global.DEFAULT_MAX_OUTPUT_TOKENS = 4000;
  global.DEFAULT_CONTEXT_SIZE = 100;
  global.DEFAULT_APP = "";

  // Create DOM for test
  document.body.innerHTML = options.bodyHtml || '';

  // Setup app-specific functions as needed
  if (options.setupAppFunctions) {
    options.setupAppFunctions();
  }

  return {
    // Clean-up function to restore originals
    cleanup: () => {
      // Restore original globals
      global.console = originalConsole;
      global.document = originalDocument;
      global.window = originalWindow;
      global.navigator = originalNavigator;

      // Clear document body
      document.body.innerHTML = '';

      // Reset mocks
      jest.resetAllMocks();

      // Clear message arrays
      global.messages.length = 0;
      global.mids.clear();
    },

    // Simulate WebSocket communications
    simulateWebSocketOpen: () => global.ws._simulateOpen(),
    simulateWebSocketMessage: (data) => global.ws._simulateMessage(data),
    simulateWebSocketClose: (code, reason) => global.ws._simulateClose(code, reason),
    simulateWebSocketError: (error) => global.ws._simulateError(error),

    // Expose core mocks for test-specific setup
    window: global.window,
    ws: global.ws,

    // Simulate events
    simulateEvent: (eventType, eventData = {}) => {
      if (eventListeners[eventType]) {
        eventListeners[eventType].forEach(listener => {
          listener(eventData);
        });
      }
    },

    // Add event listener for testing
    addEventListener: (eventType, listener) => {
      if (!eventListeners[eventType]) eventListeners[eventType] = [];
      eventListeners[eventType].push(listener);
    },

    // Remove event listener
    removeEventListener: (eventType, listener) => {
      if (!eventListeners[eventType]) return;
      const index = eventListeners[eventType].indexOf(listener);
      if (index !== -1) {
        eventListeners[eventType].splice(index, 1);
      }
    }
  };
}

/**
 * Get default model from providerDefaults.
 * @param {string} provider - Provider key (e.g., "openai", "anthropic")
 * @param {string} [category="chat"] - Category (chat, code, vision, audio_transcription)
 * @returns {string|undefined} The default model name (first in list)
 */
function getDefaultModel(provider, category = 'chat') {
  const specPath = path.join(__dirname, '../docker/services/ruby/public/js/monadic/model_spec.js');
  delete require.cache[require.resolve(specPath)];
  const spec = require(specPath);
  const defaults = spec.providerDefaults;
  if (!defaults || !defaults[provider] || !defaults[provider][category]) return undefined;
  return defaults[provider][category][0];
}

// Expose utilities for tests
module.exports = {
  createWebSocketMock,
  createWindowMock,
  setupTestEnvironment,
  getDefaultModel
};
