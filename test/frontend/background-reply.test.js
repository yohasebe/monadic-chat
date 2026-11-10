/**
 * @jest-environment jsdom
 */

// The page's side of the Web UI kept hidden by the desktop app: it counts
// the answers the server says are running, reports how each ended once,
// keeps the microphone closed, audio silent and new sends back while held,
// and drops what arrived meanwhile.

const MODULE = '../../docker/services/ruby/public/js/monadic/background-reply';

class FakeTrack {
  constructor() { this.readyState = 'live'; }
  stop() { this.readyState = 'ended'; }
}

function fakeStream() {
  const track = new FakeTrack();
  jest.spyOn(track, 'stop');
  return { track, stream: { getTracks: () => [track] } };
}

describe('BackgroundReply (page)', () => {
  let bridge;
  let handlers;
  let getUserMedia;
  let speak;
  let BackgroundReply;

  function load() {
    jest.isolateModules(() => {
      BackgroundReply = require(MODULE);
    });
  }

  beforeEach(() => {
    handlers = {};
    bridge = {
      report: jest.fn(),
      finished: jest.fn(),
      onHold: jest.fn((fn) => { handlers.hold = fn; }),
      onRelease: jest.fn((fn) => { handlers.release = fn; })
    };
    window.electronAPI = { backgroundReply: bridge };
    getUserMedia = jest.fn();
    Object.defineProperty(navigator, 'mediaDevices', { value: { getUserMedia }, configurable: true });
    speak = jest.fn();
    window.speechSynthesis = { speak, cancel: jest.fn() };
    window.ttsStop = jest.fn();
    delete window.LiveConversation;
    load();
  });

  afterEach(() => {
    jest.useRealTimers();
    delete window.electronAPI;
    delete window.ttsStop;
    delete window.BackgroundReply;
  });

  test('counts running answers from the server and reports each end once', () => {
    BackgroundReply.onReplyState({ type: 'reply_state', state: 'running', request_id: 'a' });
    BackgroundReply.onReplyState({ type: 'reply_state', state: 'running', request_id: 'b' });
    expect(bridge.report).toHaveBeenLastCalledWith({ running: 2, pending: 0 });

    BackgroundReply.onReplyState({ type: 'reply_state', state: 'finished', outcome: 'done', request_id: 'a' });
    BackgroundReply.onReplyState({ type: 'reply_state', state: 'finished', outcome: 'done', request_id: 'a' });
    BackgroundReply.onReplyState({ type: 'reply_state', state: 'finished', outcome: 'no_reply', request_id: 'b' });

    expect(bridge.finished.mock.calls).toEqual([
      [{ requestId: 'a', outcome: 'done' }],
      [{ requestId: 'b', outcome: 'no_reply' }]
    ]);
    expect(bridge.report).toHaveBeenLastCalledWith({ running: 0, pending: 0 });
  });

  test('ignores an end for an answer it was not told about', () => {
    BackgroundReply.onReplyState({ type: 'reply_state', state: 'finished', outcome: 'done', request_id: 'x' });
    expect(bridge.finished).not.toHaveBeenCalled();
  });

  test('a closed connection ends every running answer as lost', () => {
    BackgroundReply.onReplyState({ type: 'reply_state', state: 'running', request_id: 'a' });
    expect(BackgroundReply.onConnectionLost()).toBe(1);
    expect(BackgroundReply.onConnectionLost()).toBe(0);
    expect(bridge.finished.mock.calls).toEqual([[{ requestId: 'a', outcome: 'lost' }]]);
    expect(BackgroundReply._state().running).toBe(0);
  });

  test('while held, the microphone is not opened, and one that opens late is closed at once', async () => {
    const { track, stream } = fakeStream();
    let resolve;
    getUserMedia.mockReturnValue(new Promise((r) => { resolve = r; }));
    const opening = navigator.mediaDevices.getUserMedia({ audio: true });

    handlers.hold();
    resolve(stream);
    await expect(opening).rejects.toMatchObject({ name: 'NotAllowedError' });
    expect(track.stop).toHaveBeenCalled();

    getUserMedia.mockClear();
    await expect(navigator.mediaDevices.getUserMedia({ audio: true })).rejects.toMatchObject({ name: 'NotAllowedError' });
    expect(getUserMedia).not.toHaveBeenCalled();
  });

  test('holding stops audio and keeps the browser from speaking; release drops what was queued', () => {
    handlers.hold();
    expect(window.ttsStop).toHaveBeenCalledTimes(1);
    window.speechSynthesis.speak({ text: 'hi' });
    expect(speak).not.toHaveBeenCalled();
    expect(BackgroundReply.isHeld()).toBe(true);

    handlers.release();
    expect(window.ttsStop).toHaveBeenCalledTimes(2);
    expect(BackgroundReply.isHeld()).toBe(false);
    window.speechSynthesis.speak({ text: 'hi' });
    expect(speak).toHaveBeenCalledTimes(1);
  });

  test('a message that starts work counts until the server takes it up or refuses it, not for a time', () => {
    jest.useFakeTimers();
    BackgroundReply.expectReply();
    BackgroundReply.expectReply();
    BackgroundReply.expectReply();
    expect(BackgroundReply._state().pending).toBe(3);
    jest.advanceTimersByTime(60000);
    expect(BackgroundReply._state().pending).toBe(3);

    BackgroundReply.onReplyState({ type: 'reply_state', state: 'running', request_id: 'a' });
    BackgroundReply.onRefused();
    expect(bridge.report).toHaveBeenLastCalledWith({ running: 1, pending: 1 });
  });

  test('a refused message ends without a reply, and a refusal with nothing sent ends nothing', () => {
    BackgroundReply.onRefused();
    expect(bridge.finished).not.toHaveBeenCalled();
    BackgroundReply.expectReply();
    BackgroundReply.onRefused();
    expect(bridge.finished.mock.calls).toEqual([[{ requestId: 'sent:1', outcome: 'no_reply' }]]);
    expect(BackgroundReply._state().pending).toBe(0);
  });

  test('a closed connection ends what was only sent as lost too', () => {
    BackgroundReply.expectReply();
    BackgroundReply.onConnectionLost();
    expect(bridge.finished.mock.calls).toEqual([[{ requestId: 'sent:1', outcome: 'lost' }]]);
    expect(BackgroundReply._state().pending).toBe(0);
  });

  test('holding stops a microphone already open and ends a Live conversation', async () => {
    const { track, stream } = fakeStream();
    getUserMedia.mockResolvedValue(stream);
    await navigator.mediaDevices.getUserMedia({ audio: true });
    window.LiveConversation = { isActive: () => true, stopConversation: jest.fn() };
    handlers.hold();
    expect(track.readyState).toBe('ended');
    expect(window.LiveConversation.stopConversation).toHaveBeenCalled();
  });

  test('while held, nothing new is sent (reported as not sent); released, it sends again', () => {
    window.safeWsSend = jest.fn().mockReturnValue({ sent: true });
    expect(BackgroundReply.sendReply({ message: 'hi' })).toEqual({ sent: true });
    expect(BackgroundReply._state().pending).toBe(1);

    handlers.hold();
    expect(BackgroundReply.sendReply({ message: 'again' })).toEqual({ sent: false, held: true });
    expect(window.safeWsSend).toHaveBeenCalledTimes(1);
    expect(BackgroundReply._state().pending).toBe(1);

    handlers.release();
    expect(BackgroundReply.sendReply({ message: 'now' })).toEqual({ sent: true });
    delete window.safeWsSend;
  });

  describe('the token that stops an answer', () => {
    const socket = { name: 'now' };
    const token = 'A'.repeat(43);

    beforeEach(() => {
      global.fetch = jest.fn().mockResolvedValue({ status: 204 });
      BackgroundReply.onReplyState({ type: 'reply_state', state: 'running', request_id: 'a' });
    });

    afterEach(() => {
      delete global.fetch;
    });

    test('asks the server to stop the answer, once, on the socket the token came on', () => {
      BackgroundReply.onReplyToken(socket, { request_id: 'a', token });
      expect(BackgroundReply.stopAnswer(socket)).toBe(true);
      expect(global.fetch).toHaveBeenCalledTimes(1);
      const [url, options] = global.fetch.mock.calls[0];
      expect(url).toBe('/reply/cancel/' + token);
      expect(options).toMatchObject({ method: 'POST', credentials: 'same-origin', cache: 'no-store', keepalive: true });
      expect(options.body).toBeUndefined();

      expect(BackgroundReply.stopAnswer(socket)).toBe(false);
      expect(global.fetch).toHaveBeenCalledTimes(1);
    });

    test('is not used on another socket', () => {
      BackgroundReply.onReplyToken(socket, { request_id: 'a', token });
      expect(BackgroundReply.stopAnswer({ name: 'later' })).toBe(false);
      expect(global.fetch).not.toHaveBeenCalled();
    });

    test('is not taken for an answer that is not running', () => {
      BackgroundReply.onReplyToken(socket, { request_id: 'other', token });
      expect(BackgroundReply.stopAnswer(socket)).toBe(false);
      expect(global.fetch).not.toHaveBeenCalled();
    });

    test('goes when its answer finished or the connection closed', () => {
      BackgroundReply.onReplyToken(socket, { request_id: 'a', token });
      BackgroundReply.onReplyState({ type: 'reply_state', state: 'finished', request_id: 'a', outcome: 'done' });
      expect(BackgroundReply.stopAnswer(socket)).toBe(false);

      BackgroundReply.onReplyState({ type: 'reply_state', state: 'running', request_id: 'b' });
      BackgroundReply.onReplyToken(socket, { request_id: 'b', token });
      BackgroundReply.onConnectionLost();
      expect(BackgroundReply.stopAnswer(socket)).toBe(false);
      expect(global.fetch).not.toHaveBeenCalled();
    });

    test('a failed request is let go: the Cancel on the connection follows', async () => {
      global.fetch.mockRejectedValue(new TypeError('network'));
      BackgroundReply.onReplyToken(socket, { request_id: 'a', token });
      expect(BackgroundReply.stopAnswer(socket)).toBe(true);
      await Promise.resolve();
    });
  });

  describe('speech for an answer', () => {
    const running = (id) => BackgroundReply.onReplyState({ type: 'reply_state', state: 'running', request_id: id });
    const finished = (id) => BackgroundReply.onReplyState({ type: 'reply_state', state: 'finished', request_id: id, outcome: 'done' });
    const speech = (id, type = 'web_speech') => ({ type, reply_speech: id });

    test('is taken for an answer that started, also after it ended', () => {
      running('a');
      expect(BackgroundReply.refusesSpeech(speech('a'))).toBe(false);
      finished('a');
      expect(BackgroundReply.refusesSpeech(speech('a', 'audio'))).toBe(false);
      expect(BackgroundReply.refusesSpeech(speech('a', 'tts_complete'))).toBe(false);
    });

    test('is dropped for an answer started before Cancel, whatever started in between', () => {
      running('a');
      finished('a');
      running('ai_user:s');
      BackgroundReply.stopAnswer({});
      expect(BackgroundReply.refusesSpeech(speech('a'))).toBe(true);
      expect(BackgroundReply.refusesSpeech(speech('a', 'tts_complete'))).toBe(true);

      running('b');
      finished('b');
      running('c');
      BackgroundReply.stopAnswer({});
      expect(BackgroundReply.refusesSpeech(speech('b', 'audio'))).toBe(true);
      expect(BackgroundReply.refusesSpeech(speech('c'))).toBe(true);
    });

    test('stays dropped however many answers were cancelled after it', () => {
      for (let i = 0; i < 20; i += 1) {
        running('r' + i);
        BackgroundReply.stopAnswer({});
        finished('r' + i);
      }
      expect(BackgroundReply.refusesSpeech(speech('r0'))).toBe(true);
      expect(BackgroundReply.refusesSpeech(speech('r0', 'tts_complete'))).toBe(true);
      expect(BackgroundReply.refusesSpeech(speech('r19'))).toBe(true);
    });

    test('is taken for an answer started after Cancel, and manual playback always', () => {
      running('a');
      BackgroundReply.stopAnswer({});
      running('b');
      expect(BackgroundReply.refusesSpeech(speech('b'))).toBe(false);
      expect(BackgroundReply.refusesSpeech({ type: 'web_speech', content: 'played by hand' })).toBe(false);
      expect(BackgroundReply.refusesSpeech({ type: 'reply_state', request_id: 'a' })).toBe(false);
    });

    test('is dropped for an answer sent before Cancel that the server takes up only after it', () => {
      BackgroundReply.expectReply();
      BackgroundReply.stopAnswer({});
      running('a');
      expect(BackgroundReply.refusesSpeech(speech('a'))).toBe(true);
      expect(BackgroundReply.refusesSpeech(speech('a', 'tts_complete'))).toBe(true);
    });

    test('is taken for an answer sent after Cancel, even when one sent before it is taken up later', () => {
      BackgroundReply.expectReply();
      BackgroundReply.stopAnswer({});
      BackgroundReply.expectReply();
      running('a');
      running('b');
      expect(BackgroundReply.refusesSpeech(speech('a'))).toBe(true);
      expect(BackgroundReply.refusesSpeech(speech('b'))).toBe(false);
    });

    test('is taken for the next answer when the one sent before Cancel was refused', () => {
      BackgroundReply.expectReply();
      BackgroundReply.stopAnswer({});
      BackgroundReply.onRefused();
      BackgroundReply.expectReply();
      running('b');
      expect(BackgroundReply.refusesSpeech(speech('b'))).toBe(false);
    });

    test.each([
      ['taken up', () => running('ai_user:s')],
      ['refused', () => BackgroundReply.onRefused()]
    ])('is decided by the order sent when an AI User suggestion sent before Cancel is %s', (_label, suggestion) => {
      BackgroundReply.expectReply();
      BackgroundReply.expectReply();
      BackgroundReply.stopAnswer({});
      BackgroundReply.expectReply();
      running('a');
      suggestion();
      running('b');
      expect(BackgroundReply.refusesSpeech(speech('a'))).toBe(true);
      expect(BackgroundReply.refusesSpeech(speech('b'))).toBe(false);
    });

    test('is kept for the latest answers, dropped for one started before them', () => {
      for (let i = 0; i < 17; i += 1) running('r' + i);
      expect(BackgroundReply.refusesSpeech(speech('r0'))).toBe(true);
      expect(BackgroundReply.refusesSpeech(speech('r1'))).toBe(false);
      expect(BackgroundReply.refusesSpeech(speech('r16'))).toBe(false);
    });

    test('is dropped for an answer the page never saw start', () => {
      expect(BackgroundReply.refusesSpeech(speech('unknown'))).toBe(true);
    });
  });

  test('outside the desktop app it keeps counts and reports nothing', () => {
    delete window.electronAPI;
    load();
    BackgroundReply.onReplyState({ type: 'reply_state', state: 'running', request_id: 'a' });
    expect(BackgroundReply._state().running).toBe(1);
    expect(bridge.report).not.toHaveBeenCalled();
  });
});

