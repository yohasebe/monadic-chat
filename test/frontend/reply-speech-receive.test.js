/**
 * @jest-environment jsdom
 */

// An answer's stop token and speech, through the page's own receiving: the
// socket's message handler, the background-reply module and the speech
// handler are the real ones; only the socket, the synthesizer, audio
// playback and fetch are stand-ins.

const JS = '../../docker/services/ruby/public/js/monadic/';

describe('an answer, as the page receives it', () => {
  let socket;
  let speak;
  let handleAudio;
  let BackgroundReply;

  const deliver = (data) => socket.onmessage({ data: JSON.stringify(data) });
  const started = (id) => deliver({ type: 'reply_state', state: 'running', request_id: id });
  const ended = (id) => deliver({ type: 'reply_state', state: 'finished', request_id: id, outcome: 'done' });

  beforeEach(() => {
    jest.useFakeTimers();
    const sockets = [];
    global.WebSocket = class {
      constructor(url) { this.url = url; sockets.push(this); }
      send() {}
      close() {}
    };
    global.monadicSocketBase = () => 'ws://localhost/';
    global.updateAIUserButtonState = () => {};
    Object.assign(global, require(JS + 'dom-helpers'));
    global.SpeechSynthesisUtterance = class { constructor(text) { this.text = text; } };
    speak = jest.fn();
    window.speechSynthesis = { speak, cancel: jest.fn(), getVoices: () => [] };
    window.ttsSpeak = jest.fn();
    handleAudio = jest.fn();
    window.WsAudioHandler = { handleAudio };
    delete window.electronAPI;
    jest.isolateModules(() => {
      BackgroundReply = require(JS + 'background-reply');
      require(JS + 'ws-tts-handler');
      require(JS + 'websocket');
    });
    socket = sockets[sockets.length - 1];
  });

  afterEach(() => {
    jest.clearAllTimers();
    jest.useRealTimers();
    delete window.BackgroundReply;
    delete window.WsTTSHandler;
    delete window.WsAudioHandler;
    delete window.ttsSpeak;
    delete global.WebSocket;
    delete global.fetch;
  });

  test('stops the answer by its token, unless the server said it was cancelled', () => {
    global.fetch = jest.fn().mockResolvedValue({ status: 204 });
    const token = 'T'.repeat(43);
    started('a');
    deliver({ type: 'reply_cancel', request_id: 'a', token });
    expect(BackgroundReply.stopAnswer(window.ws)).toBe(true);
    expect(global.fetch).toHaveBeenCalledWith('/reply/cancel/' + token, expect.objectContaining({ method: 'POST' }));

    started('b');
    deliver({ type: 'reply_cancel', request_id: 'b', token });
    deliver({ type: 'cancel' });
    expect(BackgroundReply.stopAnswer(window.ws)).toBe(false);
    expect(global.fetch).toHaveBeenCalledTimes(1);
  });

  test('plays what comes for an answer, and nothing that comes for it after Cancel', () => {
    const complete = jest.spyOn(window.WsTTSHandler, 'handleTTSComplete');
    started('a');
    ended('a');
    deliver({ type: 'web_speech', content: 'first', reply_speech: 'a' });
    expect(speak).toHaveBeenCalledTimes(1);

    BackgroundReply.stopAnswer(window.ws);
    deliver({ type: 'web_speech', content: 'late', reply_speech: 'a' });
    deliver({ type: 'audio', content: 'AAAA', reply_speech: 'a' });
    deliver({ type: 'tts_complete', total_segments: 1, reply_speech: 'a' });
    expect(speak).toHaveBeenCalledTimes(1);
    expect(handleAudio).not.toHaveBeenCalled();
    expect(complete).not.toHaveBeenCalled();
  });

  test('plays an answer sent after Cancel, and playback by hand', () => {
    const complete = jest.spyOn(window.WsTTSHandler, 'handleTTSComplete');
    started('a');
    BackgroundReply.stopAnswer(window.ws);
    BackgroundReply.expectReply();
    started('b');
    deliver({ type: 'web_speech', content: 'new', reply_speech: 'b' });
    deliver({ type: 'audio', content: 'BBBB', reply_speech: 'b' });
    deliver({ type: 'tts_complete', total_segments: 1, reply_speech: 'b' });
    deliver({ type: 'web_speech', content: 'by hand' });
    expect(speak).toHaveBeenCalledTimes(2);
    expect(handleAudio).toHaveBeenCalledTimes(1);
    expect(complete).toHaveBeenCalledTimes(1);
  });
});
