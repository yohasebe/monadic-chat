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

function createMockElement(id) {
  return {
    length: 1,
    0: document.createElement('div'),
    prop: jest.fn().mockReturnThis(),
    show: jest.fn().mockReturnThis(),
    hide: jest.fn().mockReturnThis(),
    html: jest.fn().mockReturnThis(),
    val: jest.fn(function(v) { if (v === undefined) return ''; return this; }),
    css: jest.fn().mockReturnThis(),
    empty: jest.fn().mockReturnThis(),
    attr: jest.fn().mockReturnThis(),
    find: jest.fn().mockReturnValue({
      length: 0,
      prop: jest.fn().mockReturnThis()
    }),
    last: jest.fn().mockReturnValue({
      find: jest.fn().mockReturnValue({ length: 0 }),
      attr: jest.fn().mockReturnValue('card-1')
    })
  };
}

let mockElements;

beforeEach(() => {
  mockElements = {
    '#monadic-spinner': createMockElement('monadic-spinner'),
    '#message': createMockElement('message'),
    '#temp-card': createMockElement('temp-card'),
    '#indicator': createMockElement('indicator'),
    '#user-panel': createMockElement('user-panel'),
    '#status-message': createMockElement('status-message'),
    '#discourse': createMockElement('discourse'),
    '#chat': createMockElement('chat'),
    '#select-role': createMockElement('select-role'),
    '#ai_user': createMockElement('ai_user'),
    '#send': createMockElement('send'),
    '#clear': createMockElement('clear'),
    '#send, #clear, #image-file, #voice, #doc, #url, #pdf-import, #ai_user': createMockElement('bulk'),
    '#monadic-spinner span': createMockElement('spinner-span'),
    '#discourse .card': createMockElement('discourse-card'),
    '#tool-status': createMockElement('tool-status')
  };

  // Make #discourse .card return something with .last()
  mockElements['#discourse .card'] = {
    length: 0,
    last: jest.fn().mockReturnValue({
      find: jest.fn().mockReturnValue({ length: 0 }),
      attr: jest.fn().mockReturnValue('card-1')
    })
  };

  global.$ = jest.fn().mockImplementation(selector => {
    if (typeof selector === 'string' && mockElements[selector]) {
      return mockElements[selector];
    }
    return createMockElement('default');
  });

  // Create cancel_query element in DOM
  const cancelBtn = document.createElement('div');
  cancelBtn.id = 'cancel_query';
  document.body.appendChild(cancelBtn);

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
      expect(mockElements['#temp-card'].hide).toHaveBeenCalled();
      expect(mockElements['#indicator'].hide).toHaveBeenCalled();
    });

    it('shows user-panel', () => {
      handlers.handleError({ content: 'error' });
      expect(mockElements['#user-panel'].show).toHaveBeenCalled();
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
      expect(mockElements['#message'].val).toHaveBeenCalledWith('my original message');
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
      handlers.handleCancel({});

      expect(mockElements['#send'].prop).toHaveBeenCalledWith('disabled', false);
      expect(mockElements['#clear'].prop).toHaveBeenCalledWith('disabled', false);
      expect(mockElements['#message'].prop).toHaveBeenCalledWith('disabled', false);
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
      expect(mockElements['#temp-card'].hide).toHaveBeenCalled();
      expect(mockElements['#indicator'].hide).toHaveBeenCalled();
    });

    it('hides spinner', () => {
      handlers.handleCancel({});
      expect(mockElements['#monadic-spinner'].css).toHaveBeenCalledWith('display', 'none');
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
      expect(mockElements['#discourse'].empty).toHaveBeenCalled();
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
