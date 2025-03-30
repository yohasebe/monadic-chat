/**
 * Test helpers for Monadic Chat
 * 
 * This file contains shared utilities and mock factories for testing.
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
    
    // DOM traversal
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
    
    // Track method calls for testing
    _methodCalls: {
      val: [],
      text: [],
      html: [],
      css: [],
      attr: [],
      prop: [],
      on: [],
      off: []
    }
  };
  
  // Store selector for debugging
  mock._selector = selector;
  
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
 * Setup a standard test environment for a single test
 * 
 * @param {Object} options - Configuration options for the environment
 * @returns {Object} - Environment control methods and mocks
 */
function setupTestEnvironment(options = {}) {
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
  
  // Setup common message objects
  global.messages = options.messages || [];
  global.mids = options.mids || new Set();
  
  // Setup other common globals
  global.ws = { send: jest.fn() };
  global.createCard = jest.fn().mockImplementation((role, badge, html, lang, mid) => {
    const card = createJQueryObject('.card');
    if (mid) {
      card.attr('id', mid);
      global.mids.add(mid);
    }
    return card;
  });
  
  // Setup common helper functions
  global.setAlert = jest.fn();
  global.setStats = jest.fn();
  global.setInputFocus = jest.fn();
  
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
  
  // Return clean-up function
  return {
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
    
    // Expose core mocks for test-specific setup
    $: global.$,
    createJQueryObject: createJQueryObject
  };
}

// Expose utilities for tests
module.exports = {
  createJQueryObject,
  createJQueryMock,
  setupTestEnvironment
};