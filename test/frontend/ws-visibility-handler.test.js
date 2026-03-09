/**
 * @jest-environment jsdom
 */

/**
 * Tests for ws-visibility-handler.js
 *
 * Handles tab visibility changes: reconnection logic, spinner management,
 * TTS state reset, and WebSocket state recovery.
 */

function createMockElement(id) {
  return {
    length: 1,
    0: document.createElement('div'),
    hide: jest.fn().mockReturnThis(),
    show: jest.fn().mockReturnThis(),
    is: jest.fn().mockReturnValue(false),
    css: jest.fn().mockReturnValue(''),
    find: jest.fn().mockReturnThis(),
    text: jest.fn().mockReturnValue(''),
    html: jest.fn().mockReturnThis(),
    val: jest.fn().mockReturnValue(''),
    prop: jest.fn().mockReturnThis(),
    removeClass: jest.fn().mockReturnThis(),
    addClass: jest.fn().mockReturnThis()
  };
}

let mockElements;

describe('WsVisibilityHandler', () => {
  beforeEach(() => {
    jest.resetModules();

    mockElements = {
      '#monadic-spinner': createMockElement('monadic-spinner')
    };

    global.$ = jest.fn().mockImplementation(selector => {
      if (typeof selector === 'string' && mockElements[selector]) {
        return mockElements[selector];
      }
      return createMockElement('default');
    });

    global.setAlert = jest.fn();
    global.getTranslation = jest.fn().mockImplementation((key, fallback) => fallback);

    // WebSocket state
    window._wsIsConnecting = false;
    window._wsReconnectionTimer = null;
    window.ws = null;
    window.silentReconnectMode = false;
    window.streamingResponse = false;
    window.callingFunction = false;
    window.isReasoningStreamActive = jest.fn().mockReturnValue(false);
    window.debugWebSocket = false;

    // Functions used by handleVisibilityChange
    window.connect_websocket = jest.fn().mockReturnValue({
      readyState: 1, // OPEN
      send: jest.fn()
    });
    window.reconnect_websocket = jest.fn();
    window.startPing = jest.fn();
    window.stopPing = jest.fn();
    window.closeCurrentWebSocket = jest.fn();
    window.clearAudioQueue = jest.fn();
    window.removeStopButtonHighlight = jest.fn();
    window.setTtsPlaybackStarted = jest.fn();
    window.setTextResponseCompleted = jest.fn();

    // i18n
    window.webUIi18n = undefined;

    // Mock WebSocket constants
    global.WebSocket = {
      CONNECTING: 0,
      OPEN: 1,
      CLOSING: 2,
      CLOSED: 3
    };

    // Mock speechSynthesis
    window.speechSynthesis = {
      cancel: jest.fn()
    };

    // Cookie mock
    Object.defineProperty(document, 'cookie', {
      writable: true,
      value: ''
    });

    // Document hidden state - initially hidden, then becoming visible
    Object.defineProperty(document, 'hidden', {
      writable: true,
      configurable: true,
      value: false
    });
  });

  afterEach(() => {
    delete window._wsIsConnecting;
    delete window._wsReconnectionTimer;
    delete window.ws;
    delete window.silentReconnectMode;
    delete window.streamingResponse;
    delete window.callingFunction;
    delete window.isReasoningStreamActive;
    delete window.debugWebSocket;
    delete window.connect_websocket;
    delete window.reconnect_websocket;
    delete window.startPing;
    delete window.stopPing;
    delete window.closeCurrentWebSocket;
    delete window.clearAudioQueue;
    delete window.removeStopButtonHighlight;
    delete window.setTtsPlaybackStarted;
    delete window.setTextResponseCompleted;
    delete window.WsVisibilityHandler;
    delete window.handleVisibilityChange;
    delete global.$;
    delete global.WebSocket;
  });

  function loadHandler() {
    require('../../docker/services/ruby/public/js/monadic/ws-visibility-handler');
    return window.WsVisibilityHandler;
  }

  describe('handleVisibilityChange', () => {
    it('should do nothing when document is hidden', () => {
      Object.defineProperty(document, 'hidden', { value: true, configurable: true });
      const handler = loadHandler();
      handler.handleVisibilityChange();
      // No reconnection attempt
      expect(window.connect_websocket).not.toHaveBeenCalled();
      expect(window.reconnect_websocket).not.toHaveBeenCalled();
    });

    it('should reset TTS state when tab becomes visible', () => {
      const handler = loadHandler();
      handler.handleVisibilityChange();
      expect(window.autoSpeechActive).toBe(false);
      expect(window.autoPlayAudio).toBe(false);
      expect(window.setTtsPlaybackStarted).toHaveBeenCalledWith(true);
      expect(window.setTextResponseCompleted).toHaveBeenCalledWith(true);
    });

    it('should cancel speech synthesis when tab becomes visible', () => {
      const handler = loadHandler();
      handler.handleVisibilityChange();
      expect(window.speechSynthesis.cancel).toHaveBeenCalled();
    });

    it('should attempt reconnection when WebSocket is closed', () => {
      window.ws = { readyState: 3 }; // CLOSED
      const handler = loadHandler();
      handler.handleVisibilityChange();
      expect(window.closeCurrentWebSocket).toHaveBeenCalled();
      expect(window.connect_websocket).toHaveBeenCalled();
    });

    it('should not attempt reconnection when already connecting', () => {
      window._wsIsConnecting = true;
      window.ws = { readyState: 3 }; // CLOSED
      const handler = loadHandler();
      handler.handleVisibilityChange();
      expect(window.connect_websocket).not.toHaveBeenCalled();
    });

    it('should send PING when WebSocket is open', () => {
      const mockSend = jest.fn();
      window.ws = { readyState: 1, send: mockSend }; // OPEN
      const handler = loadHandler();
      handler.handleVisibilityChange();
      expect(mockSend).toHaveBeenCalledWith(JSON.stringify({ message: "PING" }));
    });

    it('should show Stopped message in silent mode', () => {
      window.silentReconnectMode = true;
      window.ws = { readyState: 3 }; // CLOSED
      const handler = loadHandler();
      handler.handleVisibilityChange();
      expect(global.setAlert).toHaveBeenCalledWith(
        expect.stringContaining('Stopped'),
        'warning'
      );
    });

    it('should clear reconnection timer before reconnecting', () => {
      window._wsReconnectionTimer = setTimeout(() => {}, 10000);
      window.ws = { readyState: 3 }; // CLOSED
      const handler = loadHandler();
      handler.handleVisibilityChange();
      expect(window._wsReconnectionTimer).toBeNull();
    });

    it('should set isConnecting flag during reconnection', () => {
      window.ws = { readyState: 3, _reconnectAttempts: 0 }; // CLOSED
      const handler = loadHandler();
      handler.handleVisibilityChange();
      // isConnecting should have been set to true (then reset in callback)
      // Since connect_websocket is mocked, the callback isn't automatically called
      // So it should still be true at this point
      expect(window._wsIsConnecting).toBe(true);
    });

    it('should call removeStopButtonHighlight', () => {
      const handler = loadHandler();
      handler.handleVisibilityChange();
      expect(window.removeStopButtonHighlight).toHaveBeenCalled();
    });
  });

  describe('window exports', () => {
    it('should export WsVisibilityHandler to window', () => {
      loadHandler();
      expect(typeof window.WsVisibilityHandler).toBe('object');
      expect(typeof window.WsVisibilityHandler.handleVisibilityChange).toBe('function');
    });

    it('should register visibilitychange listener', () => {
      const spy = jest.spyOn(document, 'addEventListener');
      loadHandler();
      expect(spy).toHaveBeenCalledWith('visibilitychange', expect.any(Function));
      spy.mockRestore();
    });
  });
});
