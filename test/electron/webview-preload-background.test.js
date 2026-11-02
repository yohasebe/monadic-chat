/**
 * @jest-environment jsdom
 */

// The preload's side of answers that finish while the Web UI is hidden: it
// replies to a hold or release only when the page did what was asked, names
// the operation and page generation, and answers a query with the work as
// of now.

function loadPreload() {
  const handlers = {};
  const sent = [];
  jest.resetModules();
  jest.doMock('electron', () => ({
    ipcRenderer: {
      on: (channel, fn) => { handlers[channel] = fn; },
      send: (channel, payload) => sent.push([channel, payload]),
      invoke: jest.fn().mockResolvedValue(null)
    },
    contextBridge: { exposeInMainWorld: (key, api) => { window[key] = api; } }
  }), { virtual: false });
  require('../../app/webview-preload.js');
  const emit = (channel, payload) => handlers[channel] && handlers[channel]({}, payload);
  const last = (channel) => [...sent].reverse().find(([c]) => c === channel);
  return { handlers, sent, emit, last, api: window.electronAPI.backgroundReply };
}

describe('webview preload: background reply', () => {
  afterEach(() => { delete window.electronAPI; });

  test('asks for a generation once the document is there, and reports with it', () => {
    const p = loadPreload();
    window.dispatchEvent(new Event('DOMContentLoaded'));
    expect(p.last('background-reply:ready')).toBeTruthy();
    p.api.report({ running: 1, pending: 0, media: false });
    expect(p.last('background-reply:report')).toBeUndefined(); // no generation yet
    p.emit('background-reply:hello', { generation: 7, held: false });
    p.api.report({ running: 1, pending: 2, media: false });
    expect(p.last('background-reply:report')[1]).toEqual({ generation: 7, running: 1, pending: 2, media: false });
  });

  test('confirms a hold only when the page stopped what it had', () => {
    const p = loadPreload();
    p.emit('background-reply:hello', { generation: 1, held: false });
    p.api.onHold(() => { throw new Error('could not stop'); });
    p.emit('background-reply:hold', { op: 3 });
    expect(p.last('background-reply:held')).toBeUndefined();

    p.api.onHold(() => {});
    p.emit('background-reply:hold', { op: 4 });
    expect(p.last('background-reply:held')[1]).toEqual({ generation: 1, op: 4 });
  });

  test('confirms a release only when the page dropped what was queued', () => {
    const p = loadPreload();
    p.emit('background-reply:hello', { generation: 1, held: false });
    p.api.onRelease(() => { throw new Error('could not clean up'); });
    p.emit('background-reply:release', { op: 5 });
    expect(p.last('background-reply:released')).toBeUndefined();

    p.api.onRelease(() => {});
    p.emit('background-reply:release', { op: 6 });
    expect(p.last('background-reply:released')[1]).toEqual({ generation: 1, op: 6 });
  });

  test('a page held before it registers gets the hold when it does', () => {
    const p = loadPreload();
    p.emit('background-reply:hello', { generation: 2, held: true });
    const hold = jest.fn();
    p.api.onHold(hold);
    expect(hold).toHaveBeenCalledTimes(1);
  });

  test('answers a query with the work as of now, asked of the page', () => {
    const p = loadPreload();
    p.emit('background-reply:hello', { generation: 3, held: false });
    p.api.report({ running: 0, pending: 0, media: false });
    p.api.onState(() => ({ running: 0, pending: 1, media: false }));
    p.emit('background-reply:query', { op: 9 });
    expect(p.last('background-reply:state')[1]).toEqual({ generation: 3, op: 9, running: 0, pending: 1, media: false });
  });

  test('gives no answer to a query when the page cannot say what it is doing', () => {
    const p = loadPreload();
    p.emit('background-reply:hello', { generation: 3, held: false });
    p.api.report({ running: 0, pending: 0, media: false });
    p.emit('background-reply:query', { op: 1 }); // not registered
    p.api.onState(() => { throw new Error('no state'); });
    p.emit('background-reply:query', { op: 2 });
    p.api.onState(() => ({ running: '0' }));
    p.emit('background-reply:query', { op: 3 });
    expect(p.last('background-reply:state')).toBeUndefined();
  });

  test('regular reports do not ask the page (which would stop its sending)', () => {
    const p = loadPreload();
    p.emit('background-reply:hello', { generation: 3, held: false });
    const state = jest.fn(() => ({ running: 0, pending: 0, media: false }));
    p.api.onState(state);
    p.api.report({ running: 1, pending: 0, media: false });
    expect(state).not.toHaveBeenCalled();
  });

  test('ignores a request without an operation number', () => {
    const p = loadPreload();
    p.emit('background-reply:hello', { generation: 1, held: false });
    p.api.onHold(() => {});
    p.emit('background-reply:hold', {});
    p.emit('background-reply:query', { op: 'x' });
    expect(p.last('background-reply:held')).toBeUndefined();
    expect(p.last('background-reply:state')).toBeUndefined();
  });

  test('passes on only the outcomes it knows, with the generation', () => {
    const p = loadPreload();
    p.emit('background-reply:hello', { generation: 4, held: false });
    p.api.finished({ requestId: 'r1', outcome: 'something' });
    expect(p.last('background-reply:finished')[1]).toEqual({ generation: 4, requestId: 'r1', outcome: 'no_reply' });
  });
});
