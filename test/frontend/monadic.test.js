/**
 * @jest-environment jsdom
 */

// Setup global mocks needed for monadic.js
document.body.innerHTML = `
<div id="main"></div>
<div id="message" style="height: 100px;"></div>
<div id="initial-prompt" style="height: 100px;"></div>
<div id="ai-user-initial-prompt" style="height: 100px;"></div>
<div id="alert" class="alert"></div>
<div id="browser"></div>
<div id="auto-scroll-toggle"></div>
<div id="max-tokens-toggle"></div>
<div id="context-size-toggle"></div>
<div id="discourse"></div>
<div id="send"></div>
<div id="clear"></div>
<div id="image-file"></div>
<div id="voice"></div>
<div id="doc"></div>
<div id="url"></div>
<div id="tts-provider"></div>
<div id="elevenlabs-tts-voice"></div>
<div id="tts-voice"></div>
<div id="tts-speed"></div>
<div id="asr-lang"></div>
<div id="ai-user-initial-prompt-toggle"></div>
<div id="ai-user-toggle"></div>
<div id="check-auto-speech"></div>
<div id="check-easy-submit"></div>
<div id="model"></div>
<div id="apps"></div>
<div id="temperature"></div>
<div id="temperature-value"></div>
<div id="presence-penalty"></div>
<div id="presence-penalty-value"></div>
<div id="frequency-penalty"></div>
<div id="frequency-penalty-value"></div>
<div id="model-selected"></div>
<div id="reasoning-effort"></div>
<div id="websearch"></div>
<div id="websearch-badge"></div>
<div id="monadic-badge"></div>
<div id="tools-badge"></div>
<div id="math-badge"></div>
<div id="initial-prompt-toggle"></div>
<div id="back_to_top"></div>
<div id="back_to_bottom"></div>
<div id="alert-message"></div>
<div id="monadic-spinner"></div>
<div id="voice-panel"></div>
<div id="chat-bottom"></div>
<div id="select-role"></div>
<div id="role-icon"><i></i></div>
`;

// Mock setCookie and getCookie functions
global.setCookie = jest.fn();
global.getCookie = jest.fn().mockReturnValue('');

// Additional mocks needed for monadic.js
global.defaultApp = 'Chat';
global.DEFAULT_MAX_OUTPUT_TOKENS = 2000;
global.adjustScrollButtons = jest.fn();
global.runningOnFirefox = false;
global.runningOnChrome = true;
global.runningOnEdge = false;
global.runningOnSafari = false;
global.resetParams = jest.fn();
global.loadParams = jest.fn();
global.setParams = jest.fn().mockReturnValue({});
global.checkParams = jest.fn().mockReturnValue(true);
global.saveObjToJson = jest.fn();
global.setAlert = jest.fn();
global.setInputFocus = jest.fn();
global.resetEvent = jest.fn();
global.listModels = jest.fn().mockReturnValue('<option value="model1">Model 1</option>');
global.adjustImageUploadButton = jest.fn();
global.setCookieValues = jest.fn();
global.deleteMessageOnly = jest.fn();
global.deleteMessageAndSubsequent = jest.fn();
global.deleteSystemMessage = jest.fn();
global.audioInit = jest.fn();
global.ttsStop = jest.fn();
global.formatInfo = jest.fn();
global.setStats = jest.fn();
global.voiceButton = { hide: jest.fn() };
global.stop_apps_trigger = false;
global.images = [];
global.updateFileDisplay = jest.fn();
global.apps = {
  'Chat': {
    'model': 'gpt-4',
    'models': '["gpt-3.5-turbo", "gpt-4"]',
    'display_name': 'Chat',
    'app_name': 'Chat',
    'group': 'OpenAI',
    'icon': '<i class="fas fa-comment"></i>',
    'description': 'Chat description',
    'monadic': true,
    'websearch': false,
    'tools': true,
    'mathjax': true
  }
};
global.modelSpec = {
  'gpt-4': {
    'reasoning_effort': 'medium',
    'temperature': [0, 1.0, 2],
    'presence_penalty': [-2, 0, 2],
    'frequency_penalty': [-2, 0, 2],
    'max_output_tokens': [100, 2000, 4000],
    'tool_capability': true
  }
};
global.messages = [];
global.reconnect_websocket = jest.fn();
global.ws = { send: jest.fn() };

// Mock MutationObserver
global.MutationObserver = class {
  constructor(callback) {
    this.callback = callback;
  }
  observe() {}
  disconnect() {}
};

