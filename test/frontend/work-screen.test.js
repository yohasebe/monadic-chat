/**
 * @jest-environment jsdom
 */
// The work screen pane holds a socket only while it can be seen, draws only
// frames of the stream it shows, and says when each is drawn.
const path = require('path');

const js = (f) => path.join(__dirname, '../../docker/services/ruby/public/js', f);

class FakeSocket {
  constructor(url) {
    this.url = url;
    this.sent = [];
    this.readyState = 0;
    this.closed = false;
    FakeSocket.all.push(this);
  }
  open() {
    this.readyState = 1;
    this.onopen && this.onopen();
  }
  send(text) { this.sent.push(JSON.parse(text)); }
  close() {
    this.closed = true;
    this.readyState = 3;
    this.onclose && this.onclose();
  }
  receive(message) { this.onmessage({ data: JSON.stringify(message) }); }
  of(type) { return this.sent.filter((m) => m.type === type); }
}
FakeSocket.OPEN = 1;
FakeSocket.all = [];

// Decoding finishes when the test says so.
class FakeImage {
  constructor() {
    this.src = '';
    FakeImage.pending.push(this);
    this.done = new Promise((resolve) => { this.finish = resolve; });
  }
  decode() { return this.done; }
}
FakeImage.pending = [];

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

describe('WorkScreen', () => {
  let LC;
  let WS;
  let asked;
  // What each loading of the module listens to on the document, taken off
  // after the test (the document outlives the module).
  const listeners = [];
  const realAdd = document.addEventListener.bind(document);

  beforeEach(() => {
    jest.resetModules();
    document.addEventListener = (type, fn, options) => {
      listeners.push([type, fn]);
      realAdd(type, fn, options);
    };
    FakeSocket.all = [];
    FakeImage.pending = [];
    global.WebSocket = FakeSocket;
    global.Image = FakeImage;
    Object.defineProperty(window, 'innerWidth', { configurable: true, writable: true, value: 1280 });
    Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'visible' });
    document.cookie = 'menu-hidden-preference=false; path=/';
    document.body.innerHTML =
      '<button id="toggle-menu"></button>' +
      '<div id="menu">' +
        '<div id="side-pane-tabs" role="tablist">' +
          '<button role="tab" aria-controls="settings-pane" data-pane="settings">Menu</button>' +
          '<button role="tab" aria-controls="work-screen-pane" data-pane="work">Work screen</button>' +
        '</div>' +
        '<div id="settings-pane" role="tabpanel"></div>' +
        '<div id="work-screen-pane" role="tabpanel" hidden>' +
          '<div id="work-screen-empty"></div><img id="work-screen-image" style="display: none;">' +
        '</div>' +
      '</div>' +
      '<div id="main"></div>';
    delete window.BackgroundReply;
    delete window.monadicSocketBase;
    asked = 0;
    window.safeWsSend = jest.fn((message) => { if (message.message === 'WORK_SCREEN_TOKEN') asked += 1; });
    require(js('monadic/dom-helpers.js'));
    require(js('monadic/cookie-utils.js'));
    LC = require(js('monadic/layout-controller.js'));
    WS = require(js('monadic/work-screen.js'));
    LC.apply();
  });

  afterEach(() => {
    listeners.splice(0).forEach(([type, fn]) => document.removeEventListener(type, fn));
    document.addEventListener = realAdd;
  });

  const image = () => document.getElementById('work-screen-image');
  const note = () => document.getElementById('work-screen-empty');
  const shown = (el) => el.style.display !== 'none';

  // The Work screen tab selected, a pass given, the socket open and live.
  function watching(streamNo = 1) {
    LC.setPane('work');
    WS.onPass('a'.repeat(32));
    const socket = FakeSocket.all[FakeSocket.all.length - 1];
    socket.open();
    socket.receive({ type: 'state', state: 'live', browser: 1, stream: streamNo });
    return socket;
  }

  test('asks for nothing while the Menu tab is selected', () => {
    expect(asked).toBe(0);
    expect(FakeSocket.all).toHaveLength(0);
  });

  test('on the Work screen tab, opens the socket with a pass and subscribes', () => {
    LC.setPane('work');
    expect(asked).toBe(1);
    WS.onPass('b'.repeat(32));
    const socket = FakeSocket.all[0];
    expect(socket.url).toBe('ws://localhost:4567/work-screen');
    socket.open();
    expect(socket.sent).toEqual([{ type: 'auth', token: 'b'.repeat(32) }, { type: 'subscribe' }]);
  });

  test('uses the chat socket\'s host and port', () => {
    window.monadicSocketBase = () => 'ws://192.168.0.5:4567';
    LC.setPane('work');
    WS.onPass('c'.repeat(32));
    expect(FakeSocket.all[0].url).toBe('ws://192.168.0.5:4567/work-screen');
  });

  test('draws a frame once decoded and then says it is drawn', async () => {
    const socket = watching();
    socket.receive({ type: 'frame', browser: 1, stream: 1, n: 4, data: 'QUJD' });
    expect(socket.of('frame-consumed')).toHaveLength(0);
    FakeImage.pending[0].finish();
    await flush();
    expect(image().src).toBe('data:image/jpeg;base64,QUJD');
    expect(shown(image())).toBe(true);
    expect(shown(note())).toBe(false);
    expect(socket.of('frame-consumed')).toEqual([{ type: 'frame-consumed', stream: 1, n: 4 }]);
  });

  test('does not draw a frame of another stream', () => {
    const socket = watching(2);
    socket.receive({ type: 'frame', browser: 1, stream: 1, n: 1, data: 'QUJD' });
    expect(FakeImage.pending).toHaveLength(0);
  });

  test('does not draw a frame still decoding when the stream ended', async () => {
    const socket = watching();
    socket.receive({ type: 'frame', browser: 1, stream: 1, n: 1, data: 'QUJD' });
    socket.receive({ type: 'state', state: 'ended', reason: 'browser_closed', browser: 1, stream: 1 });
    FakeImage.pending[0].finish();
    await flush();
    expect(shown(image())).toBe(false);
    expect(image().getAttribute('src')).toBeNull();
    expect(socket.of('frame-consumed')).toHaveLength(0);
  });

  test('does not draw a frame that comes after its stream ended', () => {
    const socket = watching();
    socket.receive({ type: 'state', state: 'waiting', reason: 'no_window', browser: 1, stream: 1 });
    socket.receive({ type: 'frame', browser: 1, stream: 1, n: 1, data: 'QUJD' });
    expect(FakeImage.pending).toHaveLength(0);
  });

  test('clears the image and closes the socket when the pane is left', async () => {
    const socket = watching();
    socket.receive({ type: 'frame', browser: 1, stream: 1, n: 1, data: 'QUJD' });
    FakeImage.pending[0].finish();
    await flush();
    LC.setPane('settings');
    expect(socket.closed).toBe(true);
    expect(shown(image())).toBe(false);
  });

  test('closes the socket when the window is hidden', () => {
    const socket = watching();
    Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'hidden' });
    document.dispatchEvent(new Event('visibilitychange'));
    expect(socket.closed).toBe(true);
  });

  test('opens again with a new pass when the chat socket reconnected', () => {
    const socket = watching();
    expect(asked).toBe(1);
    socket.receive({ type: 'state', state: 'ended', reason: 'connection' });
    expect(socket.closed).toBe(true);
    expect(asked).toBe(2);
  });

  test('subscribes again after a Reset or a move to another chat', () => {
    const socket = watching();
    socket.receive({ type: 'state', state: 'ended', reason: 'replaced', browser: 1, stream: 1 });
    expect(socket.of('subscribe')).toHaveLength(2);
    expect(socket.closed).toBe(false);
  });

  test('switches to the Work screen tab when the chat\'s browser opens', () => {
    WS.onChatEvent({ type: 'work_screen', event: 'browser_opened', browser: 1 });
    expect(LC.selectedPane()).toBe('work');
    expect(asked).toBe(1);
  });

  test('subscribes again when a browser opens while the pane is shown', () => {
    const socket = watching();
    WS.onChatEvent({ type: 'work_screen', event: 'browser_opened', browser: 2 });
    expect(socket.of('subscribe')).toHaveLength(2);
  });

  test('says it is unavailable, and asks no more, where the server has no work screen', () => {
    const socket = watching();
    socket.receive({ type: 'state', state: 'ended', reason: 'unavailable' });
    expect(note().getAttribute('data-i18n')).toBe('ui.sidePane.workScreenUnavailable');
    LC.setPane('settings');
    LC.setPane('work');
    expect(asked).toBe(1);
  });
});
