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

    it('gives back the typed text and the attachments of the message, not the lines added for the model', () => {
      window.params = { message: 'look\n\nAttached video: a.mp4 (attachment_id: a_1)' };
      window.pendingSend = { text: 'look', attachments: [{ attachment_id: 'a_1', name: 'a.mp4' }], images: [{ title: 'shot.png' }] };
      window.restoreVideoAttachments = jest.fn();
      window.restoreImages = jest.fn();
      handlers.handleError({ content: 'error' });
      expect(document.getElementById('message').value).toBe('look');
      expect(window.restoreImages).toHaveBeenCalledWith([{ title: 'shot.png' }]);
      delete window.restoreImages;
      expect(window.restoreVideoAttachments).toHaveBeenCalledWith([{ attachment_id: 'a_1', name: 'a.mp4' }]);
      expect(window.pendingSend).toBeNull();
      delete window.restoreVideoAttachments;
    });

    it('gives a refused sample back with its role, and stops its time limit', () => {
      const role = document.getElementById('select-role');
      role.innerHTML = '<option value="user">user</option><option value="sample-assistant">assistant</option>';
      role.value = 'user';
      const changed = jest.fn();
      role.addEventListener('change', changed);
      window.pendingSend = { text: 'I am Bob', role: 'sample-assistant', attachments: [], images: [] };
      const timedOut = jest.fn();
      window.currentSampleTimeout = setTimeout(timedOut, 10);
      handlers.handleError({ content: 'Nothing was sent.', not_accepted: true });
      expect(role.value).toBe('sample-assistant');
      expect(changed).toHaveBeenCalledTimes(1);
      expect(document.getElementById('message').value).toBe('I am Bob');
      expect(window.currentSampleTimeout).toBeNull();
      return new Promise(resolve => setTimeout(resolve, 30)).then(() => expect(timedOut).not.toHaveBeenCalled());
    });

    it('keeps the last card when the server did not accept the message (it was never shown)', () => {
      const discourse = document.getElementById('discourse');
      discourse.innerHTML = '<div class="card" id="m-earlier"><span class="user-color">User</span></div>';
      handlers.handleError({ content: 'An attached file is not known to this chat.', not_accepted: true });
      expect(global.deleteMessage).not.toHaveBeenCalled();
      handlers.handleError({ content: 'error' });
      expect(global.deleteMessage).toHaveBeenCalledWith('m-earlier');
      discourse.innerHTML = '';
    });

    it('when an answer is still running (busy), gives the send back and leaves that answer on screen', () => {
      const discourse = document.getElementById('discourse');
      discourse.innerHTML = '<div class="card" id="m-running"><span class="user-color">User</span></div>';
      document.getElementById('temp-card').style.display = '';
      window.streamingResponse = true;
      window.pendingSend = { text: 'and this', attachments: [{ attachment_id: 'a_2', name: 'b.mp4' }], images: [{ title: 'shot.png' }] };
      window.restoreVideoAttachments = jest.fn();
      window.restoreImages = jest.fn();
      handlers.handleError({ content: 'answer_still_running', not_accepted: true, busy: true });
      expect(document.getElementById('message').value).toBe('and this');
      expect(window.restoreImages).toHaveBeenCalledWith([{ title: 'shot.png' }]);
      expect(window.restoreVideoAttachments).toHaveBeenCalledWith([{ attachment_id: 'a_2', name: 'b.mp4' }]);
      expect(window.pendingSend).toBeNull();
      expect(global.setAlert).toHaveBeenCalledWith(expect.stringContaining('still running'), 'warning');
      expect(window.streamingResponse).toBe(true);
      expect(document.getElementById('temp-card').style.display).toBe('');
      expect(global.deleteMessage).not.toHaveBeenCalled();
      expect(global.WorkflowViewer.setStage).not.toHaveBeenCalled();
      delete window.restoreVideoAttachments;
      delete window.restoreImages;
      discourse.innerHTML = '';
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

/**
 * Voice-capture recovery on error.
 *
 * Observed live: an STS turn that dies between AUDIO_COMMIT and its stt/audio
 * events (upstream realtime session hits its 60-minute cap) left the mic UI
 * stranded on "Processing speech..." — the generic reset hid the spinner but
 * an armed auto-speech watchdog re-showed it. The error path must disarm the
 * watchdogs and hide the spinner last.
 */
describe('handleError voice-capture recovery', () => {
  beforeEach(() => {
    const spinner = document.createElement('div');
    spinner.id = 'monadic-spinner';
    document.body.appendChild(spinner);
    const amp = document.createElement('div');
    amp.id = 'amplitude';
    document.body.appendChild(amp);
    window.autoSpeechActive = true;
    window.autoPlayAudio = true;
    window.autoTTSSpinnerTimeout = setTimeout(() => {}, 60000);
  });

  afterEach(() => {
    ['monadic-spinner', 'amplitude'].forEach(id => document.getElementById(id)?.remove());
    delete window.autoSpeechActive;
    delete window.autoPlayAudio;
    if (window.autoTTSSpinnerTimeout) { clearTimeout(window.autoTTSSpinnerTimeout); delete window.autoTTSSpinnerTimeout; }
  });

  it('disarms auto-speech watchdogs and hides the spinner', () => {
    handlers.handleError({ type: 'error', content: 'Speech-to-speech: session expired' });

    expect(window.autoSpeechActive).toBe(false);
    expect(window.autoPlayAudio).toBe(false);
    expect(window.autoTTSSpinnerTimeout).toBeNull();
    expect(document.getElementById('monadic-spinner').style.display).toBe('none');
    expect(document.getElementById('amplitude').style.display).toBe('none');
  });
});
