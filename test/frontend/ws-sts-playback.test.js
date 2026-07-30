/**
 * @jest-environment jsdom
 */

/**
 * Tests for the streaming PCM scheduler used by speech-to-speech playback.
 *
 * The invariants that matter are all about *when* each chunk starts:
 * contiguous scheduling is what removes the gaps the onended-chained queue
 * would produce, and never rewinding the timeline is what stops an underrun
 * from collapsing every remaining chunk into one instant.
 */

// These tests assert on chunk durations and decode base64, so the stubbed
// binary globals from test/setup.js would make them measure nothing.
const { useRealBinaryGlobals } = require('../helpers');

let restoreBinaryGlobals;
beforeAll(() => { restoreBinaryGlobals = useRealBinaryGlobals(); });
afterAll(() => { restoreBinaryGlobals(); });

function makeFakeAudioContext() {
  return {
    state: 'running',
    currentTime: 0,
    destination: {},
    createdSources: [],
    resume: jest.fn(),
    createBuffer(channels, length, sampleRate) {
      const data = new Float32Array(length);
      return {
        length: length,
        sampleRate: sampleRate,
        duration: length / sampleRate,
        getChannelData: () => data
      };
    },
    createBufferSource() {
      const ctx = this;
      const source = {
        buffer: null,
        onended: null,
        startedAt: null,
        stopped: false,
        connect: jest.fn(),
        start: jest.fn(function(when) { source.startedAt = when; }),
        stop: jest.fn(function() { source.stopped = true; })
      };
      ctx.createdSources.push(source);
        return source;
    }
  };
}

const SAMPLE_RATE = 24000;

// 100ms of PCM16 mono at 24kHz = 2400 samples = 4800 bytes
function chunkBytes(ms) {
  return new Uint8Array(Math.round((SAMPLE_RATE * ms) / 1000) * 2);
}

let Sts;
let ctx;

beforeEach(() => {
  jest.resetModules();
  ctx = makeFakeAudioContext();
  window.audioCtx = ctx;
  Sts = require('../../docker/services/ruby/public/js/monadic/ws-sts-playback');
});

afterEach(() => {
  delete window.audioCtx;
  delete window.WsStsPlayback;
});

describe('scheduling', () => {
  it('starts the first chunk after the lead-in jitter buffer', () => {
    ctx.currentTime = 5;

    Sts.scheduleChunk('t1', chunkBytes(100), SAMPLE_RATE);

    expect(ctx.createdSources[0].startedAt).toBeCloseTo(5 + Sts.LEAD_IN_SEC, 6);
  });

  it('schedules consecutive chunks contiguously (no gaps)', () => {
    Sts.scheduleChunk('t1', chunkBytes(100), SAMPLE_RATE);
    Sts.scheduleChunk('t1', chunkBytes(100), SAMPLE_RATE);
    Sts.scheduleChunk('t1', chunkBytes(100), SAMPLE_RATE);

    const [a, b, c] = ctx.createdSources;
    expect(b.startedAt).toBeCloseTo(a.startedAt + 0.1, 6);
    expect(c.startedAt).toBeCloseTo(b.startedAt + 0.1, 6);
  });

  it('handles chunks of differing length', () => {
    Sts.scheduleChunk('t1', chunkBytes(100), SAMPLE_RATE);
    Sts.scheduleChunk('t1', chunkBytes(250), SAMPLE_RATE);
    Sts.scheduleChunk('t1', chunkBytes(50), SAMPLE_RATE);

    const [a, b, c] = ctx.createdSources;
    expect(b.startedAt).toBeCloseTo(a.startedAt + 0.1, 6);
    expect(c.startedAt).toBeCloseTo(b.startedAt + 0.25, 6);
  });

  it('connects each source to the destination', () => {
    Sts.scheduleChunk('t1', chunkBytes(100), SAMPLE_RATE);

    expect(ctx.createdSources[0].connect).toHaveBeenCalledWith(ctx.destination);
  });

  // The chunk payloads elsewhere in this file are silence, so a decoder that
  // mangled sign or byte order would still schedule correctly-sized buffers
  // and every timing assertion would pass while the audio came out as noise.
  it('decodes PCM16 little-endian samples to the right float values', () => {
    const written = [];
    ctx.createBuffer = (channels, length, sampleRate) => {
      const data = new Float32Array(length);
      written.push({ data, sampleRate });
      return { getChannelData: () => data };
    };

    // 0x0000 = 0, 0x7FFF = max positive, 0x8000 = min negative, 0xFFFF = -1
    const bytes = new Uint8Array([0x00, 0x00, 0xff, 0x7f, 0x00, 0x80, 0xff, 0xff]);
    Sts.scheduleChunk('t1', bytes, SAMPLE_RATE);

    const samples = written[0].data;
    expect(samples[0]).toBeCloseTo(0, 6);
    expect(samples[1]).toBeCloseTo(32767 / 32768, 6);
    expect(samples[2]).toBeCloseTo(-1.0, 6);
    expect(samples[3]).toBeCloseTo(-1 / 32768, 6);
  });

  it('ignores empty or undersized payloads', () => {
    expect(Sts.scheduleChunk('t1', new Uint8Array(0), SAMPLE_RATE)).toBe(false);
    expect(Sts.scheduleChunk('t1', new Uint8Array(1), SAMPLE_RATE)).toBe(false);
    expect(ctx.createdSources).toHaveLength(0);
  });
});

