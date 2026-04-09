/**
 * @jest-environment jsdom
 */

/**
 * Tests for ws-html-handler.js
 *
 * Tests the "html" WebSocket message handler:
 * - handleHtml: Full message rendering (assistant, user, system roles)
 * - Assistant moreComing logic (tool call continuation)
 * - Auto Speech TTS triggering
 * - Streaming state management
 */

function createDOMElement(tag, id) {
  const el = document.createElement(tag);
  el.id = id;
  document.body.appendChild(el);
  return el;
}

beforeEach(() => {
  jest.useFakeTimers();

  // Create DOM elements
  const spinner = createDOMElement('div', 'monadic-spinner');
  spinner.innerHTML = '<span></span>';
  createDOMElement('textarea', 'message');
  createDOMElement('button', 'send');
  createDOMElement('button', 'clear');
  createDOMElement('input', 'image-file');
  createDOMElement('button', 'voice');
  createDOMElement('button', 'doc');
  createDOMElement('button', 'url');
  createDOMElement('button', 'pdf-import');
  createDOMElement('select', 'select-role');
  createDOMElement('div', 'temp-card');
  createDOMElement('div', 'indicator');
  createDOMElement('div', 'discourse');
  createDOMElement('div', 'chat');
  createDOMElement('div', 'user-panel');
  createDOMElement('div', 'cancel_query');

  // Mock global functions
  global.setAlert = jest.fn();
  global.isSystemBusy = jest.fn().mockReturnValue(false);
  global.setInputFocus = jest.fn();
  global.clearToolStatus = jest.fn();
  global.isElementInViewport = jest.fn().mockReturnValue(true);
  global.checkAndHideSpinner = jest.fn();
  global.renderThinkingBlock = jest.fn((content, title) => `<div class="thinking">${content}</div>`);
  global.isAutoSpeechSuppressed = jest.fn().mockReturnValue(false);
  global.setAutoSpeechSuppressed = jest.fn();
  global.scheduleAutoTtsSpinnerTimeout = jest.fn();
  global.resetAutoSpeechSpinner = jest.fn();

  // Window globals
  window.streamingResponse = true;
  window.callingFunction = false;
  window.responseStarted = true;
  window.UIState = { set: jest.fn() };
  window.spinnerCheckInterval = null;
  window.setTextResponseCompleted = jest.fn();
  window.setTtsPlaybackStarted = jest.fn();
  window.setReasoningStreamActive = jest.fn();
  window.checkAndHideSpinner = jest.fn();
  window.isForegroundTab = jest.fn().mockReturnValue(true);
  window.params = {};
  window.autoSpeechActive = false;
  window.ttsPlaybackStarted = false;
  window.debugWebSocket = false;
  window.webUIi18n = undefined;
  window.messages = [];
  window.SessionState = { addMessage: jest.fn(), removeMessage: jest.fn() };
  window.appendCard = jest.fn();
  window.mainPanel = document.createElement('div');
  window.wsHandlers = null;
  window.updateAIUserButtonState = jest.fn();
  window.WsAudioQueue = { setSequenceRetryCount: jest.fn(), getLastAutoTtsMessageId: jest.fn(), setLastAutoTtsMessageId: jest.fn() };
  window.highlightStopButton = jest.fn();
  window._lastProcessedIndex = 0;
  window._lastProcessedSequence = 0;
  window.autoPlayAudio = false;
  window.autoTTSSpinnerTimeout = null;
  window.MarkdownRenderer = null;
});

afterEach(() => {
  jest.useRealTimers();
  jest.restoreAllMocks();
  document.body.innerHTML = '';
});

const handlers = require('../../docker/services/ruby/public/js/monadic/ws-html-handler');

