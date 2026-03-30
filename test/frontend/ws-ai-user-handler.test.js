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

function createDOMElement(tag, id, extras) {
  const el = document.createElement(tag);
  el.id = id;
  if (extras) Object.assign(el, extras);
  document.body.appendChild(el);
  return el;
}

beforeEach(() => {
  // Create DOM elements that the code queries via getElementById
  createDOMElement('div', 'monadic-spinner');
  document.getElementById('monadic-spinner').innerHTML = '<span></span>';
  createDOMElement('textarea', 'message');
  createDOMElement('button', 'send');
  createDOMElement('button', 'clear');
  createDOMElement('input', 'image-file');
  createDOMElement('button', 'voice');
  createDOMElement('button', 'doc');
  createDOMElement('button', 'url');
  createDOMElement('button', 'ai_user');
  createDOMElement('select', 'select-role');
  createDOMElement('button', 'pdf-import');
  createDOMElement('div', 'cancel_query');

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

    it('shows spinner', () => {
      handlers.handleAIUserStarted({});

      expect(document.getElementById('monadic-spinner').style.display).toBe('block');
    });

    it('disables all input elements', () => {
      handlers.handleAIUserStarted({});

      expect(document.getElementById('message').disabled).toBe(true);
      expect(document.getElementById('send').disabled).toBe(true);
      expect(document.getElementById('clear').disabled).toBe(true);
      expect(document.getElementById('voice').disabled).toBe(true);
      expect(document.getElementById('ai_user').disabled).toBe(true);
    });
  });

  describe('handleAIUser', () => {
    it('appends content to message field', () => {
      document.getElementById('message').value = 'existing ';

      handlers.handleAIUser({ content: 'new text' });

      expect(document.getElementById('message').value).toBe('existing new text');
    });

    it('converts escaped newlines to real newlines', () => {
      document.getElementById('message').value = '';

      handlers.handleAIUser({ content: 'line1\\nline2' });

      expect(document.getElementById('message').value).toBe('line1\nline2');
    });

    it('scrolls to main panel when auto scroll enabled and not in viewport', () => {
      global.isElementInViewport = jest.fn().mockReturnValue(false);
      global.mainPanel = { scrollIntoView: jest.fn() };
      document.getElementById('message').value = '';

      handlers.handleAIUser({ content: 'text' });

      expect(global.mainPanel.scrollIntoView).toHaveBeenCalledWith(false);
    });
  });

  describe('handleAIUserFinished', () => {
    it('sets trimmed content to message field', () => {
      handlers.handleAIUserFinished({ content: '  hello world  ' });

      expect(document.getElementById('message').value).toBe('hello world');
    });

    it('hides cancel button and spinner', () => {
      handlers.handleAIUserFinished({ content: 'done' });

      const cancelButton = document.getElementById('cancel_query');
      expect(cancelButton.style.display).toBe('none');
      expect(document.getElementById('monadic-spinner').style.display).toBe('none');
    });

    it('re-enables all input elements', () => {
      // Disable first
      document.getElementById('message').disabled = true;
      document.getElementById('send').disabled = true;
      document.getElementById('ai_user').disabled = true;

      handlers.handleAIUserFinished({ content: 'done' });

      expect(document.getElementById('message').disabled).toBe(false);
      expect(document.getElementById('send').disabled).toBe(false);
      expect(document.getElementById('ai_user').disabled).toBe(false);
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