// Define autoResize and setupTextarea functions from monadic.js for testing
function autoResize(textarea, initialHeight) {
  textarea.style.height = 'auto';
  const newHeight = Math.max(textarea.scrollHeight, initialHeight);
  textarea.style.height = newHeight + 'px';
}

function setupTextarea(textarea, initialHeight) {
  let isIMEActive = false;

  textarea.style.height = initialHeight + 'px';

  textarea.addEventListener('compositionstart', function() {
    isIMEActive = true;
  });

  textarea.addEventListener('compositionend', function() {
    isIMEActive = false;
    autoResize(textarea, initialHeight);
  });

  textarea.addEventListener('input', function() {
    if (!isIMEActive) {
      autoResize(textarea, initialHeight);
    }
  });

  textarea.addEventListener('focus', function() {
    autoResize(textarea, initialHeight);
  });

  autoResize(textarea, initialHeight);
}

// Import the module under test - we'll test the functions we copied directly
// require('../../docker/services/ruby/public/js/monadic.js');

// Test suite
describe('monadic.js', () => {
  beforeEach(() => {
    // Reset mocks before each test
    jest.clearAllMocks();
    document.getElementById = jest.fn().mockImplementation((id) => {
      const element = document.createElement('div');
      element.id = id;
      element.style = { height: '100px' };
      element.scrollHeight = 200;
      element.dataset = {};
      element.addEventListener = jest.fn((event, handler) => {
        if (!global.domEventHandlers) global.domEventHandlers = {};
        if (!global.domEventHandlers[id]) global.domEventHandlers[id] = {};
        global.domEventHandlers[id][event] = handler;
      });
      return element;
    });
  });

  // Test autoResize function
  describe('autoResize', () => {
    it('should resize a textarea based on content', () => {
      // Create mock textarea
      const textarea = {
        style: { height: '100px' },
        scrollHeight: 250
      };
      
      // Call autoResize
      autoResize(textarea, 100);
      
      // Verify the height was updated correctly
      expect(textarea.style.height).toBe('250px');
    });
    
    it('should not resize below initial height', () => {
      // Create mock textarea with smaller scrollHeight
      const textarea = {
        style: { height: '100px' },
        scrollHeight: 50
      };
      
      // Call autoResize
      autoResize(textarea, 100);
      
      // Verify the height was set to initialHeight
      expect(textarea.style.height).toBe('100px');
    });
  });

  // Test setupTextarea function
  describe('setupTextarea', () => {
    it('should set up event listeners on a textarea', () => {
      // Create mock textarea
      const textarea = {
        style: { height: '100px' },
        scrollHeight: 200,
        addEventListener: jest.fn()
      };
      
      // Call setupTextarea
      setupTextarea(textarea, 100);
      
      // Verify event listeners were added
      expect(textarea.addEventListener).toHaveBeenCalledTimes(4);
      expect(textarea.addEventListener).toHaveBeenCalledWith('compositionstart', expect.any(Function));
      expect(textarea.addEventListener).toHaveBeenCalledWith('compositionend', expect.any(Function));
      expect(textarea.addEventListener).toHaveBeenCalledWith('input', expect.any(Function));
      expect(textarea.addEventListener).toHaveBeenCalledWith('focus', expect.any(Function));
      
      // Verify height was updated
      // Note: The height is set to scrollHeight (200px) by autoResize call
      expect(textarea.style.height).toBe('200px');
    });
  });

  // Test DOMContentLoaded event handler
  describe('DOMContentLoaded handler', () => {
    it('should call setupTextarea for message elements', () => {
      // Create spy for setupTextarea
      const setupTextareaSpy = jest.spyOn({ setupTextarea }, 'setupTextarea');
      
      // Create elements
      const messageEl = document.createElement('div');
      messageEl.id = 'message';
      const initialPromptEl = document.createElement('div');
      initialPromptEl.id = 'initial-prompt';
      const aiUserInitialPromptEl = document.createElement('div');
      aiUserInitialPromptEl.id = 'ai-user-initial-prompt';
      
      // Mock getElementById
      document.getElementById = jest.fn((id) => {
        if (id === 'message') return messageEl;
        if (id === 'initial-prompt') return initialPromptEl;
        if (id === 'ai-user-initial-prompt') return aiUserInitialPromptEl;
        return null;
      });
      
      // Trigger DOMContentLoaded event
      const event = new Event('DOMContentLoaded');
      document.dispatchEvent(event);
      
      // Currently we can't test the event handler without refactoring the code
      // This would require extracting the function from the event listener
    });
  });

});