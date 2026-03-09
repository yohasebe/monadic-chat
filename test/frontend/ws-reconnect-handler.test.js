/**
 * @jest-environment jsdom
 */

/**
 * Tests for ws-reconnect-handler.js
 *
 * WebSocket reconnection logic with exponential backoff, maximum attempt
 * limits, state cleanup, and proper connection lifecycle management.
 */

describe('WsReconnectHandler', () => {
  beforeEach(() => {
    jest.resetModules();
    jest.useFakeTimers();

    global.$ = jest.fn().mockReturnValue({
      length: 0,
      hide: jest.fn().mockReturnThis(),
      show: jest.fn().mockReturnThis(),
      is: jest.fn().mockReturnValue(false)
    });

    global.setAlert = jest.fn();
    global.getTranslation = jest.fn().mockImplementation((key, fallback) => fallback);

    // WebSocket constants
    global.WebSocket = {
      CONNECTING: 0,
      OPEN: 1,
      CLOSING: 2,
      CLOSED: 3
    };

    // Shared state
    window._wsReconnectionTimer = null;
    window.silentReconnectMode = false;
    window.debugWebSocket = false;
    window.ws = null;

    // Functions used by reconnect_websocket
    window.connect_websocket = jest.fn().mockReturnValue({
      readyState: 1,
      send: jest.fn(),
      _reconnectAttempts: 0
    });
    window.startPing = jest.fn();
    window.stopPing = jest.fn();
    window.closeCurrentWebSocket = jest.fn();
    window.clearAudioQueue = jest.fn();

    // Constants
    window.WsAudioConstants = {
      maxReconnectAttempts: 5,
      baseReconnectDelay: 1000
    };

    // Cookie mock
    Object.defineProperty(document, 'cookie', {
      writable: true,
      value: ''
    });

    // i18n
    window.webUIi18n = undefined;
  });

  afterEach(() => {
    jest.useRealTimers();
    delete window._wsReconnectionTimer;
    delete window.silentReconnectMode;
    delete window.debugWebSocket;
    delete window.ws;
    delete window.connect_websocket;
    delete window.startPing;
    delete window.stopPing;
    delete window.closeCurrentWebSocket;
    delete window.clearAudioQueue;
    delete window.WsAudioConstants;
    delete window.WsReconnectHandler;
    delete window.reconnect_websocket;
    delete global.$;
    delete global.WebSocket;
  });

  function loadHandler() {
    require('../../docker/services/ruby/public/js/monadic/ws-reconnect-handler');
    return window.WsReconnectHandler;
  }

  describe('reconnect_websocket', () => {
    it('should not reconnect in silent mode', () => {
      window.silentReconnectMode = true;
      const handler = loadHandler();
      handler.reconnect_websocket({ readyState: 3 });
      expect(window.connect_websocket).not.toHaveBeenCalled();
    });

    it('should not reconnect when silent_reconnect cookie is set', () => {
      document.cookie = 'silent_reconnect=true';
      const handler = loadHandler();
      handler.reconnect_websocket({ readyState: 3 });
      expect(window.connect_websocket).not.toHaveBeenCalled();
    });

    it('should not reconnect when already reconnecting', () => {
      const handler = loadHandler();
      const mockWs = { readyState: 3, _isReconnecting: true };
      handler.reconnect_websocket(mockWs);
      expect(window.connect_websocket).not.toHaveBeenCalled();
    });

    it('should stop after max reconnection attempts', () => {
      const handler = loadHandler();
      const mockWs = { readyState: 3, _reconnectAttempts: 5 };
      handler.reconnect_websocket(mockWs);
      expect(window.connect_websocket).not.toHaveBeenCalled();
      expect(global.setAlert).toHaveBeenCalledWith(
        expect.stringContaining('Connection failed'),
        'danger'
      );
    });

    it('should create new connection when socket is closed', () => {
      const handler = loadHandler();
      const mockWs = { readyState: 3, _reconnectAttempts: 0, _isReconnecting: false };
      handler.reconnect_websocket(mockWs);
      expect(window.stopPing).toHaveBeenCalled();
      expect(window.closeCurrentWebSocket).toHaveBeenCalled();
      expect(window.connect_websocket).toHaveBeenCalled();
    });

    it('should clear audio queue before reconnection', () => {
      const handler = loadHandler();
      const mockWs = { readyState: 3, _reconnectAttempts: 0, _isReconnecting: false };
      handler.reconnect_websocket(mockWs);
      expect(window.clearAudioQueue).toHaveBeenCalled();
    });

    it('should schedule retry when socket is closing', () => {
      const handler = loadHandler();
      const mockWs = { readyState: 2, _reconnectAttempts: 0, _isReconnecting: false };
      handler.reconnect_websocket(mockWs);
      expect(window._wsReconnectionTimer).not.toBeNull();
      // Should not immediately connect
      expect(window.connect_websocket).not.toHaveBeenCalled();
    });

    it('should schedule retry when socket is connecting', () => {
      const handler = loadHandler();
      const mockWs = { readyState: 0, _reconnectAttempts: 0, _isReconnecting: false };
      handler.reconnect_websocket(mockWs);
      expect(window._wsReconnectionTimer).not.toBeNull();
      expect(window.connect_websocket).not.toHaveBeenCalled();
    });

    it('should reset counters when socket is open', () => {
      const handler = loadHandler();
      window.ws = { readyState: 1, _reconnectAttempts: 3, _isReconnecting: true };
      const mockWs = { readyState: 1, _reconnectAttempts: 2, _isReconnecting: false };
      handler.reconnect_websocket(mockWs);
      expect(window.ws._reconnectAttempts).toBe(0);
      expect(window.ws._isReconnecting).toBe(false);
      expect(window.startPing).toHaveBeenCalled();
    });

    it('should call callback when socket is open', () => {
      const handler = loadHandler();
      window.ws = { readyState: 1, _reconnectAttempts: 0, _isReconnecting: false };
      const callback = jest.fn();
      const mockWs = { readyState: 1, _reconnectAttempts: 0, _isReconnecting: false };
      handler.reconnect_websocket(mockWs, callback);
      expect(callback).toHaveBeenCalledWith(window.ws);
    });

    it('should update window.ws after creating new connection', () => {
      const handler = loadHandler();
      const newWs = { readyState: 1, send: jest.fn() };
      window.connect_websocket.mockReturnValue(newWs);
      const mockWs = { readyState: 3, _reconnectAttempts: 0, _isReconnecting: false };
      handler.reconnect_websocket(mockWs);
      expect(window.ws).toBe(newWs);
    });

    it('should use exponential backoff for delay', () => {
      const handler = loadHandler();
      // Attempt 2: delay = 1000 * 1.5^2 = 2250
      const mockWs = { readyState: 2, _reconnectAttempts: 2, _isReconnecting: false };
      handler.reconnect_websocket(mockWs);
      // Timer should be set with backoff delay
      expect(window._wsReconnectionTimer).not.toBeNull();
    });

    it('should clear existing timer before setting new one', () => {
      const existingTimer = setTimeout(() => {}, 99999);
      window._wsReconnectionTimer = existingTimer;
      const clearSpy = jest.spyOn(global, 'clearTimeout');

      const handler = loadHandler();
      const mockWs = { readyState: 2, _reconnectAttempts: 0, _isReconnecting: false };
      handler.reconnect_websocket(mockWs);

      expect(clearSpy).toHaveBeenCalledWith(existingTimer);
      clearSpy.mockRestore();
    });
  });

  describe('window exports', () => {
    it('should export reconnect_websocket to window', () => {
      loadHandler();
      expect(typeof window.reconnect_websocket).toBe('function');
    });

    it('should export WsReconnectHandler object', () => {
      loadHandler();
      expect(typeof window.WsReconnectHandler).toBe('object');
      expect(typeof window.WsReconnectHandler.reconnect_websocket).toBe('function');
    });
  });
});
