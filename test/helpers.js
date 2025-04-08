/**
 * Common Test Utilities for Monadic Chat
 *
 * This file provides shared utilities for Jest tests including:
 * - jQuery mocking utilities
 * - Test environment setup and teardown
 * - Common mock factories
 */

// Import core dependencies
const fs = require('fs');
const path = require('path');

/**
 * Creates a standardized mock for any jQuery selector.
 * 
 * @param {string} selector - The jQuery selector string
 * @returns {Object} - A mock jQuery object with common methods
 */
function createJQueryObject(selector) {
  const state = {
    value: '',
    text: '',
    html: '',
    css: {},
    attributes: { 'placeholder': 'Type your message...' },
    properties: {},
    data: {},
    display: null,
    checked: false,
    visible: true,
    disabled: false
  };
  
  // Create a chainable mock object
  const mock = {
    // Value methods
    val: jest.fn().mockImplementation(function(newVal) {
      if (newVal === undefined) return state.value;
      state.value = newVal;
      return mock;
    }),
    
    // Content methods
    text: jest.fn().mockImplementation(function(newText) {
      if (newText === undefined) return state.text;
      state.text = newText;
      return mock;
    }),
    
    html: jest.fn().mockImplementation(function(newHtml) {
      if (newHtml === undefined) return state.html;
      state.html = newHtml;
      return mock;
    }),
    
    // Style and attribute methods
    css: jest.fn().mockImplementation(function(prop, value) {
      if (typeof prop === 'object') {
        Object.assign(state.css, prop);
        return mock;
      }
      
      if (value === undefined) return state.css[prop] || '';
      state.css[prop] = value;
      return mock;
    }),
    
    attr: jest.fn().mockImplementation(function(name, value) {
      if (value === undefined) return state.attributes[name];
      state.attributes[name] = value;
      return mock;
    }),
    
    prop: jest.fn().mockImplementation(function(name, value) {
      if (value === undefined) {
        if (name === 'disabled') return state.disabled;
        if (name === 'checked') return state.checked;
        return state.properties[name];
      }
      
      if (name === 'disabled') state.disabled = value;
      else if (name === 'checked') state.checked = value;
      else state.properties[name] = value;
      
      return mock;
    }),
    
    // State methods
    hide: jest.fn().mockImplementation(function() {
      state.display = 'none';
      return mock;
    }),
    
    show: jest.fn().mockImplementation(function() {
      state.display = 'block';
      return mock;
    }),
    
    is: jest.fn().mockImplementation(function(selector) {
      if (selector === ':visible') return state.display !== 'none';
      if (selector === ':checked') return state.checked;
      if (selector === ':disabled') return state.disabled;
      return false;
    }),
    
    // Data methods
    data: jest.fn().mockImplementation(function(key, value) {
      if (value === undefined) return state.data[key];
      state.data[key] = value;
      return mock;
    }),
    
    // DOM traversal - all return a new mock for chaining
    find: jest.fn().mockReturnThis(),
    parent: jest.fn().mockReturnThis(),
    parents: jest.fn().mockReturnThis(),
    closest: jest.fn().mockReturnThis(),
    children: jest.fn().mockReturnThis(),
    
    // Event methods
    on: jest.fn().mockReturnThis(),
    off: jest.fn().mockReturnThis(),
    trigger: jest.fn().mockReturnThis(),
    click: jest.fn().mockImplementation(function(handler) {
      if (handler) handler();
      return mock;
    }),
    
    // Common jQuery methods
    remove: jest.fn().mockReturnThis(),
    empty: jest.fn().mockReturnThis(),
    append: jest.fn().mockReturnThis(),
    appendTo: jest.fn().mockReturnThis(),
    prepend: jest.fn().mockReturnThis(),
    before: jest.fn().mockReturnThis(),
    after: jest.fn().mockReturnThis(),
    addClass: jest.fn().mockReturnThis(),
    removeClass: jest.fn().mockReturnThis(),
    toggleClass: jest.fn().mockReturnThis(),
    hasClass: jest.fn().mockReturnValue(false),
    
    // Dialog methods
    modal: jest.fn().mockReturnThis(),
    tooltip: jest.fn().mockReturnThis(),
    focus: jest.fn(),
    
    // Array-like methods
    length: 1,
    get: jest.fn().mockImplementation(index => {
      if (index === undefined) return [{}];
      return {};
    }),
    each: jest.fn().mockImplementation(function(callback) {
      callback.call(mock, 0, mock);
      return mock;
    }),
    
    // Make it array-like
    0: {},
    
    // Store selector for debugging
    _selector: selector
  };
  
  return mock;
}

/**
 * Creates a standardized jQuery mock function
 * 
 * @returns {Function} - A mock jQuery function
 */
function createJQueryMock() {
  const jQueryMock = jest.fn().mockImplementation(selector => {
    // Handle HTML string for creating elements
    if (typeof selector === 'string' && selector.startsWith('<') && selector.endsWith('>')) {
      return createJQueryObject('element:' + selector);
    }
    return createJQueryObject(selector);
  });
  
  // Add static jQuery methods
  jQueryMock.ajax = jest.fn().mockImplementation(options => {
    setTimeout(() => {
      if (options && options.success) {
        options.success({ success: true });
      }
    }, 10);
    
    return {
      promise: jest.fn().mockReturnThis(),
      done: jest.fn().mockReturnThis(),
      fail: jest.fn().mockReturnThis(),
      always: jest.fn().mockReturnThis()
    };
  });
  
  jQueryMock.Deferred = jest.fn().mockImplementation(() => ({
    resolve: jest.fn(),
    reject: jest.fn(),
    promise: jest.fn().mockReturnThis(),
    done: jest.fn().mockReturnThis(),
    fail: jest.fn().mockReturnThis(),
    always: jest.fn().mockReturnThis()
  }));
  
  return jQueryMock;
}

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
  
  // Setup jQuery
  global.$ = createJQueryMock();
  global.jQuery = global.$;
  
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
    const card = createJQueryObject('.card');
    if (mid) {
      card.attr('id', mid);
      global.mids.add(mid);
    }
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
    $: global.$,
    window: global.window,
    ws: global.ws,
    createJQueryObject: createJQueryObject,
    
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

// Create a standardized mock factory for UI components
const mockFactories = {
  // Create a standard card mock
  createCardMock: (options = {}) => {
    const {
      role = 'assistant',
      badge = '<span>Icon</span>',
      html = 'Card content',
      language = 'en',
      mid = `card-${Date.now()}`,
      status = true,
      images = []
    } = options;
    
    const card = createJQueryObject(`.card#${mid}`);
    card.role = role;
    card.badge = badge;
    card.content = html;
    card.lang = language;
    card.status = status;
    card.images = images;
    
    return card;
  }
};

// Expose utilities for tests
module.exports = {
  createJQueryObject,
  createJQueryMock,
  createWebSocketMock,
  createWindowMock,
  setupTestEnvironment,
  mockFactories
};