/**
 * monadic-ws.js — single-source-of-truth wrapper around `ws.send(...)`.
 *
 * Background: prior to this helper, 39 of 40 callsites in the codebase
 * called `ws.send(JSON.stringify(payload))` with no null-guard and no
 * non-OPEN guard. When the WebSocket dropped (idle close, network blip,
 * page hibernation) and the reconnect was still in flight, every one
 * of those callsites threw "Cannot read properties of null (reading
 * 'send')" or "WebSocket is already in CLOSING or CLOSED state".
 *
 * Symmetric with monadic-fetch.js: that helper enforces a contract for
 * all HTTP I/O, this helper enforces one for all WebSocket I/O. See
 * docs_dev/safe_ws_send_plan.md for the design rationale, idempotency
 * audit, and rollout plan (H7 phases of the architecture hardening
 * effort).
 *
 * Usage:
 *   const r = window.safeWsSend({ message: 'RESET' });
 *   if (r.sent || r.queued) {
 *     // Operation is in flight; safe to update UI optimistically.
 *   } else {
 *     // safeWsSend has already alerted the user. Caller should not
 *     // close modals or otherwise advance state.
 *   }
 *
 * Hook from websocket.js onopen:
 *   if (window.MonadicWs && typeof window.MonadicWs.drainQueue === 'function') {
 *     window.MonadicWs.drainQueue();
 *   }
 */