describe('underrun', () => {
  it('re-primes forward when playback has overtaken the timeline', () => {
    Sts.scheduleChunk('t1', chunkBytes(100), SAMPLE_RATE);
    const first = ctx.createdSources[0];

    // Nothing arrived for a while: playback drained and the clock moved past
    // the scheduled tail.
    ctx.currentTime = first.startedAt + 5;
    Sts.scheduleChunk('t1', chunkBytes(100), SAMPLE_RATE);

    const second = ctx.createdSources[1];
    expect(second.startedAt).toBeCloseTo(ctx.currentTime + Sts.LEAD_IN_SEC, 6);
  });

  it('never schedules a chunk in the past', () => {
    ctx.currentTime = 10;
    Sts.scheduleChunk('t1', chunkBytes(100), SAMPLE_RATE);
    ctx.currentTime = 100;
    Sts.scheduleChunk('t1', chunkBytes(100), SAMPLE_RATE);

    ctx.createdSources.forEach(function(source) {
      expect(source.startedAt).toBeGreaterThanOrEqual(10);
    });
    expect(ctx.createdSources[1].startedAt).toBeGreaterThan(ctx.currentTime);
  });

  it('does not rewind the timeline when the clock is still behind it', () => {
    Sts.scheduleChunk('t1', chunkBytes(100), SAMPLE_RATE);
    const tail = Sts.getNextStartTime();

    // Clock advanced a little but the buffer is still ahead — keep chaining.
    ctx.currentTime = 0.05;
    Sts.scheduleChunk('t1', chunkBytes(100), SAMPLE_RATE);

    expect(ctx.createdSources[1].startedAt).toBeCloseTo(tail, 6);
  });
});

describe('turn boundaries', () => {
  it('starts a new turn on its own timeline', () => {
    Sts.scheduleChunk('t1', chunkBytes(100), SAMPLE_RATE);
    Sts.scheduleChunk('t1', chunkBytes(100), SAMPLE_RATE);

    ctx.currentTime = 20;
    Sts.scheduleChunk('t2', chunkBytes(100), SAMPLE_RATE);

    expect(ctx.createdSources[2].startedAt).toBeCloseTo(20 + Sts.LEAD_IN_SEC, 6);
    expect(Sts.getActiveTurnId()).toBe('t2');
  });

  it('finishTurn releases the timeline anchor without stopping audio', () => {
    Sts.scheduleChunk('t1', chunkBytes(100), SAMPLE_RATE);

    Sts.finishTurn('t1');

    expect(ctx.createdSources[0].stop).not.toHaveBeenCalled();
    expect(Sts.getActiveTurnId()).toBeNull();
  });
});

