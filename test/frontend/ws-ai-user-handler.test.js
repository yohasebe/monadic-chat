/**
 * @jest-environment jsdom
 */

/**
 * Tests for ws-ai-user-handler.js
 *
 * Tests the AI User WebSocket message handlers:
 * - handleAIUserStarted: Disable UI and show generating spinner
 * - handleAIUser: Stream AI-generated user text into message field
 * - handleAIUserFinished: Re-enable UI with completed response
 */

function createMockElement(id) {
  return {
    prop: jest.fn().mockReturnThis(),
    val: jest.fn(function(v) { if (v === undefined) return ''; return this; }),
    html: jest.fn().mockReturnThis(),
    css: jest.fn().mockReturnThis(),
    show: jest.fn().mockReturnThis(),
    hide: jest.fn().mockReturnThis(),
    focus: jest.fn().mockReturnThis(),
    length: 1,
    0: document.createElement('div')
  };
}

let mockElements;

function setupMockElements() {
  mockElements = {
    '#message': createMockElement('message'),
    '#send': createMockElement('send'),
    '#clear': createMockElement('clear'),
    '#image-file': createMockElement('image-file'),
    '#voice': createMockElement('voice'),
    '#doc': createMockElement('doc'),
    '#url': createMockElement('url'),
    '#ai_user': createMockElement('ai_user'),
    '#select-role': createMockElement('select-role'),
    '#pdf-import': createMockElement('pdf-import'),
    '#monadic-spinner': createMockElement('monadic-spinner'),
    '#monadic-spinner span': createMockElement('monadic-spinner-span')
  };
}

beforeEach(() => {
  setupMockElements();

  global.$ = jest.fn().mockImplementation(selector => {
    if (typeof selector === 'string' && mockElements[selector]) {
      return mockElements[selector];
    }
    return createMockElement('default');
  });

  // Mock DOM elements for direct getElementById
  const cancelButton = document.createElement('div');
  cancelButton.id = 'cancel_query';
  cancelButton.style.display = 'none';
  document.body.appendChild(cancelButton);

  // Mock global functions
  global.getTranslation = jest.fn((key, fallback) => fallback);
  global.setAlert = jest.fn();
  global.isElementInViewport = jest.fn().mockReturnValue(true);
  global.setInputFocus = jest.fn();
  global.mainPanel = document.createElement('div');

  // Window globals
  window.autoScroll = true;
  window.webUIi18n = undefined;
});

afterEach(() => {
  jest.restoreAllMocks();
  document.body.innerHTML = '';
});

const handlers = require('../../docker/services/ruby/public/js/monadic/ws-ai-user-handler');

describe('ws-ai-user-handler', () => {
  describe('handleAIUserStarted', () => {
    it('shows warning alert with generating message', () => {
      handlers.handleAIUserStarted({});

      expect(global.setAlert).toHaveBeenCalledWith(
        expect.stringContaining('Generating AI user response'),
        'warning'
      );
    });

    it('shows cancel button', () => {
      handlers.handleAIUserStarted({});

      const cancelButton = document.getElementById('cancel_query');
      expect(cancelButton.style.display).toBe('flex');
    });

    it('shows spinner with robot icon', () => {
      handlers.handleAIUserStarted({});

      expect(mockElements['#monadic-spinner'].css).toHaveBeenCalledWith('display', 'block');
    });

    it('disables all input elements', () => {
      handlers.handleAIUserStarted({});

      expect(mockElements['#message'].prop).toHaveBeenCalledWith('disabled', true);
      expect(mockElements['#send'].prop).toHaveBeenCalledWith('disabled', true);
      expect(mockElements['#clear'].prop).toHaveBeenCalledWith('disabled', true);
      expect(mockElements['#voice'].prop).toHaveBeenCalledWith('disabled', true);
      expect(mockElements['#ai_user'].prop).toHaveBeenCalledWith('disabled', true);
    });
  });

  describe('handleAIUser', () => {
    it('appends content to message field', () => {
      mockElements['#message'].val = jest.fn(function(v) {
        if (v === undefined) return 'existing ';
        this._val = v;
        return this;
      });

      handlers.handleAIUser({ content: 'new text' });

      expect(mockElements['#message'].val).toHaveBeenCalledWith('existing new text');
    });

    it('converts escaped newlines to real newlines', () => {
      mockElements['#message'].val = jest.fn(function(v) {
        if (v === undefined) return '';
        this._val = v;
        return this;
      });

      handlers.handleAIUser({ content: 'line1\\nline2' });

      expect(mockElements['#message'].val).toHaveBeenCalledWith('line1\nline2');
    });

    it('scrolls to main panel when auto scroll enabled and not in viewport', () => {
      global.isElementInViewport = jest.fn().mockReturnValue(false);
      global.mainPanel = { scrollIntoView: jest.fn() };
      mockElements['#message'].val = jest.fn(function(v) {
        if (v === undefined) return '';
        return this;
      });

      handlers.handleAIUser({ content: 'text' });

      expect(global.mainPanel.scrollIntoView).toHaveBeenCalledWith(false);
    });
  });

  describe('handleAIUserFinished', () => {
    it('sets trimmed content to message field', () => {
      handlers.handleAIUserFinished({ content: '  hello world  ' });

      expect(mockElements['#message'].val).toHaveBeenCalledWith('hello world');
    });

    it('hides cancel button and spinner', () => {
      handlers.handleAIUserFinished({ content: 'done' });

      const cancelButton = document.getElementById('cancel_query');
      expect(cancelButton.style.display).toBe('none');
      expect(mockElements['#monadic-spinner'].css).toHaveBeenCalledWith('display', 'none');
    });

    it('re-enables all input elements', () => {
      handlers.handleAIUserFinished({ content: 'done' });

      expect(mockElements['#message'].prop).toHaveBeenCalledWith('disabled', false);
      expect(mockElements['#send'].prop).toHaveBeenCalledWith('disabled', false);
      expect(mockElements['#ai_user'].prop).toHaveBeenCalledWith('disabled', false);
    });

    it('shows success alert', () => {
      handlers.handleAIUserFinished({ content: 'done' });

      expect(global.setAlert).toHaveBeenCalledWith(
        expect.stringContaining('AI user response generated'),
        'success'
      );
    });

    it('focuses on input field', () => {
      handlers.handleAIUserFinished({ content: 'done' });

      expect(global.setInputFocus).toHaveBeenCalled();
    });
  });

  describe('module exports', () => {
    it('exports all three handlers', () => {
      expect(typeof handlers.handleAIUserStarted).toBe('function');
      expect(typeof handlers.handleAIUser).toBe('function');
      expect(typeof handlers.handleAIUserFinished).toBe('function');
    });

    it('exposes handlers on window.WsAIUserHandler', () => {
      expect(typeof window.WsAIUserHandler).toBe('object');
      expect(typeof window.WsAIUserHandler.handleAIUserStarted).toBe('function');
      expect(typeof window.WsAIUserHandler.handleAIUser).toBe('function');
      expect(typeof window.WsAIUserHandler.handleAIUserFinished).toBe('function');
    });
  });
});
