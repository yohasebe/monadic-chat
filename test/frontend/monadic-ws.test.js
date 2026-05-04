/**
 * Tests for monadic-ws.js (safeWsSend wrapper).
 *
 * These specs cover the state matrix from docs_dev/safe_ws_send_plan.md
 * §3.2: every combination of (ws state) × (idempotent yes/no) routes
 * to the correct outcome (send / queue / fail), and the queue
 * semantics (cap, TTL, dedup) match §3.4.
 *
 * The lint:bare_ws_send rule (planned H7.9) will catch new bare
 * ws.send() calls; these tests catch behaviour regressions in the
 * helper itself.
 */

require('../../docker/services/ruby/public/js/monadic/monadic-ws.js');

// Define WebSocket readyState constants on globalThis so the helper
// can resolve WebSocket.OPEN etc. at lookup time. jsdom may or may
// not expose a real WebSocket constructor; we only need the numeric
// constants for state branching, so a minimal shim is enough.
if (typeof global.WebSocket === 'undefined') {
  global.WebSocket = {
    CONNECTING: 0,
    OPEN: 1,
    CLOSING: 2,
    CLOSED: 3
  };
}

const { safeWsSend, MonadicWs } = window;

function makeMockWs(readyState) {
  return {
    readyState: readyState,
    send: jest.fn()
  };
}

