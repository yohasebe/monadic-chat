/**
 * @jest-environment jsdom
 */

/**
 * Tests for ws-streaming-handler.js
 *
 * Tests streaming lifecycle handlers:
 * - handleStreamingComplete: State reset, spinner management, ready status
 */

function createMockElement(id) {
  return {
    length: 1,
    0: document.createElement('div'),
    hide: jest.fn().mockReturnThis(),
    show: jest.fn().mockReturnThis(),
    prop: jest.fn().mockReturnThis(),
    is: jest.fn().mockReturnValue(false),
    html: jest.fn().mockReturnThis()
  };
}

let mockElements;

beforeEach(() => {
  jest.useFakeTimers();

  mockElements = {
    '#monadic-spinner': createMockElement('monadic-spinner'),
    '#monadic-spinner span': createMockElement('spinner-span'),
    '#check-auto-speech': createMockElement('check-auto-speech'),
    '#message': createMockElement('message'),
    '#send, #clear, #image-file, #voice, #doc, #url, #pdf-import': createMockElement('buttons'),
    '#select-role': createMockElement('select-role')
  };

  global.$ = jest.fn().mockImplementation(selector => {
    if (typeof selector === 'string' && mockElements[selector]) {
      return mockElements[selector];
    }
    return createMockElement('default');
  });

  // Mock global functions
  global.setAlert = jest.fn();
  global.isSystemBusy = jest.fn().mockReturnValue(false);
  global.setInputFocus = jest.fn();

  // Window globals
  window.streamingResponse = true;
  window.callingFunction = false;
  window.UIState = { set: jest.fn() };
  window.spinnerCheckInterval = null;
  window.setTextResponseCompleted = jest.fn();
  window.checkAndHideSpinner = jest.fn();
  window.isForegroundTab = jest.fn().mockReturnValue(true);
  window.params = {};
  window.autoSpeechActive = false;
  window.ttsPlaybackStarted = false;
  window.debugWebSocket = false;
  window.resetSequenceTracking = jest.fn();
  window.webUIi18n = undefined;
});

afterEach(() => {
  jest.useRealTimers();
  jest.restoreAllMocks();
});

const handlers = require('../../docker/services/ruby/public/js/monadic/ws-streaming-handler');

