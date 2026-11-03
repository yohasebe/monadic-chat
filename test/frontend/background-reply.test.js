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
    BackgroundReply.onConnectionLost();
    BackgroundReply.onConnectionLost();
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

  test('outside the desktop app it keeps counts and reports nothing', () => {
    delete window.electronAPI;
    load();
    BackgroundReply.onReplyState({ type: 'reply_state', state: 'running', request_id: 'a' });
    expect(BackgroundReply._state().running).toBe(1);
    expect(bridge.report).not.toHaveBeenCalled();
  });
});
