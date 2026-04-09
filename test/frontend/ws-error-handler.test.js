/**
 * @jest-environment jsdom
 */

/**
 * Tests for ws-error-handler.js
 *
 * Tests error and cancellation handlers:
 * - handleError: Error message processing, state reset, AI User error handling
 * - handleCancel: Operation cancellation, UI cleanup
 */

function createDOMElement(tag, id) {
  const el = document.createElement(tag);
  el.id = id;
  document.body.appendChild(el);
  return el;
}

beforeEach(() => {
  // Create DOM elements
  const spinner = createDOMElement('div', 'monadic-spinner');
  spinner.innerHTML = '<span></span>';
  createDOMElement('textarea', 'message');
  createDOMElement('div', 'temp-card');
  createDOMElement('div', 'indicator');
  createDOMElement('div', 'user-panel');
  createDOMElement('div', 'status-message');
  createDOMElement('div', 'discourse');
  createDOMElement('div', 'chat');
  createDOMElement('select', 'select-role');
  createDOMElement('button', 'ai_user');
  createDOMElement('button', 'send');
  createDOMElement('button', 'clear');
  createDOMElement('input', 'image-file');
  createDOMElement('button', 'voice');
  createDOMElement('button', 'doc');
  createDOMElement('button', 'url');
  createDOMElement('button', 'pdf-import');
  createDOMElement('div', 'cancel_query');

  // Mock global functions
  global.setAlert = jest.fn();
  global.getTranslation = jest.fn((key, fallback) => fallback);
  global.isSystemBusy = jest.fn().mockReturnValue(false);
  global.clearToolStatus = jest.fn();
  global.setInputFocus = jest.fn();
  global.deleteMessage = jest.fn();
  global.updateAIUserButtonState = jest.fn();
  global.WorkflowViewer = { setStage: jest.fn() };

  // Window globals
  window.streamingResponse = false;
  window.responseStarted = false;
  window.callingFunction = false;
  window.spinnerCheckInterval = null;
  window.UIState = { set: jest.fn() };
  window.SessionState = { removeMessage: jest.fn() };
  window.wsHandlers = null;
  window.messages = [];
  window.params = {};
  window.webUIi18n = undefined;
});

afterEach(() => {
  jest.restoreAllMocks();
  document.body.innerHTML = '';
});

const handlers = require('../../docker/services/ruby/public/js/monadic/ws-error-handler');

