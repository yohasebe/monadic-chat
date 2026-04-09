/**
 * ws-reconnect-handler.js
 *
 * WebSocket reconnection logic with exponential backoff.
 * Handles connection state transitions (CLOSED → new connection,
 * CLOSING/CONNECTING → schedule retry, OPEN → reset counters).
 *
 * Shared mutable state accessed via window:
 *   window._wsReconnectionTimer - pending reconnection setTimeout id
 *   window.ws                   - the active WebSocket instance
 *
 * Extracted from websocket.js for modularity.
 */
(function() {
  'use strict';

  // Improved WebSocket reconnection logic with proper cleanup and retry handling
  // Note: Parameter renamed from 'ws' to 'currentWs' to avoid shadowing the window.ws variable
  function reconnect_websocket(currentWs, callback) {
    // In silent mode (intentional stop), suppress reconnection attempts
    try {
      if (window.silentReconnectMode || (document.cookie && document.cookie.includes('silent_reconnect=true'))) {
        return;
      }
    } catch (_) { console.warn("[WebSocket] Silent reconnect check failed:", _); }

    // Prevent multiple reconnection attempts for the same WebSocket
    if (currentWs && currentWs._isReconnecting) {
      if (window.debugWebSocket) console.log("Already attempting to reconnect, skipping duplicate attempt");
      return;
    }

    // Store reconnection attempts in the WebSocket object itself
    // This ensures each WebSocket manages its own reconnection state
    if (currentWs && currentWs._reconnectAttempts === undefined) {
      currentWs._reconnectAttempts = 0;
    }

    // Get constants from ws-audio-constants.js
    const maxReconnectAttempts = (window.WsAudioConstants || {}).maxReconnectAttempts || 5;
    const baseReconnectDelay = (window.WsAudioConstants || {}).baseReconnectDelay || 1000;

    // Limit maximum reconnection attempts
    if (currentWs && currentWs._reconnectAttempts >= maxReconnectAttempts) {
      console.error(`Maximum reconnection attempts (${maxReconnectAttempts}) reached.`);
      // In silent mode, keep showing 'Stopped'; otherwise show failure
      if (!window.silentReconnectMode) {
        const connectionFailedRefreshText = getTranslation('ui.messages.connectionFailedRefresh', 'Connection failed - please refresh page');
        setAlert(`<i class='fa-solid fa-server'></i> ${connectionFailedRefreshText}`, "danger");
      }

      // Properly clean up any pending timers
      currentWs._isReconnecting = false;
      if (window._wsReconnectionTimer) {
        clearTimeout(window._wsReconnectionTimer);
        window._wsReconnectionTimer = null;
      }
      return;
    }

    // Mark as reconnecting
    if (currentWs) {
      currentWs._isReconnecting = true;
    }

    // Calculate exponential backoff delay (use currentWs for attempt tracking, fallback to 0)
    const attemptCount = (currentWs && currentWs._reconnectAttempts) || 0;
    const delay = baseReconnectDelay * Math.pow(1.5, attemptCount);

    // Clear any existing reconnection timer
    if (window._wsReconnectionTimer) {
      clearTimeout(window._wsReconnectionTimer);
      window._wsReconnectionTimer = null;
    }

    try {
      // Check WebSocket state (use currentWs if provided, otherwise check window.ws)
      const wsToCheck = currentWs || window.ws;
      const currentState = wsToCheck ? wsToCheck.readyState : WebSocket.CLOSED;

      switch (currentState) {
        case WebSocket.CLOSED:
          // Socket is closed, create a new one
          if (currentWs) {
            currentWs._reconnectAttempts = (currentWs._reconnectAttempts || 0) + 1;
          }

          // Stop any active ping interval
          if (typeof window.stopPing === 'function') {
            window.stopPing();
          }

          // After maximum attempts, just show final error and don't reconnect
          const currentAttempts = currentWs ? currentWs._reconnectAttempts : 0;
          if (currentAttempts >= maxReconnectAttempts) {
            const connectionFailedRefreshText = getTranslation('ui.messages.connectionFailedRefresh', 'Connection failed - please refresh page');
            setAlert(`<i class='fa-solid fa-server'></i> ${connectionFailedRefreshText}`, "danger");
            return; // Exit without creating new connection
          }

          // Get connection details
          let connectionDetails = "";
          let host = "localhost";
          let port = "4567";

          // Get hostname from browser URL if not localhost
          if (window.location.hostname && window.location.hostname !== 'localhost' && window.location.hostname !== '127.0.0.1') {
            host = window.location.hostname;
            port = window.location.port || "4567";
            connectionDetails = ` to ${host}:${port}`;
          }

          // In silent mode, do not spam connection messages
          if (!window.silentReconnectMode) {
            const message = `<i class='fa-solid fa-sync fa-spin'></i> Connecting${connectionDetails}...`;
            setAlert(message, "warning");
          }

          // Clear audio state before reconnection to prevent stale sequences
          try {
            if (typeof window.clearAudioQueue === 'function') {
              window.clearAudioQueue();
            }
          } catch (e) {
            console.warn('[reconnect_websocket] Error clearing audio queue:', e);
          }

          // CRITICAL: Close old WebSocket before creating new one to prevent connection accumulation
          if (typeof window.closeCurrentWebSocket === 'function') {
            window.closeCurrentWebSocket();
          }

          // Create new connection and assign to window.ws
          window.ws = window.connect_websocket(callback);
          break;

        case WebSocket.CLOSING:
          // Wait for socket to fully close before reconnecting
          if (window.debugWebSocket) console.log(`Socket is closing. Waiting ${delay}ms before reconnection attempt.`);
          window._wsReconnectionTimer = setTimeout(() => {
            if (currentWs) {
              currentWs._isReconnecting = false; // Reset flag before next attempt
            }
            reconnect_websocket(currentWs, callback);
          }, delay);
          break;

        case WebSocket.CONNECTING:
          // Socket is still trying to connect, wait a bit before checking again
          if (window.debugWebSocket) console.log(`Socket is connecting. Checking again in ${delay}ms.`);
          window._wsReconnectionTimer = setTimeout(() => {
            if (currentWs) {
              currentWs._isReconnecting = false; // Reset flag before next attempt
            }
            reconnect_websocket(currentWs, callback);
          }, delay);
          break;

        case WebSocket.OPEN:
          // Connection is successful, reset counters on the active connection
          if (window.ws) {
            window.ws._reconnectAttempts = 0;
            window.ws._isReconnecting = false;
          }

          // Start ping to keep connection alive
          if (typeof window.startPing === 'function') {
            window.startPing();
          }

          // Update UI
          const connectedMsg = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.connected') : 'Connected';
          // Clear silent mode and cookie when successfully connected again
          try {
            window.silentReconnectMode = false;
            document.cookie = 'silent_reconnect=; path=/; expires=Thu, 01 Jan 1970 00:00:00 GMT';
          } catch(_) { console.warn("[WebSocket] Silent reconnect cleanup failed:", _); }
          setAlert(`<i class='fa-solid fa-circle-check'></i> ${connectedMsg}`, "info");

          // Execute callback if provided
          if (callback && typeof callback === 'function') {
            callback(window.ws);
          }
          break;
      }
    } catch (error) {
      console.error("Error during WebSocket reconnection:", error);

      // Schedule another attempt with backoff on error
      window._wsReconnectionTimer = setTimeout(() => {
        // Increment attempt counter on error
        if (currentWs) {
          currentWs._reconnectAttempts = (currentWs._reconnectAttempts || 0) + 1;
          currentWs._isReconnecting = false; // Reset flag before next attempt
        }
        reconnect_websocket(currentWs, callback);
      }, delay);
    }
  }

  // Export to window for browser usage
  window.reconnect_websocket = reconnect_websocket;

  window.WsReconnectHandler = {
    reconnect_websocket: reconnect_websocket
  };

  // Support for Jest testing environment (CommonJS)
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = window.WsReconnectHandler;
  }
})();