describe('ws-html-handler', () => {
  const assistantData = {
    content: {
      role: 'assistant',
      text: 'Hello world',
      html: '<p>Hello world</p>',
      mid: 'msg-1',
      lang: 'en'
    }
  };

  const userData = {
    content: {
      role: 'user',
      text: 'User message',
      html: '<p>User message</p>',
      mid: 'msg-2',
      lang: 'en'
    }
  };

  const systemData = {
    content: {
      role: 'system',
      text: 'System message',
      html: '<p>System message</p>',
      mid: 'msg-3',
      lang: 'en'
    }
  };

  describe('handleHtml - common behavior', () => {
    it('resets completion tracking flags', () => {
      handlers.handleHtml(assistantData);
      expect(window.setTextResponseCompleted).toHaveBeenCalledWith(false);
      expect(window.setTtsPlaybackStarted).toHaveBeenCalledWith(false);
    });

    it('resets sequence retry count', () => {
      handlers.handleHtml(assistantData);
      expect(window.WsAudioQueue.setSequenceRetryCount).toHaveBeenCalledWith(0);
    });

    it('adds message to SessionState', () => {
      handlers.handleHtml(assistantData);
      expect(window.SessionState.addMessage).toHaveBeenCalledWith(assistantData.content);
    });

    it('updates AI User button state', () => {
      handlers.handleHtml(assistantData);
      expect(window.updateAIUserButtonState).toHaveBeenCalled();
    });

    it('clears chat and hides temp-card after rendering', () => {
      document.getElementById('chat').innerHTML = '<p>old</p>';
      handlers.handleHtml(assistantData);
      expect(document.getElementById('chat').innerHTML).toBe('');
      expect(document.getElementById('temp-card').style.display).toBe('none');
    });

    it('shows user-panel', () => {
      document.getElementById('user-panel').style.display = 'none';
      handlers.handleHtml(assistantData);
      expect(document.getElementById('user-panel').style.display).toBe('');
    });

    it('calls setInputFocus', () => {
      handlers.handleHtml(assistantData);
      expect(global.setInputFocus).toHaveBeenCalled();
    });
  });

  describe('handleHtml - wsHandlers delegation', () => {
    it('delegates to wsHandlers.handleHtmlMessage when available', () => {
      const mockHandler = jest.fn().mockReturnValue(true);
      window.wsHandlers = { handleHtmlMessage: mockHandler };

      handlers.handleHtml(assistantData);

      expect(mockHandler).toHaveBeenCalledWith(assistantData, window.appendCard);
    });

    it('skips fallback when handler returns true', () => {
      window.wsHandlers = { handleHtmlMessage: jest.fn().mockReturnValue(true) };

      handlers.handleHtml(assistantData);

      expect(window.appendCard).not.toHaveBeenCalled();
    });

    it('uses fallback when handler returns false', () => {
      window.wsHandlers = { handleHtmlMessage: jest.fn().mockReturnValue(false) };

      handlers.handleHtml(assistantData);

      expect(window.appendCard).toHaveBeenCalled();
    });
  });

  describe('handleHtml - assistant role', () => {
    it('calls appendCard with assistant role', () => {
      handlers.handleHtml(assistantData);
      expect(window.appendCard).toHaveBeenCalledWith(
        'assistant',
        expect.stringContaining('Assistant'),
        '<p>Hello world</p>',
        'en',
        'msg-1',
        true,
        [],
        expect.any(Number)
      );
    });

    it('resets streaming state on final message', () => {
      handlers.handleHtml(assistantData);
      expect(window.UIState.set).toHaveBeenCalledWith('streamingResponse', false);
      expect(window.UIState.set).toHaveBeenCalledWith('isStreaming', false);
    });

    it('enables message input on final message', () => {
      document.getElementById('message').disabled = true;
      handlers.handleHtml(assistantData);
      expect(document.getElementById('message').disabled).toBe(false);
    });

    it('shows response received alert', () => {
      handlers.handleHtml(assistantData);
      expect(global.setAlert).toHaveBeenCalledWith(
        expect.stringContaining('Response received'),
        'success'
      );
    });

    it('hides cancel_query on final message', () => {
      handlers.handleHtml(assistantData);
      expect(document.getElementById('cancel_query').style.display).toBe('none');
    });
  });

  describe('handleHtml - assistant moreComing', () => {
    const moreComingData = {
      ...assistantData,
      more_coming: true
    };

    it('sets callingFunction when moreComing', () => {
      handlers.handleHtml(moreComingData);
      expect(window.callingFunction).toBe(true);
    });

    it('keeps streamingResponse true when moreComing', () => {
      handlers.handleHtml(moreComingData);
      expect(window.streamingResponse).toBe(true);
    });

    it('resets responseStarted for next streaming', () => {
      handlers.handleHtml(moreComingData);
      expect(window.responseStarted).toBe(false);
    });

    it('resets sequence tracking', () => {
      handlers.handleHtml(moreComingData);
      expect(window._lastProcessedSequence).toBe(-1);
      expect(window._lastProcessedIndex).toBe(-1);
    });

    it('shows spinner with processing tools message', () => {
      document.getElementById('monadic-spinner').style.display = 'none';
      handlers.handleHtml(moreComingData);
      expect(document.getElementById('monadic-spinner').style.display).toBe('');
    });

    it('keeps cancel button visible', () => {
      handlers.handleHtml(moreComingData);
      expect(document.getElementById('cancel_query').style.display).toBe('flex');
    });
  });

  describe('handleHtml - thinking/reasoning blocks', () => {
    it('renders thinking block when present', () => {
      const dataWithThinking = {
        content: {
          ...assistantData.content,
          thinking: 'I am thinking...'
        }
      };
      handlers.handleHtml(dataWithThinking);
      expect(global.renderThinkingBlock).toHaveBeenCalledWith('I am thinking...', 'Thinking Process');
    });

    it('renders reasoning block when present', () => {
      const dataWithReasoning = {
        content: {
          ...assistantData.content,
          reasoning_content: 'My reasoning...'
        }
      };
      handlers.handleHtml(dataWithReasoning);
      expect(global.renderThinkingBlock).toHaveBeenCalledWith('My reasoning...', 'Reasoning Process');
    });

    it('uses MarkdownRenderer when html field is missing', () => {
      window.MarkdownRenderer = { render: jest.fn().mockReturnValue('<p>rendered</p>') };
      const dataNoHtml = {
        content: {
          role: 'assistant',
          text: 'Plain text',
          mid: 'msg-10',
          lang: 'en',
          app_name: 'TestApp'
        }
      };
      handlers.handleHtml(dataNoHtml);
      expect(window.MarkdownRenderer.render).toHaveBeenCalledWith('Plain text', { appName: 'TestApp' });
    });
  });

  describe('handleHtml - user role', () => {
    it('calls appendCard with user role', () => {
      handlers.handleHtml(userData);
      expect(window.appendCard).toHaveBeenCalledWith(
        'user',
        expect.stringContaining('User'),
        expect.stringContaining('User message'),
        'en',
        'msg-2',
        true,
        undefined,
        expect.any(Number)
      );
    });

    it('resets streaming state', () => {
      handlers.handleHtml(userData);
      expect(window.streamingResponse).toBe(false);
    });

    it('clears spinner check interval', () => {
      const intervalId = 42;
      window.spinnerCheckInterval = intervalId;
      global.clearInterval = jest.fn();

      handlers.handleHtml(userData);

      expect(global.clearInterval).toHaveBeenCalledWith(intervalId);
      expect(window.spinnerCheckInterval).toBeNull();
    });

    it('shows ready alert when not busy', () => {
      handlers.handleHtml(userData);
      expect(global.setAlert).toHaveBeenCalledWith(
        expect.stringContaining('Ready for input'),
        'success'
      );
    });
  });

  describe('handleHtml - system role', () => {
    it('calls appendCard with system role', () => {
      handlers.handleHtml(systemData);
      expect(window.appendCard).toHaveBeenCalledWith(
        'system',
        expect.stringContaining('System'),
        '<p>System message</p>',
        'en',
        'msg-3',
        true
      );
    });

    it('resets streaming state', () => {
      handlers.handleHtml(systemData);
      expect(window.streamingResponse).toBe(false);
    });

    it('hides cancel button', () => {
      handlers.handleHtml(systemData);
      expect(document.getElementById('cancel_query').style.display).toBe('none');
    });
  });

  describe('handleHtml - Auto Speech', () => {
    it('does not trigger auto speech by default', () => {
      handlers.handleHtml(assistantData);
      jest.advanceTimersByTime(200);
      expect(window.highlightStopButton).not.toHaveBeenCalled();
    });

    it('triggers auto speech when enabled in params', () => {
      window.params = { auto_speech: true };
      window.autoSpeechActive = true;

      handlers.handleHtml(assistantData);
      jest.advanceTimersByTime(200);

      expect(global.scheduleAutoTtsSpinnerTimeout).toHaveBeenCalled();
    });

    it('skips auto speech for duplicate message IDs', () => {
      window.params = { auto_speech: true };
      window.autoSpeechActive = true;
      window.WsAudioQueue.getLastAutoTtsMessageId.mockReturnValue('msg-1');

      handlers.handleHtml(assistantData);

      expect(window.autoSpeechActive).toBe(false);
    });

    it('suppresses auto speech in background tab', () => {
      window.params = { auto_speech: true };
      window.isForegroundTab = jest.fn().mockReturnValue(false);

      handlers.handleHtml(assistantData);

      expect(global.setAutoSpeechSuppressed).toHaveBeenCalledWith(true, expect.objectContaining({ reason: 'background_tab' }));
    });

    it('handles suppression active state', () => {
      window.params = { auto_speech: true };
      global.isAutoSpeechSuppressed.mockReturnValue(true);

      handlers.handleHtml(assistantData);

      expect(window.autoSpeechActive).toBe(false);
      expect(window.autoPlayAudio).toBe(false);
    });
  });

  describe('module exports', () => {
    it('exports handleHtml', () => {
      expect(typeof handlers.handleHtml).toBe('function');
    });

    it('exposes on window.WsHtmlHandler', () => {
      expect(typeof window.WsHtmlHandler).toBe('object');
      expect(typeof window.WsHtmlHandler.handleHtml).toBe('function');
    });
  });
});
