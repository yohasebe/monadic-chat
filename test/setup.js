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
  innerWidth: 1920
};

// Mock document with proper body
document.body = document.createElement('body');

// Create and add mock elements to the DOM for testing
const mockElements = {
  '#message': document.createElement('input'),
  '#discourse': document.createElement('div'),
  '#send': document.createElement('button'),
  '#clear': document.createElement('button'),
  '#voice': document.createElement('button'),
  '#image-file': document.createElement('input'),
  '#doc': document.createElement('button'),
  '#url': document.createElement('button'),
  '#monadic-spinner': document.createElement('div'),
  '#token': document.createElement('input'),
  '#api-token': document.createElement('input'),
  '#ai-user-initial-prompt': document.createElement('input'),
  '#start': document.createElement('button'),
  '#select-role': document.createElement('select'),
  '#apps': document.createElement('select'),
  '#model': document.createElement('select'),
  '#cancel_query': document.createElement('button'),
  '#chat-bottom': document.createElement('div'),
  '#main-panel': document.createElement('div'),
  '#check-easy-submit': document.createElement('input'),
};

// Add elements to document body
Object.values(mockElements).forEach(el => document.body.appendChild(el));

// Create a mocked jQuery interface
const jQuery = {
  ajax: jest.fn().mockImplementation(options => {
    // Simulate async behavior
    setTimeout(() => {
      if (options && options.success) {
        options.success({ success: true });
      }
    }, 10);
    return { 
      promise: jest.fn(),
      done: jest.fn().mockReturnThis(),
      fail: jest.fn().mockReturnThis(),
      always: jest.fn().mockReturnThis()
    };
  }),
  
  modal: jest.fn().mockReturnValue({ modal: jest.fn() }),
  
  Deferred: jest.fn().mockImplementation(() => ({
    resolve: jest.fn(),
    reject: jest.fn(),
    promise: jest.fn().mockReturnThis(),
    done: jest.fn().mockReturnThis(),
    fail: jest.fn().mockReturnThis(),
    always: jest.fn().mockReturnThis()
  }))
};

// Create a shared state store for jQuery selectors
const selectorStates = new Map();

// Create a function to generate jQuery selector objects
function createJQueryObject(selector) {
  // Get or create state for this selector
  if (!selectorStates.has(selector)) {
    selectorStates.set(selector, {
      value: '',
      placeholder: 'Type your message...',
      disabled: false,
      attributes: { placeholder: 'Type your message...' },
      data: {},
      properties: {},
      text: '',
      html: ''
    });
  }
  
  const state = selectorStates.get(selector);
  
  // Create a chainable object with all jQuery methods
  const mockObject = {
    // Improved val() implementation
    val: jest.fn().mockImplementation(function(newVal) {
      if (newVal === undefined) return state.value;
      state.value = newVal;
      return mockObject;
    }),
    
    // Improved text() implementation
    text: jest.fn().mockImplementation(function(newText) {
      if (newText === undefined) return state.text || '';
      state.text = newText;
      return mockObject;
    }),
    
    // Improved html() implementation
    html: jest.fn().mockImplementation(function(newHtml) {
      if (newHtml === undefined) return state.html || '';
      state.html = newHtml;
      return mockObject;
    }),
    
    // Improved attr() implementation - now correctly returns this for chaining
    attr: jest.fn().mockImplementation(function(name, value) {
      if (value === undefined) {
        return state.attributes[name];
      }
      state.attributes[name] = value;
      if (name === 'placeholder') {
        state.placeholder = value;
      }
      return mockObject;
    }),
    
    // Improved prop() implementation
    prop: jest.fn().mockImplementation(function(name, value) {
      if (value === undefined) {
        if (name === 'disabled') return state.disabled;
        return state.properties?.[name];
      }
      if (name === 'disabled') {
        state.disabled = value;
      } else {
        if (!state.properties) state.properties = {};
        state.properties[name] = value;
      }
      return mockObject;
    }),
    
    // Improved data() implementation
    data: jest.fn().mockImplementation(function(name, value) {
      if (value === undefined) {
        return state.data[name];
      }
      state.data[name] = value;
      return mockObject;
    }),
    
    append: jest.fn().mockReturnThis(),
    appendTo: jest.fn().mockReturnThis(),
    prepend: jest.fn().mockReturnThis(),
    find: jest.fn().mockReturnThis(),
    addClass: jest.fn().mockReturnThis(),
    removeClass: jest.fn().mockReturnThis(),
    trigger: jest.fn().mockReturnThis(),
    show: jest.fn().mockReturnThis(),
    hide: jest.fn().mockReturnThis(),
    click: jest.fn().mockImplementation(function(handler) {
      if (handler) handler();
      return mockObject;
    }),
    on: jest.fn().mockReturnThis(),
    off: jest.fn().mockReturnThis(),
    one: jest.fn((event, handler) => {
      if (handler) handler();
      return mockObject;
    }),
    each: jest.fn().mockImplementation(function(callback) {
      callback.call(mockObject, 0, mockObject);
      return mockObject;
    }),
    is: jest.fn().mockReturnValue(false),
    hasClass: jest.fn().mockReturnValue(false),
    css: jest.fn().mockReturnThis(),
    length: 1,
    get: jest.fn().mockImplementation((index) => {
      if (index === undefined) return [mockElements[selector] || {}];
      return mockElements[selector] || {};
    }),
    prev: jest.fn().mockReturnThis(),
    next: jest.fn().mockReturnThis(),
    parent: jest.fn().mockReturnThis(),
    parents: jest.fn().mockReturnThis(),
    children: jest.fn().mockReturnThis(),
    siblings: jest.fn().mockReturnThis(),
    last: jest.fn().mockReturnThis(),
    first: jest.fn().mockReturnThis(),
    before: jest.fn().mockReturnThis(),
    after: jest.fn().mockReturnThis(),
    remove: jest.fn().mockReturnThis(),
    empty: jest.fn().mockReturnThis(),
    height: jest.fn().mockReturnValue(100),
    width: jest.fn().mockReturnValue(100),
    scrollTop: jest.fn().mockReturnValue(0),
    tooltip: jest.fn().mockReturnThis(),
    modal: jest.fn().mockReturnThis(),
  };

  // Make it array-like
  mockObject[0] = {};
  mockObject.length = 1;
  
  return mockObject;
}