describe('ws-streaming-handler', () => {
  describe('handleStreamingComplete', () => {
    it('resets streamingResponse to false', () => {
      handlers.handleStreamingComplete({});
      expect(window.streamingResponse).toBe(false);
    });

    it('updates UIState', () => {
      handlers.handleStreamingComplete({});
      expect(window.UIState.set).toHaveBeenCalledWith('streamingResponse', false);
      expect(window.UIState.set).toHaveBeenCalledWith('isStreaming', false);
    });

    it('clears spinner check interval', () => {
      const intervalId = 42;
      window.spinnerCheckInterval = intervalId;
      global.clearInterval = jest.fn();

      handlers.handleStreamingComplete({});

      expect(global.clearInterval).toHaveBeenCalledWith(intervalId);
      expect(window.spinnerCheckInterval).toBeNull();
    });

    it('marks text response as completed', () => {
      handlers.handleStreamingComplete({});
      expect(window.setTextResponseCompleted).toHaveBeenCalledWith(true);
    });

    it('calls checkAndHideSpinner when not auto speech', () => {
      handlers.handleStreamingComplete({});
      expect(window.checkAndHideSpinner).toHaveBeenCalled();
    });

    it('does not hide spinner when auto speech is enabled', () => {
      window.params = { auto_speech: true };
      window.ttsPlaybackStarted = false;

      handlers.handleStreamingComplete({});

      expect(window.checkAndHideSpinner).not.toHaveBeenCalled();
    });

    it('shows ready alert after delay when system not busy', () => {
      handlers.handleStreamingComplete({});

      // Alert not shown yet (delayed)
      expect(global.setAlert).not.toHaveBeenCalled();

      // Advance timers
      jest.advanceTimersByTime(250);

      expect(global.setAlert).toHaveBeenCalledWith(
        expect.stringContaining('Ready for input'),
        'success'
      );
    });

    it('enables message input after delay', () => {
      handlers.handleStreamingComplete({});
      jest.advanceTimersByTime(250);

      expect(mockElements['#message'].prop).toHaveBeenCalledWith('disabled', false);
    });

    it('calls setInputFocus after delay', () => {
      handlers.handleStreamingComplete({});
      jest.advanceTimersByTime(250);

      expect(global.setInputFocus).toHaveBeenCalled();
    });

    it('resets sequence tracking after delay', () => {
      handlers.handleStreamingComplete({});
      jest.advanceTimersByTime(250);

      expect(window.resetSequenceTracking).toHaveBeenCalled();
    });

    it('does not hide spinner when callingFunction is true', () => {
      window.callingFunction = true;

      handlers.handleStreamingComplete({});

      expect(window.checkAndHideSpinner).not.toHaveBeenCalled();
      expect(window.setTextResponseCompleted).not.toHaveBeenCalled();
    });
  });

  describe('handleDefaultMessage', () => {
    beforeEach(() => {
      window.handleFragmentMessage = jest.fn();
      global.isElementInViewport = jest.fn().mockReturnValue(true);
      global.WorkflowViewer = { setStage: jest.fn() };
      window.autoScroll = false;
      window.chatBottom = null;
    });

    describe('fragment type', () => {
      it('sets responseStarted on first fragment', () => {
        window.responseStarted = false;
        handlers.handleDefaultMessage({ type: 'fragment', content: 'Hello' });
        expect(window.responseStarted).toBe(true);
      });

      it('sets streamingResponse on first fragment', () => {
        window.responseStarted = false;
        handlers.handleDefaultMessage({ type: 'fragment', content: 'Hello' });
        expect(window.streamingResponse).toBe(true);
      });

      it('shows RESPONDING alert on first fragment', () => {
        window.responseStarted = false;
        handlers.handleDefaultMessage({ type: 'fragment', content: 'test' });
        expect(global.setAlert).toHaveBeenCalledWith(
          expect.stringContaining('RESPONDING'),
          'warning'
        );
      });

      it('does not re-alert on subsequent fragments', () => {
        window.responseStarted = true;
        handlers.handleDefaultMessage({ type: 'fragment', content: 'test' });
        expect(global.setAlert).not.toHaveBeenCalled();
      });

      it('calls handleFragmentMessage', () => {
        handlers.handleDefaultMessage({ type: 'fragment', content: 'test' });
        expect(window.handleFragmentMessage).toHaveBeenCalledWith({ type: 'fragment', content: 'test' });
      });

      it('shows spinner during streaming', () => {
        window.streamingResponse = true;
        window.responseStarted = true;
        handlers.handleDefaultMessage({ type: 'fragment', content: 'test' });
        expect(mockElements['#monadic-spinner'].show).toHaveBeenCalled();
      });
    });

    describe('legacy message type', () => {
      it('sets responseStarted', () => {
        window.responseStarted = false;
        handlers.handleDefaultMessage({ type: 'unknown', content: 'Hello' });
        expect(window.responseStarted).toBe(true);
      });

      it('resets callingFunction', () => {
        window.callingFunction = true;
        handlers.handleDefaultMessage({ type: 'unknown', content: 'test' });
        expect(window.callingFunction).toBe(false);
      });

      it('appends escaped content to chat', () => {
        window.responseStarted = true;
        window.callingFunction = false;
        const chatMock = { html: jest.fn().mockReturnValue('existing') };
        mockElements['#chat'] = chatMock;

        handlers.handleDefaultMessage({ type: 'unknown', content: '<b>test</b>' });

        expect(chatMock.html).toHaveBeenCalledWith(expect.stringContaining('&lt;b&gt;test&lt;/b&gt;'));
      });
    });
  });

  describe('module exports', () => {
    it('exports both handlers', () => {
      expect(typeof handlers.handleStreamingComplete).toBe('function');
      expect(typeof handlers.handleDefaultMessage).toBe('function');
    });

    it('exposes handlers on window.WsStreamingHandler', () => {
      expect(typeof window.WsStreamingHandler).toBe('object');
    });
  });
});
