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
        // The OPEN guard above owns the "stop the interval if the
        // socket is no longer alive" semantics; safeWsSend is invoked
        // here strictly for the central sending discipline. silentDrop
        // is belt-and-suspenders — even if the guard regresses, a
        // background heartbeat must never alert the user.
        window.safeWsSend({ message: 'PING' }, { silentDrop: true });
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