// Create an implementation of the jQuery function
const $ = jest.fn().mockImplementation(selector => {
  return createJQueryObject(selector);
});

// Add all static methods
Object.assign($, jQuery);

// Make $ and jQuery available globally
global.$ = $;
global.jQuery = $;

// Mock MathJax
global.MathJax = {
  typesetPromise: jest.fn().mockResolvedValue(true)
};

// Mock mermaid
global.mermaid = {
  initialize: jest.fn(),
  run: jest.fn().mockResolvedValue(true),
  detectType: jest.fn().mockReturnValue('flowchart')
};

// Mock ABCJS
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

// Default constants needed by websocket.js
global.DEFAULT_APP = 'Chat';
global.runningOnFirefox = false;
global.setAlert = jest.fn();
global.setStats = jest.fn();
global.formatInfo = jest.fn().mockReturnValue('');
global.createCard = jest.fn();
global.updateItemStates = jest.fn();
global.setCookie = jest.fn();
global.getCookie = jest.fn();
global.setInputFocus = jest.fn();
global.listModels = jest.fn().mockReturnValue('<option>model1</option>');
global.modelSpec = { 'gpt-4o': { reasoning_effort: 'high' } };

// Mock Audio constructor
global.Audio = jest.fn().mockImplementation(() => ({
  src: '',
  play: jest.fn().mockResolvedValue(undefined),
  pause: jest.fn(),
  load: jest.fn()
}));

// Mock MediaSource
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

// Mock URL methods
global.URL = {
  createObjectURL: jest.fn().mockReturnValue('blob:test'),
  revokeObjectURL: jest.fn()
};

// Mock Uint8Array for audio processing
global.Uint8Array = jest.fn();
global.Uint8Array.from = jest.fn().mockImplementation(() => new Array(10));

// Mock Base64 functions
global.atob = jest.fn().mockReturnValue('test-audio-data');
global.btoa = jest.fn().mockReturnValue('dGVzdC1hdWRpby1kYXRh');

// Mock XMLSerializer for SVG download
global.XMLSerializer = jest.fn().mockImplementation(() => ({
  serializeToString: jest.fn().mockReturnValue('<svg></svg>')
}));

// Mock Blob for file operations
global.Blob = jest.fn().mockImplementation(() => ({}));

// Mock navigator clipboard
if (!global.navigator) {
  global.navigator = {};
}
global.navigator.clipboard = {
  writeText: jest.fn().mockResolvedValue(undefined)
};

// Mock mids Set used in websocket.js
global.mids = new Set();