// websocket.js is not loaded in these tests: the close handler is pinned in
// its source.
describe('the socket close', () => {
  const fs = require('fs');
  const path = require('path');
  const source = fs.readFileSync(path.join(__dirname, '../../docker/services/ruby/public/js/monadic/websocket.js'), 'utf8');
  const onclose = source.slice(source.indexOf('ws.onclose = function'), source.indexOf('ws.onerror = function'));

  test('gives the page back for input when answers were running, and tells it after reconnecting', () => {
    expect(onclose).toMatch(/const repliesLost = window\.BackgroundReply \? window\.BackgroundReply\.onConnectionLost\(\) : 0;/);
    expect(onclose).toMatch(/if \(repliesLost > 0\) \{[\s\S]*window\._replyInterrupted = true;[\s\S]*endInterruptedReply\(\)/);
  });
});

// The token comes in websocket.js and the Cancel button is in monadic.js;
// neither is loaded here, so where they call the module is pinned in their
// source.
describe('where the token is taken and used', () => {
  const fs = require('fs');
  const path = require('path');
  const js = (name) => fs.readFileSync(path.join(__dirname, '../../docker/services/ruby/public/js', name), 'utf8');

  test('the token is taken with the socket it came on', () => {
    const source = js('monadic/websocket.js');
    const branch = source.slice(source.indexOf('case "reply_cancel"'));
    expect(branch).toMatch(/^case "reply_cancel": \{[\s\S]{0,200}window\.BackgroundReply\.onReplyToken\(ws, data\)/);
  });

  test('the token goes before each RESET is sent', () => {
    const source = js('monadic.js');
    const resets = [];
    let at = source.indexOf('window.sendChatSwitch({ message: "RESET" })');
    while (at !== -1) {
      resets.push(at);
      at = source.indexOf('window.sendChatSwitch({ message: "RESET" })', at + 1);
    }
    expect(resets.length).toBeGreaterThan(0);
    resets.forEach((reset) => {
      const forget = source.lastIndexOf('window.BackgroundReply.forgetStopToken()', reset);
      expect(forget).toBeGreaterThan(-1);
      expect(reset - forget).toBeLessThan(200);
    });
  });

  test('Cancel asks for the stop by HTTP before it sends CANCEL on the connection', () => {
    const source = js('monadic.js');
    const cancel = source.indexOf('window.safeWsSend({ message: "CANCEL" })');
    const stop = source.lastIndexOf('window.BackgroundReply.stopAnswer(window.ws)', cancel);
    expect(cancel).toBeGreaterThan(-1);
    expect(stop).toBeGreaterThan(-1);
    expect(cancel - stop).toBeLessThan(200);
  });
});