describe('safeWsSend', () => {
  let originalWs;
  let originalConnect;
  let originalSetAlert;
  let originalAlert;
  let setAlertSpy;
  let alertSpy;

  beforeEach(() => {
    originalWs = window.ws;
    originalConnect = window.connect_websocket;
    originalSetAlert = window.setAlert;
    originalAlert = window.alert;
    window._wsIsConnecting = false;
    setAlertSpy = jest.fn();
    alertSpy = jest.fn();
    window.setAlert = setAlertSpy;
    window.alert = alertSpy;
    window.connect_websocket = jest.fn(() => makeMockWs(WebSocket.CONNECTING));
    MonadicWs._resetQueueForTests();
  });

  afterEach(() => {
    window.ws = originalWs;
    window.connect_websocket = originalConnect;
    window.setAlert = originalSetAlert;
    window.alert = originalAlert;
    window._wsIsConnecting = false;
    MonadicWs._resetQueueForTests();
  });

  test('OPEN state → sends synchronously', () => {
    const mockWs = makeMockWs(WebSocket.OPEN);
    window.ws = mockWs;

    const result = safeWsSend({ message: 'RESET' });

    expect(result).toMatchObject({ sent: true, queued: false, state: 'OPEN' });
    expect(mockWs.send).toHaveBeenCalledWith(JSON.stringify({ message: 'RESET' }));
    expect(setAlertSpy).not.toHaveBeenCalled();
    expect(alertSpy).not.toHaveBeenCalled();
  });

  test('CONNECTING + idempotent → queued, reconnect not retriggered', () => {
    window.ws = makeMockWs(WebSocket.CONNECTING);

    const result = safeWsSend({ message: 'RESET' });

    expect(result).toMatchObject({ sent: false, queued: true, state: 'CONNECTING' });
    expect(window.connect_websocket).not.toHaveBeenCalled();
    expect(MonadicWs._peekQueue().length).toBe(1);
    expect(setAlertSpy).toHaveBeenCalled();
  });

  test('null ws + idempotent → queued AND triggers reconnect', () => {
    window.ws = null;

    const result = safeWsSend({ message: 'LIBRARY_SAVE', contents: { x: 1 } });

    expect(result).toMatchObject({ sent: false, queued: true, state: 'NULL' });
    expect(window.connect_websocket).toHaveBeenCalledTimes(1);
    expect(MonadicWs._peekQueue().length).toBe(1);
  });

  test('null ws + non-idempotent → fails fast with alert, no queue, no reconnect', () => {
    window.ws = null;

    const result = safeWsSend({ message: 'CHAT', text: 'hi' });

    expect(result.sent).toBe(false);
    expect(result.queued).toBe(false);
    expect(result.error).toBeInstanceOf(Error);
    expect(alertSpy).toHaveBeenCalledTimes(1);
    expect(window.connect_websocket).not.toHaveBeenCalled();
    expect(MonadicWs._peekQueue().length).toBe(0);
  });

  test('CLOSED + idempotent → triggers reconnect once even with multiple queued messages', () => {
    window.ws = makeMockWs(WebSocket.CLOSED);

    safeWsSend({ message: 'RESET' });
    safeWsSend({ message: 'LOAD', ui_language: 'en' });
    safeWsSend({ message: 'HTML' });

    // _wsIsConnecting was set true on the first triggerReconnect; the
    // subsequent calls see the flag and do not start a second
    // connect. This matches the behaviour required by R2 in the plan.
    expect(window.connect_websocket).toHaveBeenCalledTimes(1);
    expect(MonadicWs._peekQueue().length).toBe(3);
  });

  test('drainQueue sends FIFO when ws becomes OPEN', () => {
    window.ws = null;
    safeWsSend({ message: 'RESET' });
    safeWsSend({ message: 'LOAD', ui_language: 'en' });

    // Simulate reconnect completing.
    const opened = makeMockWs(WebSocket.OPEN);
    window.ws = opened;

    const drained = MonadicWs.drainQueue();

    expect(drained).toBe(2);
    expect(opened.send).toHaveBeenNthCalledWith(1, JSON.stringify({ message: 'RESET' }));
    expect(opened.send).toHaveBeenNthCalledWith(2, JSON.stringify({ message: 'LOAD', ui_language: 'en' }));
    expect(MonadicWs._peekQueue().length).toBe(0);
  });

  test('queue cap drops oldest PING first when full', () => {
    window.ws = makeMockWs(WebSocket.CONNECTING);
    const cap = MonadicWs._config.QUEUE_CAP;

    // Pre-load with one PING and (cap-1) RESETs. Each RESET payload is
    // unique to bypass the dedup window.
    safeWsSend({ message: 'PING' });
    for (let i = 0; i < cap - 1; i++) {
      safeWsSend({ message: 'RESET', _seq: i });
    }
    expect(MonadicWs._peekQueue().length).toBe(cap);

    // One more entry → would overflow. The PING gets dropped.
    const result = safeWsSend({ message: 'RESET', _seq: 999 });
    expect(result.queued).toBe(true);
    const remaining = MonadicWs._peekQueue();
    expect(remaining.length).toBe(cap);
    expect(remaining.some(e => e.payload.message === 'PING')).toBe(false);
  });

  test('queue cap rejects new entry when full of non-PING messages', () => {
    window.ws = makeMockWs(WebSocket.CONNECTING);
    const cap = MonadicWs._config.QUEUE_CAP;

    for (let i = 0; i < cap; i++) {
      safeWsSend({ message: 'RESET', _seq: i });
    }
    expect(MonadicWs._peekQueue().length).toBe(cap);

    const result = safeWsSend({ message: 'RESET', _seq: 9999 });
    expect(result.sent).toBe(false);
    expect(result.queued).toBe(false);
    expect(result.error).toBeInstanceOf(Error);
    expect(MonadicWs._peekQueue().length).toBe(cap);
  });

  test('dedup coalesces identical payloads queued within window', () => {
    window.ws = makeMockWs(WebSocket.CONNECTING);

    const r1 = safeWsSend({ message: 'RESET' });
    const r2 = safeWsSend({ message: 'RESET' });

    expect(r1.queued).toBe(true);
    expect(r1.deduped).toBeUndefined();
    expect(r2.queued).toBe(true);
    expect(r2.deduped).toBe(true);
    expect(MonadicWs._peekQueue().length).toBe(1);
  });

  test('TTL expiry: stale entries dropped on next prune', () => {
    jest.useFakeTimers();
    window.ws = makeMockWs(WebSocket.CONNECTING);
    safeWsSend({ message: 'RESET' });
    expect(MonadicWs._peekQueue().length).toBe(1);

    // Advance past the TTL boundary and trigger a path that prunes.
    jest.advanceTimersByTime(MonadicWs._config.QUEUE_TTL_MS + 1000);
    safeWsSend({ message: 'LOAD' });

    const queue = MonadicWs._peekQueue();
    expect(queue.length).toBe(1);
    expect(queue[0].payload.message).toBe('LOAD');

    jest.useRealTimers();
  });

  test('silentDrop: no alert and no queue toast', () => {
    window.ws = null;
    const result = safeWsSend({ message: 'PING' }, { silentDrop: true });
    expect(result.queued).toBe(true);
    expect(setAlertSpy).not.toHaveBeenCalled();
    expect(alertSpy).not.toHaveBeenCalled();
  });

  test('refuses to queue an unserializable payload (circular reference)', () => {
    window.ws = makeMockWs(WebSocket.CLOSED);
    const a = { message: 'LOAD' };
    a.self = a; // JSON.stringify will throw

    const result = safeWsSend(a);

    expect(result.sent).toBe(false);
    expect(result.queued).toBe(false);
    // Even though LOAD is idempotent (would normally queue when CLOSED),
    // the unserializable payload short-circuits to fail-fast so the
    // drain loop is not poisoned for the next 30s of TTL.
    expect(alertSpy).toHaveBeenCalled();
  });

  test('isIdempotent surface for callers', () => {
    expect(MonadicWs.isIdempotent('RESET')).toBe(true);
    expect(MonadicWs.isIdempotent('LIBRARY_SAVE')).toBe(true);
    expect(MonadicWs.isIdempotent('LIBRARY_RAG_QUERY')).toBe(true);
    expect(MonadicWs.isIdempotent('LIBRARY_SET_SCOPE')).toBe(true);
    expect(MonadicWs.isIdempotent('LIBRARY_RENAME')).toBe(true);
    expect(MonadicWs.isIdempotent('LIBRARY_GET_CONVERSATION')).toBe(true);
    expect(MonadicWs.isIdempotent('EDIT')).toBe(true);
    expect(MonadicWs.isIdempotent('UPDATE_PARAMS')).toBe(true);
    expect(MonadicWs.isIdempotent('UPDATE_LANGUAGE')).toBe(true);
    expect(MonadicWs.isIdempotent('PDF_TITLES')).toBe(true);
    expect(MonadicWs.isIdempotent('DELETE_PDF')).toBe(true);
    expect(MonadicWs.isIdempotent('DELETE_ALL_PDFS')).toBe(true);
    expect(MonadicWs.isIdempotent('CHAT')).toBe(false);
    expect(MonadicWs.isIdempotent('PLAY_TTS')).toBe(false);
    expect(MonadicWs.isIdempotent('LIBRARY_SUGGEST_TITLE')).toBe(false);
    // SYSTEM_PROMPT and SAMPLE both append fresh-mid messages to
    // session[:messages] server-side, so replay would push duplicates.
    expect(MonadicWs.isIdempotent('SYSTEM_PROMPT')).toBe(false);
    expect(MonadicWs.isIdempotent('SAMPLE')).toBe(false);
    expect(MonadicWs.isIdempotent('AI_USER_QUERY')).toBe(false);
    // LIBRARY_RAG_STATE was a stale entry — the actual server message
    // is LIBRARY_RAG_QUERY. Lock the rename so it cannot regress.
    expect(MonadicWs.isIdempotent('LIBRARY_RAG_STATE')).toBe(false);
    expect(MonadicWs.isIdempotent('UNKNOWN_FUTURE_MSG')).toBe(false);
  });
});