describe('ws-error-handler', () => {
  describe('handleError', () => {
    it('resets streaming state flags', () => {
      window.streamingResponse = true;
      window.responseStarted = true;
      window.callingFunction = true;

      handlers.handleError({ content: 'test error' });

      expect(window.streamingResponse).toBe(false);
      expect(window.responseStarted).toBe(false);
      expect(window.callingFunction).toBe(false);
    });

    it('clears spinner check interval', () => {
      const intervalId = 123;
      window.spinnerCheckInterval = intervalId;
      global.clearInterval = jest.fn();

      handlers.handleError({ content: 'test error' });

      expect(global.clearInterval).toHaveBeenCalledWith(intervalId);
      expect(window.spinnerCheckInterval).toBeNull();
    });

    it('updates UIState', () => {
      handlers.handleError({ content: 'test error' });

      expect(window.UIState.set).toHaveBeenCalledWith('streamingResponse', false);
      expect(window.UIState.set).toHaveBeenCalledWith('isStreaming', false);
    });

    it('shows error alert with string content', () => {
      handlers.handleError({ content: 'Something failed' });
      expect(global.setAlert).toHaveBeenCalledWith('Something failed', 'error');
    });

    it('translates known error keys', () => {
      handlers.handleError({ content: 'something_went_wrong' });
      expect(global.getTranslation).toHaveBeenCalledWith(
        'ui.messages.somethingWentWrong',
        'Something went wrong'
      );
    });

    it('handles structured AI User error object', () => {
      handlers.handleError({ content: { key: 'ai_user_error', details: 'timeout' } });
      expect(global.setAlert).toHaveBeenCalledWith(
        expect.stringContaining('AI User error'),
        'error'
      );
    });

    it('hides temp-card and indicator', () => {
      handlers.handleError({ content: 'error' });
      expect(document.getElementById('temp-card').style.display).toBe('none');
      expect(document.getElementById('indicator').style.display).toBe('none');
    });

    it('shows user-panel', () => {
      document.getElementById('user-panel').style.display = 'none';
      handlers.handleError({ content: 'error' });
      expect(document.getElementById('user-panel').style.display).toBe('');
    });

    it('sets WorkflowViewer stage to error', () => {
      handlers.handleError({ content: 'error' });
      expect(global.WorkflowViewer.setStage).toHaveBeenCalledWith('error');
    });

    it('calls setInputFocus', () => {
      handlers.handleError({ content: 'error' });
      expect(global.setInputFocus).toHaveBeenCalled();
    });

    it('restores message value from params for non-AI-User errors', () => {
      window.params = { message: 'my original message' };
      handlers.handleError({ content: 'error' });
      expect(document.getElementById('message').value).toBe('my original message');
    });

    it('delegates to wsHandlers.handleErrorMessage when available', () => {
      const mockHandler = jest.fn().mockReturnValue(true);
      window.wsHandlers = { handleErrorMessage: mockHandler };

      handlers.handleError({ content: 'test error' });

      expect(mockHandler).toHaveBeenCalled();
    });
  });

  describe('handleCancel', () => {
    it('re-enables UI elements', () => {
      document.getElementById('send').disabled = true;
      document.getElementById('clear').disabled = true;
      document.getElementById('message').disabled = true;

      handlers.handleCancel({});

      expect(document.getElementById('send').disabled).toBe(false);
      expect(document.getElementById('clear').disabled).toBe(false);
      expect(document.getElementById('message').disabled).toBe(false);
    });

    it('shows cancellation alert', () => {
      handlers.handleCancel({});
      expect(global.setAlert).toHaveBeenCalledWith(
        expect.stringContaining('Operation canceled'),
        'warning'
      );
    });

    it('hides temp-card and indicator', () => {
      handlers.handleCancel({});
      expect(document.getElementById('temp-card').style.display).toBe('none');
      expect(document.getElementById('indicator').style.display).toBe('none');
    });

    it('hides spinner', () => {
      handlers.handleCancel({});
      expect(document.getElementById('monadic-spinner').style.display).toBe('none');
    });

    it('calls clearToolStatus', () => {
      handlers.handleCancel({});
      expect(global.clearToolStatus).toHaveBeenCalled();
    });

    it('calls setInputFocus', () => {
      handlers.handleCancel({});
      expect(global.setInputFocus).toHaveBeenCalled();
    });

    it('calls updateAIUserButtonState', () => {
      handlers.handleCancel({});
      expect(global.updateAIUserButtonState).toHaveBeenCalled();
    });

    it('removes temporary messages from session', () => {
      window.messages = [{ text: 'hello' }, { text: 'temp', temp: true }];

      handlers.handleCancel({});

      expect(window.SessionState.removeMessage).toHaveBeenCalledWith(1);
    });

    it('empties discourse when no messages remain', () => {
      window.messages = [];
      handlers.handleCancel({});
      expect(document.getElementById('discourse').innerHTML).toBe('');
    });

    it('delegates to wsHandlers.handleCancelMessage when available', () => {
      const mockHandler = jest.fn().mockReturnValue(true);
      window.wsHandlers = { handleCancelMessage: mockHandler };

      handlers.handleCancel({});

      expect(mockHandler).toHaveBeenCalled();
      // When handler returns true, inline code should not run
      expect(global.setAlert).not.toHaveBeenCalled();
    });
  });

  describe('module exports', () => {
    it('exports both handlers', () => {
      expect(typeof handlers.handleError).toBe('function');
      expect(typeof handlers.handleCancel).toBe('function');
    });

    it('exposes handlers on window.WsErrorHandler', () => {
      expect(typeof window.WsErrorHandler).toBe('object');
    });
  });
});
