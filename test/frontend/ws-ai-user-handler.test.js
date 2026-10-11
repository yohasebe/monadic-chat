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
  let rid;
  beforeEach(() => { rid = handlers.beginRequest(); });

  describe('handleAIUserStarted', () => {
    it('shows warning alert with generating message', () => {
      handlers.handleAIUserStarted({ request_id: rid });

      expect(global.setAlert).toHaveBeenCalledWith(
        expect.stringContaining('Generating AI user response'),
        'warning'
      );
    });

    it('shows cancel button', () => {
      handlers.handleAIUserStarted({ request_id: rid });

      const cancelButton = document.getElementById('cancel_query');
      expect(cancelButton.style.display).toBe('flex');
    });

    it('shows spinner', () => {
      handlers.handleAIUserStarted({ request_id: rid });

      expect(document.getElementById('monadic-spinner').style.display).toBe('block');
    });

    it('disables all input elements', () => {
      handlers.handleAIUserStarted({ request_id: rid });

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

      handlers.handleAIUser({ request_id: rid, content: 'new text' });

      expect(document.getElementById('message').value).toBe('existing new text');
    });

    it('converts escaped newlines to real newlines', () => {
      document.getElementById('message').value = '';

      handlers.handleAIUser({ request_id: rid, content: 'line1\\nline2' });

      expect(document.getElementById('message').value).toBe('line1\nline2');
    });

    it('scrolls to main panel when auto scroll enabled and not in viewport', () => {
      global.isElementInViewport = jest.fn().mockReturnValue(false);
      global.mainPanel = { scrollIntoView: jest.fn() };
      document.getElementById('message').value = '';

      handlers.handleAIUser({ request_id: rid, content: 'text' });

      expect(global.mainPanel.scrollIntoView).toHaveBeenCalledWith(false);
    });
  });

  describe('handleAIUserFinished', () => {
    it('sets trimmed content to message field', () => {
      handlers.handleAIUserFinished({ request_id: rid, content: '  hello world  ' });

      expect(document.getElementById('message').value).toBe('hello world');
    });

    it('hides cancel button and spinner', () => {
      handlers.handleAIUserFinished({ request_id: rid, content: 'done' });

      const cancelButton = document.getElementById('cancel_query');
      expect(cancelButton.style.display).toBe('none');
      expect(document.getElementById('monadic-spinner').style.display).toBe('none');
    });

    it('re-enables all input elements', () => {
      // Disable first
      document.getElementById('message').disabled = true;
      document.getElementById('send').disabled = true;
      document.getElementById('ai_user').disabled = true;

      handlers.handleAIUserFinished({ request_id: rid, content: 'done' });

      expect(document.getElementById('message').disabled).toBe(false);
      expect(document.getElementById('send').disabled).toBe(false);
      expect(document.getElementById('ai_user').disabled).toBe(false);
    });

    it('shows success alert', () => {
      handlers.handleAIUserFinished({ request_id: rid, content: 'done' });

      expect(global.setAlert).toHaveBeenCalledWith(
        expect.stringContaining('AI user response generated'),
        'success'
      );
    });

    it('focuses on input field', () => {
      handlers.handleAIUserFinished({ request_id: rid, content: 'done' });

      expect(global.setInputFocus).toHaveBeenCalled();
    });
  });

  describe('abandonAIUser (Reset while a suggestion is being written)', () => {
    it('gives the controls back and leaves the new chat\'s input box alone', () => {
      handlers.handleAIUserStarted({ request_id: rid });
      const message = document.getElementById('message');
      message.value = 'a draft for the new chat';
      global.setAlert.mockClear();

      handlers.abandonAIUser();

      expect(message.value).toBe('a draft for the new chat');
      expect(message.disabled).toBe(false);
      expect(document.getElementById('send').disabled).toBe(false);
      expect(document.getElementById('cancel_query').style.display).toBe('none');
      expect(global.setAlert).not.toHaveBeenCalled();
    });

    it('does nothing when no suggestion is being written', () => {
      handlers.handleAIUserStarted({ request_id: rid });
      handlers.handleAIUserFinished({ request_id: rid, content: 'done' });
      const send = document.getElementById('send');
      send.disabled = true; // locked by something else since

      handlers.abandonAIUser();

      expect(send.disabled).toBe(true);
    });
  });

  describe('a suggestion given up at Reset or app switch', () => {
    it('cannot fill the input box or unlock the controls when its notices arrive later', () => {
      handlers.handleAIUserStarted({ request_id: rid });
      handlers.abandonAIUser();
      const message = document.getElementById('message');
      message.value = 'a draft for the new chat';
      const send = document.getElementById('send');
      send.disabled = true; // locked by a reply in the new chat

      handlers.handleAIUser({ request_id: rid, content: 'old suggestion' });
      handlers.handleAIUserFinished({ request_id: rid, content: 'old suggestion' });

      expect(message.value).toBe('a draft for the new chat');
      expect(send.disabled).toBe(true);
    });

    it('is told apart from a new request made after it', () => {
      const old = rid;
      handlers.abandonAIUser();
      const fresh = handlers.beginRequest();
      handlers.handleAIUserStarted({ request_id: fresh });

      handlers.handleAIUserFinished({ request_id: old, content: 'old suggestion' });
      expect(document.getElementById('message').value).toBe('');
      handlers.handleAIUserFinished({ request_id: fresh, content: 'new suggestion' });
      expect(document.getElementById('message').value).toBe('new suggestion');
    });

    it('ignores notices without a request id', () => {
      handlers.handleAIUserFinished({ content: 'from nowhere' });
      expect(document.getElementById('message').value).toBe('');
    });
  });

  describe('errors and the request they belong to', () => {
    it('ends the current request on its error, leaving the input box as it is', () => {
      handlers.handleAIUserStarted({ request_id: rid });
      const message = document.getElementById('message');
      message.value = 'kept';
      handlers.handleAIUserError({ request_id: rid, content: 'AI User error: quota' });
      expect(message.value).toBe('kept');
      expect(document.getElementById('send').disabled).toBe(false);
      expect(handlers.isWaiting()).toBe(false);
      expect(global.setAlert).toHaveBeenLastCalledWith(expect.stringContaining('AI User error: quota'), 'error');
    });

    it('ignores the error of a request given up already', () => {
      handlers.handleAIUserStarted({ request_id: rid });
      handlers.abandonAIUser();
      const send = document.getElementById('send');
      send.disabled = true; // locked by something in the next chat
      global.setAlert.mockClear();
      handlers.handleAIUserError({ request_id: rid, content: 'AI User error: late' });
      expect(send.disabled).toBe(true);
      expect(global.setAlert).not.toHaveBeenCalled();
    });

    it('shows the error text as text', () => {
      handlers.handleAIUserError({ request_id: rid, content: '<img src=x onerror=alert(1)>' });
      expect(global.setAlert).toHaveBeenLastCalledWith(expect.stringContaining('&lt;img'), 'error');
    });
  });

  describe('one request at a time', () => {
    it('is waiting from the press of the button until the request ends', () => {
      expect(handlers.isWaiting()).toBe(true);
      handlers.handleAIUserFinished({ request_id: rid, content: 'done' });
      expect(handlers.isWaiting()).toBe(false);
    });

    it('gives the controls back when given up before the server started', () => {
      const send = document.getElementById('send');
      send.disabled = true; // locked by the button itself
      handlers.abandonAIUser();
      expect(send.disabled).toBe(false);
      expect(handlers.isWaiting()).toBe(false);
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
