/**
 * Global Jest Test Setup for Monadic Chat
 *
 * This file provides the global setup for Jest tests, including:
 * - Mock global objects (console, document, window)
 * - Mock browser APIs (fetch, WebSocket)
 * - Mock DOM elements
 * - Setup for jQuery and other libraries
 */

const { createJQueryMock } = require('./helpers');

// Mock global variables and functions needed for tests

// Mock console methods to avoid cluttering test output
global.console = {
  ...console,
  log: jest.fn(),
  error: jest.fn(),
  warn: jest.fn(),
  info: jest.fn(),
};

// Mock window properties and methods
global.window = {
  ...global.window,
  addEventListener: jest.fn(),
  removeEventListener: jest.fn(),
  innerHeight: 1080,
  innerWidth: 1920,
  localStorage: {
    getItem: jest.fn(),
    setItem: jest.fn(),
    removeItem: jest.fn(),
  },
  sessionStorage: {
    getItem: jest.fn(),
    setItem: jest.fn(),
    removeItem: jest.fn(),
  },
  location: {
    href: 'http://localhost:8080/',
    hostname: 'localhost',
    pathname: '/',
    search: '',
    hash: ''
  },
  performance: {
    now: jest.fn(() => Date.now()),
    timing: {
      navigationStart: 1000,
      loadEventEnd: 2000,
      domContentLoadedEventEnd: 1500,
      responseEnd: 1200
    },
    memory: {
      usedJSHeapSize: 1000000,
      totalJSHeapSize: 2000000,
      jsHeapSizeLimit: 4000000
    }
  },
  Date: global.Date,
  setTimeout: global.setTimeout,
  clearTimeout: global.clearTimeout,
  setInterval: global.setInterval,
  clearInterval: global.clearInterval
};

// Mock document with proper body
document.body = document.createElement('body');

// Create and add mock elements to the DOM for testing
const createElementWithId = (type, id) => {
  const element = document.createElement(type);
  element.id = id.replace('#', '');
  document.body.appendChild(element);
  return element;
};

// Setup common test elements
[
  ['input', 'message'],
  ['div', 'discourse'],
  ['button', 'send'],
  ['button', 'clear'],
  ['button', 'voice'],
  ['input', 'image-file'],
  ['button', 'doc'],
  ['button', 'url'],
  ['div', 'monadic-spinner'],
  ['input', 'token'],
  ['input', 'api-token'],
  ['input', 'ai-user-initial-prompt'],
  ['button', 'start'],
  ['select', 'select-role'],
  ['select', 'apps'],
  ['select', 'model'],
  ['button', 'cancel_query'],
  ['div', 'chat-bottom'],
  ['div', 'main-panel'],
  ['input', 'check-easy-submit']
].forEach(([type, id]) => createElementWithId(type, id));

// Setup jQuery using helpers
global.$ = createJQueryMock();
global.jQuery = global.$;

// Setup common JavaScript visualization libraries
global.MathJax = {
  typesetPromise: jest.fn().mockResolvedValue(true)
};

global.mermaid = {
  initialize: jest.fn(),
  run: jest.fn().mockResolvedValue(true),
  detectType: jest.fn().mockReturnValue('flowchart')
};

global.ABCJS = {
  renderAbc: jest.fn().mockReturnValue([{}]),
  synth: {
    supportsAudio: jest.fn().mockReturnValue(true),
    SynthController: jest.fn().mockImplementation(() => ({
      load: jest.fn(),
      setTune: jest.fn()
    })),
    playEvent: jest.fn()
  }
};

// Mock default constants needed by most modules
global.DEFAULT_APP = 'Chat';
global.runningOnFirefox = false;
global.runningOnChrome = true;
global.runningOnSafari = false;
global.runningOnEdge = false;

// Common utility functions
global.setAlert = jest.fn();
global.setStats = jest.fn();
global.formatInfo = jest.fn().mockReturnValue('');
global.createCard = jest.fn();
global.updateItemStates = jest.fn();
global.setCookie = jest.fn();
global.getCookie = jest.fn();
global.setInputFocus = jest.fn();
global.listModels = jest.fn().mockReturnValue('<option>model1</option>');
global.modelSpec = { 'gpt-4.1': { reasoning_effort: 'high' } };

// Mock browser multimedia APIs
global.Audio = jest.fn().mockImplementation(() => ({
  src: '',
  play: jest.fn().mockResolvedValue(undefined),
  pause: jest.fn(),
  load: jest.fn()
}));

global.MediaSource = jest.fn().mockImplementation(() => ({
  addEventListener: jest.fn((event, callback) => {
    if (event === 'sourceopen' && callback) callback();
  }),
  addSourceBuffer: jest.fn().mockReturnValue({
    addEventListener: jest.fn(),
    appendBuffer: jest.fn(),
    remove: jest.fn(),
    updating: false
  }),
  readyState: 'open'
}));

// Mock URL and file handling methods
global.URL = {
  createObjectURL: jest.fn().mockReturnValue('blob:test'),
  revokeObjectURL: jest.fn()
};

global.Uint8Array = jest.fn();
global.Uint8Array.from = jest.fn().mockImplementation(() => new Array(10));

global.atob = jest.fn().mockReturnValue('test-audio-data');
global.btoa = jest.fn().mockReturnValue('dGVzdC1hdWRpby1kYXRh');

global.XMLSerializer = jest.fn().mockImplementation(() => ({
  serializeToString: jest.fn().mockReturnValue('<svg></svg>')
}));

global.Blob = jest.fn().mockImplementation(() => ({}));

// Navigator APIs
if (!global.navigator) {
  global.navigator = {};
}

global.navigator.clipboard = {
  writeText: jest.fn().mockResolvedValue(undefined)
};

// Common global state
global.mids = new Set();
