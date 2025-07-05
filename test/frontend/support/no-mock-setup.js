/**
 * No-Mock Test Setup for Monadic Chat UI Tests
 * 
 * This setup file provides a real testing environment without mocks,
 * using actual DOM, real libraries, and proper event handling.
 */

// Add TextEncoder/TextDecoder polyfills for Node.js environment
const { TextEncoder, TextDecoder } = require('util');
global.TextEncoder = TextEncoder;
global.TextDecoder = TextDecoder;

const fs = require('fs');
const path = require('path');
const { JSDOM } = require('jsdom');

// Set up proper DOM environment
const dom = new JSDOM('<!DOCTYPE html><html><body></body></html>', {
  url: 'http://localhost:3000',
  pretendToBeVisual: true,
  resources: 'usable',
  runScripts: 'dangerously',
  beforeParse(window) {
    // Add console to window for debugging
    window.console = global.console;
    
    // Set up localStorage and sessionStorage
    const storage = {};
    window.localStorage = {
      getItem: (key) => storage[key] || null,
      setItem: (key, value) => { storage[key] = value.toString(); },
      removeItem: (key) => { delete storage[key]; },
      clear: () => { Object.keys(storage).forEach(key => delete storage[key]); }
    };
    window.sessionStorage = { ...window.localStorage };
    
    // Add performance.now() for timing
    window.performance = {
      now: () => Date.now()
    };
    
    // Add requestAnimationFrame
    window.requestAnimationFrame = (callback) => {
      return setTimeout(callback, 16);
    };
    window.cancelAnimationFrame = (id) => {
      clearTimeout(id);
    };
  }
});

// Make DOM globals available
global.window = dom.window;
global.document = window.document;
global.navigator = window.navigator;

// Add commonly needed globals
global.HTMLElement = window.HTMLElement;
global.Event = window.Event;
global.CustomEvent = window.CustomEvent;
global.KeyboardEvent = window.KeyboardEvent;
global.MouseEvent = window.MouseEvent;
global.ClipboardEvent = window.ClipboardEvent;

// DataTransfer polyfill for jsdom
if (!window.DataTransfer) {
  class DataTransfer {
    constructor() {
      this.items = [];
      this.types = [];
      this._data = {};
    }
    
    setData(format, data) {
      this._data[format] = data;
      if (!this.types.includes(format)) {
        this.types.push(format);
      }
    }
    
    getData(format) {
      return this._data[format] || '';
    }
    
    clearData(format) {
      if (format) {
        delete this._data[format];
        const index = this.types.indexOf(format);
        if (index > -1) {
          this.types.splice(index, 1);
        }
      } else {
        this._data = {};
        this.types = [];
      }
    }
  }
  
  window.DataTransfer = DataTransfer;
  global.DataTransfer = DataTransfer;
} else {
  global.DataTransfer = window.DataTransfer;
}

// Add WebSocket support
const WebSocket = require('ws');
global.WebSocket = WebSocket;

// Load jQuery from actual source
function loadJQuery() {
  const jqueryPath = path.join(__dirname, '../../../docker/services/ruby/public/vendor/js/jquery.min.js');
  if (fs.existsSync(jqueryPath)) {
    const jqueryCode = fs.readFileSync(jqueryPath, 'utf8');
    const scriptEl = document.createElement('script');
    scriptEl.textContent = jqueryCode;
    document.head.appendChild(scriptEl);
    global.$ = window.$;
    global.jQuery = window.jQuery;
  } else {
    console.warn('jQuery file not found at:', jqueryPath);
  }
}

// Load other required libraries
function loadLibraries() {
  // These would be loaded similarly if needed for specific tests
  // For now, we'll add minimal stubs that match real API
  
  // MathJax stub (matches real API)
  window.MathJax = {
    typesetPromise: (elements) => Promise.resolve(),
    startup: {
      document: null,
      promise: Promise.resolve()
    }
  };
  
  // Mermaid stub (matches real API)
  window.mermaid = {
    initialize: (config) => {},
    run: async (config) => {
      return { svg: '<svg></svg>' };
    },
    detectType: (text) => 'flowchart'
  };
}

// Initialize the test environment
function initializeTestEnvironment() {
  loadJQuery();
  loadLibraries();
  
  // Add global test helpers to window
  window.testHelpers = {
    // Helper to load HTML fixtures
    loadHTML: (html) => {
      document.body.innerHTML = html;
    },
    
    // Helper to trigger real events
    triggerEvent: (element, eventType, eventData = {}) => {
      const event = new window.Event(eventType, { bubbles: true, cancelable: true });
      Object.assign(event, eventData);
      element.dispatchEvent(event);
    },
    
    // Helper to wait for async operations
    waitFor: async (condition, timeout = 5000) => {
      const startTime = Date.now();
      while (!condition()) {
        if (Date.now() - startTime > timeout) {
          throw new Error('Timeout waiting for condition');
        }
        await new Promise(resolve => setTimeout(resolve, 50));
      }
    }
  };
}

// Clean up after each test
global.afterEach(() => {
  // Clear DOM
  document.body.innerHTML = '';
  document.head.innerHTML = '';
  
  // Clear any timers
  jest.clearAllTimers();
  
  // Clear localStorage/sessionStorage
  window.localStorage.clear();
  window.sessionStorage.clear();
  
  // Note: We can't clone window in jsdom, so we'll skip that cleanup
  // Event listeners will be cleaned up with the DOM elements
});

// Initialize on import
initializeTestEnvironment();

module.exports = {
  window,
  document,
  loadJQuery,
  loadLibraries,
  initializeTestEnvironment
};