(function (window) {
  'use strict';

  // Message types whose server-side handlers are idempotent under
  // replay. Audited in docs_dev/safe_ws_send_plan.md §3.3. Anything
  // not in this set defaults to non-idempotent (safer to fail fast
  // than to risk a silent double-send for non-replayable actions like
  // CHAT messages).
  const IDEMPOTENT_MESSAGE_TYPES = new Set([
    'PING',
    'RESET',
    'LOAD',
    'HTML',
    'CHECK_TOKEN',
    'CANCEL',
    'DELETE',
    'EDIT',
    'STOP_TTS',
    'UPDATE_PARAMS',
    'UPDATE_LANGUAGE',
    'PDF_TITLES',
    'DELETE_PDF',
    'DELETE_ALL_PDFS',
    'PRIVACY_REGISTRY',
    'LIBRARY_SAVE',
    'LIBRARY_LIST',
    'LIBRARY_DELETE',
    'LIBRARY_STATS',
    'LIBRARY_GET_CONVERSATION',
    'LIBRARY_RAG_QUERY',
    'LIBRARY_RAG_TOGGLE',
    'LIBRARY_RENAME',
    'LIBRARY_SET_SCOPE'
  ]);

  // Queue caps: 20 entries total, 30s TTL per entry, 500ms dedup
  // window. Tuned for "two reset clicks while reconnecting" not "store
  // a session's worth of messages." See plan §3.4.
  const QUEUE_CAP = 20;
  const QUEUE_TTL_MS = 30_000;
  const DEDUP_WINDOW_MS = 500;

  // Closure-scoped queue. Each entry: { payload, queuedAt, key }.
  // Exposed only via the helper API below — not via window directly,
  // so test code uses the same accessors the rest of the codebase will.
  let queue = [];

  function readyStateName(ws) {
    if (!ws) return 'NULL';
    switch (ws.readyState) {
      case WebSocket.CONNECTING: return 'CONNECTING';
      case WebSocket.OPEN: return 'OPEN';
      case WebSocket.CLOSING: return 'CLOSING';
      case WebSocket.CLOSED: return 'CLOSED';
      default: return 'UNKNOWN';
    }
  }

  function payloadKey(payload) {
    // Cheap dedup key. JSON.stringify is fine here: payloads are
    // small and infrequent at this layer; the alternative (deep
    // equality) is more code than the dedup is worth.
    try { return JSON.stringify(payload); } catch (_) { return null; }
  }

  function notifyReconnecting() {
    if (typeof window.setAlert !== 'function') return;
    const text = (typeof window.webUIi18n !== 'undefined' && window.webUIi18n.t)
      ? window.webUIi18n.t('ui.messages.reconnecting')
      : 'Reconnecting…';
    // The leading text content equals the key when no translation is
    // registered for it — fall back to English so the toast stays
    // readable during the i18n catch-up phase.
    const display = (text === 'ui.messages.reconnecting') ? 'Reconnecting…' : text;
    try {
      window.setAlert(`<i class='fa-solid fa-spinner fa-spin'></i> ${display}`, 'warning');
    } catch (_) { /* never let the alert path break the send path */ }
  }

  function notifyFailed() {
    const text = (typeof window.webUIi18n !== 'undefined' && window.webUIi18n.t)
      ? window.webUIi18n.t('ui.messages.connectionLost')
      : 'Connection lost. Please retry.';
    const display = (text === 'ui.messages.connectionLost') ? 'Connection lost. Please retry.' : text;
    try {
      // alert() is intentional here: this is a fail-fast for actions
      // the user expected to take effect immediately (CHAT send, AI_USER,
      // TTS). A non-blocking toast would let them think the action
      // succeeded and click again.
      window.alert(display);
    } catch (_) { /* never let the alert path break the caller */ }
  }

  function pruneExpired(now) {
    if (queue.length === 0) return;
    const cutoff = now - QUEUE_TTL_MS;
    queue = queue.filter(function (entry) { return entry.queuedAt >= cutoff; });
  }

  function enforceCap() {
    if (queue.length <= QUEUE_CAP) return true;
    // Drop oldest PING first — those are background heartbeats and
    // their loss is harmless. If the queue is full of non-PING entries
    // we reject the new one (handled by caller).
    const pingIdx = queue.findIndex(function (entry) {
      return entry.payload && entry.payload.message === 'PING';
    });
    if (pingIdx !== -1) {
      queue.splice(pingIdx, 1);
      return true;
    }
    return false;
  }

  function triggerReconnect() {
    // Reuse the existing reconnect machinery rather than implementing
    // our own. _wsIsConnecting is the codebase's existing dedup flag
    // for "do not start a second connect while one is in flight."
    if (window._wsIsConnecting) return;
    if (typeof window.connect_websocket !== 'function') return;
    try {
      window._wsIsConnecting = true;
      window.ws = window.connect_websocket();
      // Note: connect_websocket sets the new ws on window.ws and wires
      // its onopen/onclose. The drain happens when onopen fires and
      // calls our drainQueue hook (added to websocket.js as a 3-line
      // touch).
    } catch (err) {
      window._wsIsConnecting = false;
      try { console.error('[safeWsSend] reconnect trigger failed:', err); } catch (_) {}
    }
  }

  function safeWsSend(payload, opts) {
    opts = opts || {};
    const messageType = (payload && payload.message) || 'UNKNOWN';
    const isIdempotent = (opts.idempotent !== undefined)
      ? !!opts.idempotent
      : IDEMPOTENT_MESSAGE_TYPES.has(messageType);
    const allowReconnect = (opts.allowReconnect !== undefined)
      ? !!opts.allowReconnect
      : isIdempotent;
    const alertOnFail = opts.alertOnFail !== false;
    const silentDrop = !!opts.silentDrop;

    const ws = window.ws;
    const state = readyStateName(ws);

    // Fast path.
    if (state === 'OPEN') {
      try {
        ws.send(JSON.stringify(payload));
        return { sent: true, queued: false, state: state };
      } catch (err) {
        // Extremely rare: ws was OPEN but send threw (usually means
        // the underlying socket transitioned in the same tick). Fall
        // through to the queue path.
        try { console.warn('[safeWsSend] send threw on OPEN socket:', err); } catch (_) {}
      }
    }

    // Non-idempotent + not OPEN: fail fast.
    if (!allowReconnect) {
      if (alertOnFail && !silentDrop) notifyFailed();
      return {
        sent: false,
        queued: false,
        state: state,
        error: new Error('WebSocket not OPEN and message ' + messageType + ' is not safe to replay.')
      };
    }

    // Queue for replay.
    const now = Date.now();
    pruneExpired(now);

    // Dedup: identical payload queued in the last DEDUP_WINDOW_MS is
    // coalesced (keeps rage-click Reset from flooding the queue).
    const key = payloadKey(payload);
    // payloadKey returns null when JSON.stringify throws (circular
    // references, BigInt, etc.). Queueing such a payload would put
    // drainQueue into a re-throw / re-queue loop that only exits via
    // the 30s TTL. Fail fast so the caller sees the error
    // immediately instead of waiting half a minute for a phantom
    // recovery that never comes.
    if (key === null) {
      try { console.warn('[safeWsSend] payload not serializable; refusing to queue.'); } catch (_) {}
      if (alertOnFail && !silentDrop) notifyFailed();
      return {
        sent: false,
        queued: false,
        state: state,
        error: new Error('payload not JSON-serializable')
      };
    }
    if (key) {
      const recent = queue.find(function (entry) {
        return entry.key === key && (now - entry.queuedAt) < DEDUP_WINDOW_MS;
      });
      if (recent) {
        return { sent: false, queued: true, deduped: true, state: state };
      }
    }

    queue.push({ payload: payload, queuedAt: now, key: key });

    if (!enforceCap()) {
      // Cap exceeded and no PING to drop — reject this entry.
      queue.pop();
      if (alertOnFail && !silentDrop) notifyFailed();
      return {
        sent: false,
        queued: false,
        state: state,
        error: new Error('WebSocket send queue is full (' + QUEUE_CAP + ').')
      };
    }

    if (!silentDrop) notifyReconnecting();

    // CONNECTING / CLOSING: existing transition will fire onopen. We
    // do not start a new reconnect.
    if (state === 'CONNECTING' || state === 'CLOSING') {
      return { sent: false, queued: true, state: state };
    }

    // CLOSED / NULL: trigger reconnect ourselves.
    triggerReconnect();
    return { sent: false, queued: true, state: state };
  }

  function drainQueue() {
    const ws = window.ws;
    if (!ws || ws.readyState !== WebSocket.OPEN) return;

    const now = Date.now();
    pruneExpired(now);

    // Snapshot then clear so retries-during-drain don't double-process.
    const snapshot = queue.slice();
    queue = [];

    let sentCount = 0;
    for (let i = 0; i < snapshot.length; i++) {
      try {
        ws.send(JSON.stringify(snapshot[i].payload));
        sentCount++;
      } catch (err) {
        // The socket transitioned mid-drain. Re-queue the remainder
        // for the next onopen and bail.
        try { console.warn('[safeWsSend] drain send failed mid-batch:', err); } catch (_) {}
        for (let j = i; j < snapshot.length; j++) queue.push(snapshot[j]);
        break;
      }
    }
    if (sentCount > 0) {
      try { console.log('[safeWsSend] drained ' + sentCount + ' queued message(s).'); } catch (_) {}
    }
    return sentCount;
  }

  function _peekQueue() {
    return queue.slice();
  }

  function _resetQueueForTests() {
    queue = [];
  }

  window.safeWsSend = safeWsSend;
  window.MonadicWs = {
    drainQueue: drainQueue,
    isIdempotent: function (messageType) { return IDEMPOTENT_MESSAGE_TYPES.has(messageType); },
    _peekQueue: _peekQueue,
    _resetQueueForTests: _resetQueueForTests,
    _config: {
      QUEUE_CAP: QUEUE_CAP,
      QUEUE_TTL_MS: QUEUE_TTL_MS,
      DEDUP_WINDOW_MS: DEDUP_WINDOW_MS
    }
  };
})(window);
