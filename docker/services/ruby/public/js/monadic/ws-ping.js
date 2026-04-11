/**
 * ws-ping.js
 *
 * Periodic keep-alive PING sender for the WebSocket connection.
 * Extracted from websocket.js for modularity.
 *
 * The interval ID is held internally; callers use start/stop only.
 * start() auto-stops any existing interval before starting a new one,
 * so it is safe to call repeatedly (e.g. on reconnect).
 */
(function() {
  'use strict';

  var pingInterval = null;

  function start(getWs, intervalMs) {
    stop();
    pingInterval = setInterval(function() {
      var ws = typeof getWs === 'function' ? getWs() : null;
      if (ws && ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({ message: 'PING' }));
      } else {
        stop();
      }
    }, intervalMs);
  }

  function stop() {
    if (pingInterval) {
      clearInterval(pingInterval);
      pingInterval = null;
    }
  }

  window.WsPing = {
    start: start,
    stop: stop
  };

  // Support for Jest testing environment (CommonJS)
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = window.WsPing;
  }
})();