describe('barge-in', () => {
  it('cancelTurn stops every source scheduled for that turn', () => {
    Sts.scheduleChunk('t1', chunkBytes(100), SAMPLE_RATE);
    Sts.scheduleChunk('t1', chunkBytes(100), SAMPLE_RATE);

    Sts.cancelTurn('t1');

    ctx.createdSources.forEach(function(source) {
      expect(source.stop).toHaveBeenCalled();
    });
    expect(Sts.getScheduledCount('t1')).toBe(0);
  });

  it('discards deltas that arrive after the turn was cancelled', () => {
    Sts.scheduleChunk('t1', chunkBytes(100), SAMPLE_RATE);
    Sts.cancelTurn('t1');

    // Upstream cancellation does not un-send deltas already in flight.
    const scheduled = Sts.scheduleChunk('t1', chunkBytes(100), SAMPLE_RATE);

    expect(scheduled).toBe(false);
    expect(ctx.createdSources).toHaveLength(1);
  });

  it('does not block a different turn after a cancellation', () => {
    Sts.scheduleChunk('t1', chunkBytes(100), SAMPLE_RATE);
    Sts.cancelTurn('t1');

    expect(Sts.scheduleChunk('t2', chunkBytes(100), SAMPLE_RATE)).toBe(true);
  });

  it('detaches onended before stopping so no per-source cleanup fires', () => {
    Sts.scheduleChunk('t1', chunkBytes(100), SAMPLE_RATE);
    const source = ctx.createdSources[0];

    Sts.cancelTurn('t1');

    expect(source.onended).toBeNull();
  });

  // The server sends `turn_id: turn && turn[:id]`, so an id-less turn is a
  // real case, not a defensive hypothetical.
  describe('unidentified turns (turn_id null)', () => {
    it('plays audio that arrives without a turn id', () => {
      expect(Sts.scheduleChunk(null, chunkBytes(100), SAMPLE_RATE)).toBe(true);
      expect(ctx.createdSources).toHaveLength(1);
    });

    it('cancelling an unidentified turn stops what is already scheduled', () => {
      Sts.scheduleChunk(null, chunkBytes(100), SAMPLE_RATE);

      Sts.cancelTurn(null);

      expect(ctx.createdSources[0].stop).toHaveBeenCalled();
    });

    it('does not deafen every later unidentified turn', () => {
      Sts.scheduleChunk(null, chunkBytes(100), SAMPLE_RATE);
      Sts.cancelTurn(null);

      // Two unnamed turns are indistinguishable, so remembering the first as
      // cancelled would silently drop this one forever.
      expect(Sts.scheduleChunk(null, chunkBytes(100), SAMPLE_RATE)).toBe(true);
    });

    it('treats undefined and empty string the same as null', () => {
      expect(Sts.scheduleChunk(undefined, chunkBytes(100), SAMPLE_RATE)).toBe(true);
      expect(Sts.scheduleChunk('', chunkBytes(100), SAMPLE_RATE)).toBe(true);
      expect(Sts.getActiveTurnId()).toBeNull();
    });

    it('still discards late deltas for a named cancelled turn', () => {
      Sts.scheduleChunk('t1', chunkBytes(100), SAMPLE_RATE);
      Sts.cancelTurn('t1');

      expect(Sts.scheduleChunk('t1', chunkBytes(100), SAMPLE_RATE)).toBe(false);
    });

    it('accepts a numeric turn id without treating it as a different turn', () => {
      Sts.scheduleChunk(7, chunkBytes(100), SAMPLE_RATE);
      Sts.scheduleChunk('7', chunkBytes(100), SAMPLE_RATE);

      const [a, b] = ctx.createdSources;
      expect(b.startedAt).toBeCloseTo(a.startedAt + 0.1, 6);
    });
  });

  it('stopAll stops sources across all turns', () => {
    Sts.scheduleChunk('t1', chunkBytes(100), SAMPLE_RATE);
    Sts.scheduleChunk('t2', chunkBytes(100), SAMPLE_RATE);

    Sts.stopAll();

    ctx.createdSources.forEach(function(source) {
      expect(source.stop).toHaveBeenCalled();
    });
    expect(Sts.getNextStartTime()).toBe(0);
    expect(Sts.getActiveTurnId()).toBeNull();
  });
});

describe('message handlers', () => {
  function b64(bytes) {
    let binary = '';
    bytes.forEach(function(b) { binary += String.fromCharCode(b); });
    return btoa(binary);
  }

  it('decodes base64 PCM from an sts_audio_delta message', () => {
    const handled = Sts.handleStsAudioDelta({
      type: 'sts_audio_delta',
      turn_id: 't1',
      content: b64(chunkBytes(100)),
      sample_rate: SAMPLE_RATE
    });

    expect(handled).toBe(true);
    expect(ctx.createdSources).toHaveLength(1);
  });

  it('defaults to 24kHz when sample_rate is absent', () => {
    Sts.handleStsAudioDelta({ turn_id: 't1', content: b64(chunkBytes(100)) });
    Sts.handleStsAudioDelta({ turn_id: 't1', content: b64(chunkBytes(100)) });

    const [a, b] = ctx.createdSources;
    expect(b.startedAt).toBeCloseTo(a.startedAt + 0.1, 6);
  });

  it('ignores a delta with no content', () => {
    expect(Sts.handleStsAudioDelta({ turn_id: 't1' })).toBe(false);
    expect(Sts.handleStsAudioDelta(null)).toBe(false);
  });

  it('sts_audio_cancelled discards subsequent deltas for that turn', () => {
    Sts.handleStsAudioDelta({ turn_id: 't1', content: b64(chunkBytes(100)) });
    Sts.handleStsAudioCancelled({ turn_id: 't1' });

    const handled = Sts.handleStsAudioDelta({ turn_id: 't1', content: b64(chunkBytes(100)) });

    expect(handled).toBe(false);
    expect(ctx.createdSources).toHaveLength(1);
  });

  it('sts_audio_done leaves scheduled audio playing', () => {
    Sts.handleStsAudioDelta({ turn_id: 't1', content: b64(chunkBytes(100)) });

    Sts.handleStsAudioDone({ turn_id: 't1' });

    expect(ctx.createdSources[0].stop).not.toHaveBeenCalled();
  });
});

describe('integration with existing stop paths', () => {
  it('stopAllActiveAudio also stops streaming STS playback', () => {
    const Playback = require('../../docker/services/ruby/public/js/monadic/ws-audio-playback');
    Sts.scheduleChunk('t1', chunkBytes(100), SAMPLE_RATE);

    Playback.stopAllActiveAudio();

    expect(ctx.createdSources[0].stop).toHaveBeenCalled();
    expect(Sts.getActiveTurnId()).toBeNull();
  });
});
