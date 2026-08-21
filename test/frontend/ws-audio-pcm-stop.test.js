/**
 * @jest-environment jsdom
 */

/**
 * Regression tests for PCM playback stop.
 *
 * PCM audio (the audio/L16 path used by Gemini TTS, and the future
 * speech-to-speech path) plays through an AudioBufferSourceNode, not an
 * <audio> element. It was therefore invisible to stopAllActiveAudio(), and
 * ws-audio-queue.js tracked it in a module-local variable that was never
 * assigned — so no stop path ever called .stop() on the live source and PCM
 * audio played to completion regardless of the user stopping playback.
 *
 * These tests lock the contract: every stop path must reach the real source,
 * and stopping must not advance the audio queue.
 */

function makeFakeAudioContext() {
  const started = [];
  return {
    state: 'running',
    destination: {},
    _startedSources: started,
    createBuffer(channels, length) {
      return { getChannelData: () => new Float32Array(length) };
    },
    createBufferSource() {
      const source = {
        buffer: null,
        onended: null,
        connect: jest.fn(),
        start: jest.fn(),
        stop: jest.fn()
      };
      started.push(source);
      return source;
    }
  };
}

let Playback;

beforeEach(() => {
  jest.resetModules();
  window.audioCtx = makeFakeAudioContext();
  window._currentPCMSource = null;
  window.ttsPlaybackCallback = null;
  Playback = require('../../docker/services/ruby/public/js/monadic/ws-audio-playback');
});

afterEach(() => {
  delete window.audioCtx;
  delete window._currentPCMSource;
  delete window.ttsPlaybackCallback;
});

function playOneChunk() {
  // 4 samples of silence (PCM16 little-endian => 2 bytes per sample)
  Playback.playPCMAudio(new Uint8Array(8), 24000);
  return window.audioCtx._startedSources[window.audioCtx._startedSources.length - 1];
}

describe('PCM playback stop', () => {
  it('playPCMAudio publishes the live source so stop paths can reach it', () => {
    const source = playOneChunk();

    expect(source.start).toHaveBeenCalled();
    expect(window._currentPCMSource).toBe(source);
  });

  it('stopPCMPlayback stops the live source and clears the reference', () => {
    const source = playOneChunk();

    Playback.stopPCMPlayback();

    expect(source.stop).toHaveBeenCalled();
    expect(window._currentPCMSource).toBeNull();
  });

  it('stopAllActiveAudio stops PCM playback (regression: PCM was not covered)', () => {
    const source = playOneChunk();

    Playback.stopAllActiveAudio();

    expect(source.stop).toHaveBeenCalled();
    expect(window._currentPCMSource).toBeNull();
  });

  it('stopping does not invoke ttsPlaybackCallback, so the queue is not advanced', () => {
    const source = playOneChunk();
    const advanceQueue = jest.fn();
    window.ttsPlaybackCallback = advanceQueue;

    Playback.stopPCMPlayback();

    // onended fires on stop() as well as on natural completion; the handler
    // must be detached first or a stop request would start the next segment.
    expect(source.onended).toBeNull();
    expect(advanceQueue).not.toHaveBeenCalled();
  });

  it('natural completion still advances the queue', () => {
    const source = playOneChunk();
    const advanceQueue = jest.fn();
    window.ttsPlaybackCallback = advanceQueue;

    source.onended();

    expect(advanceQueue).toHaveBeenCalledWith(true);
    expect(window._currentPCMSource).toBeNull();
  });

  it('stopPCMPlayback is a no-op when nothing is playing', () => {
    expect(() => Playback.stopPCMPlayback()).not.toThrow();
    expect(window._currentPCMSource).toBeNull();
  });

  it('survives a source whose stop() throws', () => {
    const source = playOneChunk();
    source.stop.mockImplementation(() => { throw new Error('InvalidStateError'); });
    const warnSpy = jest.spyOn(console, 'warn').mockImplementation();

    expect(() => Playback.stopPCMPlayback()).not.toThrow();
    expect(window._currentPCMSource).toBeNull();

    warnSpy.mockRestore();
  });
});

describe('clearAudioQueue reaches PCM playback', () => {
  it('stops the live PCM source (regression: tracked a never-assigned local)', () => {
    // Bundle order: ws-audio-playback.js loads before ws-audio-queue.js, so the
    // queue captures the populated window.WsAudioPlayback namespace.
    const Queue = require('../../docker/services/ruby/public/js/monadic/ws-audio-queue');
    const source = playOneChunk();

    Queue.clearAudioQueue();

    expect(source.stop).toHaveBeenCalled();
    expect(window._currentPCMSource).toBeNull();
  });
});
