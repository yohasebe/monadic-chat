/**
 * ws-sts-playback.js
 *
 * Streaming PCM playback for speech-to-speech (STS) sessions.
 *
 * Why this is separate from ws-audio-playback.js / ws-audio-queue.js:
 * the existing path plays one complete buffer per message and chains the
 * next one from `source.onended`. That is correct for finished TTS audio,
 * but an STS response arrives as ~100ms deltas — chaining them through an
 * onended callback puts a JS event-loop round trip between every chunk,
 * which is audible as gaps and clicks. Buffering them until the response
 * completes would remove the very latency win STS exists for.
 *
 * So chunks are scheduled ahead of time on the audio clock instead: each
 * chunk starts at the exact frame where the previous one ends, with a small
 * jitter buffer (LEAD_IN_SEC) absorbing network variance. One worklet node
 * (sts-stream-worklet.js) plays them, in an AudioContext of their own at the
 * stream's rate: the chunks are written into one sound, sample for sample.
 * A node started per chunk (an AudioBufferSourceNode each) is heard in
 * Electron as a buzz or a pop at the joins, though the schedule is the same.
 *
 * Wire contract:
 *   {"type":"sts_audio_delta","turn_id":..,"content":<base64 PCM16 mono LE>,"sample_rate":24000}
 *   {"type":"sts_audio_done","turn_id":..}
 *   {"type":"sts_audio_cancelled","turn_id":..}
 *
 * `turn_id` matters for barge-in: cancelling a response upstream does not
 * un-send the deltas already in flight, so deltas that arrive after a
 * cancellation must be discarded or the interrupted answer keeps playing.
 */
(function() {
  "use strict";

  // Jitter buffer. Large enough to absorb network variance between ~100ms
  // deltas, small enough to stay negligible against the ~1.1s STS TTFA.
  const LEAD_IN_SEC = 0.16;

  // How many finished/cancelled turn ids to remember, so late deltas from a
  // cancelled turn are still recognised without growing without bound.
  const MAX_REMEMBERED_TURNS = 16;

  // Where the next chunk of the timeline starts, in frames of the player's
  // clock (0: no timeline). Only ever moves forward.
  let nextStartFrame = 0;
  let activeTurnId = null;
  // The turn the timeline was last anchored for. A turn's response can end
  // (finishTurn) and the same turn go on with another one (an answer after
  // a tool call): that one plays after what is still to be heard, not over
  // it.
  let timelineTurnId = null;

  // Speech highlight: per-SEGMENT (= upstream response) playback
  // ranges on the audio clock. The live view maps the current position to
  // the currently spoken sentence; silence between segments (tool calls)
  // is simply not covered by any range, so the highlight cannot advance
  // through it.
  // segmentId -> { turnId, start, end } (AudioContext seconds; end moves as
  // more chunks of the segment are scheduled ahead).
  const segmentTimelines = new Map();

  // turnId -> [start, end] (seconds on the player's clock) of each chunk
  // given to the player and not yet heard to its end.
  const scheduledSpans = new Map();

  // turnId -> the last byte of a chunk of an odd length: a sample is two
  // bytes, and a stream split between them would play every later sample
  // of the next chunk a byte off (noise). The byte goes before the turn's
  // next chunk.
  const leftovers = new Map();

  // Turn ids whose remaining deltas must be dropped, newest last.
  const cancelledTurns = [];

  // The server sends `turn_id: turn && turn[:id]`, so it can legitimately be
  // null when a turn ended before an id existed. A missing id is treated as
  // "unidentified" rather than as the literal key null: two unidentified turns
  // are indistinguishable, so remembering one as cancelled would silently
  // discard every later unidentified turn as well.
  function normalizeTurnId(turnId) {
    return (turnId === null || turnId === undefined || turnId === '') ? null : String(turnId);
  }

  function isCancelled(turnId) {
    if (turnId === null) return false;
    return cancelledTurns.indexOf(turnId) !== -1;
  }

  function rememberCancelled(turnId) {
    // Cannot discard future deltas for a turn we cannot name; stopping what is
    // already scheduled is the most that can be done honestly.
    if (turnId === null) return;
    if (isCancelled(turnId)) return;
    cancelledTurns.push(turnId);
    while (cancelledTurns.length > MAX_REMEMBERED_TURNS) cancelledTurns.shift();
  }

  // ── The player ─────────────────────────────────────────────────────
  const WORKLET_URL = '/js/monadic/sts-stream-worklet.js';
  let playCtx = null;
  let player = null;
  // Messages for the player given before it was ready, in order.
  const pending = [];

  // The player's AudioContext (made at the rate of the first chunk), or
  // null where there is none. Its worklet node is made once the module is
  // loaded; what is given meanwhile waits (flushPending).
  function ensurePlayer(sampleRate) {
    if (!playCtx) {
      const AudioContextClass = window.AudioContext || window.webkitAudioContext;
      if (!AudioContextClass) return null;
      try {
        playCtx = new AudioContextClass({ sampleRate: sampleRate });
      } catch (e) {
        try {
          playCtx = new AudioContextClass();
        } catch (e2) {
          console.error("[STS] Failed to create AudioContext:", e2);
          return null;
        }
      }
      loadPlayer(playCtx);
    }
    // A suspended context does not advance currentTime, so chunks scheduled
    // while suspended stay correctly ordered and play once it resumes.
    if (playCtx.state === 'suspended' && typeof playCtx.resume === 'function') {
      try {
        const p = playCtx.resume();
        if (p && typeof p.catch === 'function') {
          p.catch(function(err) { console.warn("[STS] AudioContext resume failed:", err); });
        }
      } catch (e) {
        console.warn("[STS] AudioContext resume threw:", e);
      }
    }
    return playCtx;
  }

  function loadPlayer(ctx) {
    if (!ctx.audioWorklet || typeof window.AudioWorkletNode !== 'function') {
      console.error("[STS] This browser cannot play the stream (no AudioWorklet).");
      return;
    }
    ctx.audioWorklet.addModule(WORKLET_URL).then(function() {
      if (ctx !== playCtx) return;
      player = new window.AudioWorkletNode(ctx, 'sts-stream-player', { numberOfInputs: 0, outputChannelCount: [1] });
      player.connect(ctx.destination);
      flushPending(ctx);
    }, function(err) {
      console.error("[STS] Failed to load the stream player:", err);
    });
  }

  function post(message, transfer) {
    if (player) player.port.postMessage(message, transfer || []);
    else pending.push([message, transfer]);
  }

  // What was given before the player was ready starts where it was meant
  // to, or, when that has passed, the lead-in from now (the whole timeline
  // moves on together, so its chunks still join).
  function flushPending(ctx) {
    const adds = pending.filter(function(entry) { return entry[0].type === 'add'; });
    if (adds.length > 0) {
      const first = Math.min.apply(null, adds.map(function(entry) { return entry[0].start; }));
      const shift = Math.ceil((ctx.currentTime + LEAD_IN_SEC) * ctx.sampleRate) - first;
      if (shift > 0) {
        adds.forEach(function(entry) { entry[0].start += shift; });
        moveTimeline(shift, ctx.sampleRate);
      }
    }
    pending.splice(0).forEach(function(entry) { player.port.postMessage(entry[0], entry[1] || []); });
  }

  function moveTimeline(frames, rate) {
    const seconds = frames / rate;
    if (nextStartFrame > 0) nextStartFrame += frames;
    scheduledSpans.forEach(function(spans) { spans.forEach(function(span) { span[0] += seconds; span[1] += seconds; }); });
    segmentTimelines.forEach(function(seg) { seg.start += seconds; seg.end += seconds; });
  }

  // Samples at rate `from` taken to rate `to` (straight lines between
  // samples): only for a chunk at another rate than the player's.
  function resample(samples, from, to) {
    if (from === to) return samples;
    const length = Math.max(1, Math.round(samples.length * to / from));
    const out = new Float32Array(length);
    for (let i = 0; i < length; i++) {
      const at = i * from / to;
      const a = Math.floor(at);
      const b = Math.min(a + 1, samples.length - 1);
      out[i] = samples[a] + (samples[b] - samples[a]) * (at - a);
    }
    return out;
  }

  // ── PCM16 LE → Float32 ─────────────────────────────────────────────
  function pcm16ToFloat32(bytes) {
    const numSamples = Math.floor(bytes.length / 2);
    const out = new Float32Array(numSamples);
    for (let i = 0; i < numSamples; i++) {
      const sample = bytes[i * 2] | (bytes[i * 2 + 1] << 8);
      out[i] = (sample < 0x8000 ? sample : sample - 0x10000) / 32768.0;
    }
    return out;
  }

  function base64ToBytes(b64) {
    const binary = atob(b64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return bytes;
  }

  // ── What is scheduled ──────────────────────────────────────────────
  function liveSpans(turnId) {
    const spans = scheduledSpans.get(turnId);
    if (!spans) return [];
    const now = playCtx ? playCtx.currentTime : 0;
    const left = spans.filter(function(span) { return span[1] > now; });
    if (left.length === 0) scheduledSpans.delete(turnId);
    else scheduledSpans.set(turnId, left);
    return left;
  }

  function stopSources(turnId) {
    if (!scheduledSpans.has(turnId)) return;
    post({ type: 'drop', turn: turnId });
    scheduledSpans.delete(turnId);
  }

  // ── scheduleChunk ──────────────────────────────────────────────────
  /**
   * Schedule one PCM chunk for playback.
   * @param {string} turnId - Response turn this chunk belongs to.
   * @param {Uint8Array} pcmBytes - PCM16 mono little-endian samples.
   * @param {number} sampleRate - Sample rate of pcmBytes (e.g. 24000).
   * @param {string} [segmentId] - Upstream response id; defaults
   *   to turnId so single-response turns need no special handling.
   * @returns {boolean} true if scheduled, false if dropped.
   */
  function scheduleChunk(rawTurnId, pcmBytes, sampleRate, segmentId) {
    const turnId = normalizeTurnId(rawTurnId);
    if (isCancelled(turnId)) return false;
    if (!pcmBytes || pcmBytes.length === 0) return false;
    const left = leftovers.get(turnId);
    if (left !== undefined) {
      const joined = new Uint8Array(pcmBytes.length + 1);
      joined[0] = left;
      joined.set(pcmBytes, 1);
      pcmBytes = joined;
      leftovers.delete(turnId);
    }
    if (pcmBytes.length % 2 === 1) {
      leftovers.set(turnId, pcmBytes[pcmBytes.length - 1]);
      pcmBytes = pcmBytes.subarray(0, pcmBytes.length - 1);
    }
    if (pcmBytes.length < 2) return false;

    const ctx = ensurePlayer(sampleRate);
    if (!ctx) return false;

    // A new turn starts its own timeline; do not inherit the previous one's
    // tail, which may be in the past by now. Two unidentified turns compare
    // equal here and so share a timeline — harmless, because the underrun
    // re-prime below moves a stale anchor forward anyway.
    //
    // Mono-voice invariant: only one assistant turn may be audible at a
    // time. A turn switch without an explicit cancel happens whenever the
    // upstream moved on without emitting a cancellation we could attribute
    // (otherwise two responses talk over each other), so
    // the switch itself silences every other turn's scheduled tail.
    if (turnId !== activeTurnId) {
      Array.from(scheduledSpans.keys()).forEach(function(id) {
        if (id !== turnId) stopSources(id);
      });
      // The same turn going on keeps its timeline (its next response plays
      // after the one still being heard); another turn starts its own.
      if (turnId === null || turnId !== timelineTurnId) nextStartFrame = 0;
      activeTurnId = turnId;
      timelineTurnId = turnId;
    }

    const rate = ctx.sampleRate;
    const samples = resample(pcm16ToFloat32(pcmBytes), sampleRate, rate);
    if (samples.length === 0) return false;

    // A chunk goes right after the one before it while that one has not
    // ended (a gap there is heard as a click; audio that comes just in time
    // would get one at every chunk). Only a timeline already passed (an
    // underrun, or a new timeline) starts after the lead-in from now — never
    // rewind the timeline, since a chunk given for frames already played is
    // cut and would collapse every remaining chunk into one instant.
    const nowFrame = Math.round(ctx.currentTime * rate);
    const startFrame = nextStartFrame > nowFrame ? nextStartFrame : nowFrame + Math.round(LEAD_IN_SEC * rate);
    // The length is taken first: handing the samples over (a transfer)
    // leaves this array empty.
    const length = samples.length;
    post({ type: 'add', turn: turnId, start: startFrame, samples: samples }, [samples.buffer]);
    nextStartFrame = startFrame + length;
    const startAt = startFrame / rate;
    const endAt = nextStartFrame / rate;
    const spans = scheduledSpans.get(turnId) || [];
    spans.push([startAt, endAt]);
    scheduledSpans.set(turnId, spans);

    // Extend the segment's playback range on the audio clock.
    const segId = (segmentId === null || segmentId === undefined || segmentId === '')
      ? turnId : String(segmentId);
    if (segId !== null) {
      const seg = segmentTimelines.get(segId) || { turnId: turnId, start: startAt, end: startAt };
      seg.end = endAt;
      segmentTimelines.set(segId, seg);
    }

    if (typeof window.setTtsPlaybackStarted === 'function') {
      window.setTtsPlaybackStarted(true);
      if (typeof window.checkAndHideSpinner === 'function') window.checkAndHideSpinner();
    }
    return true;
  }

  // ── Turn lifecycle ─────────────────────────────────────────────────
  function finishTurn(rawTurnId) {
    // Scheduled audio plays out; only the timeline anchor is released so the
    // next turn starts fresh.
    if (normalizeTurnId(rawTurnId) === activeTurnId) activeTurnId = null;
  }

  function cancelTurn(rawTurnId) {
    const turnId = normalizeTurnId(rawTurnId);
    rememberCancelled(turnId);
    leftovers.delete(turnId);
    stopSources(turnId);
    segmentTimelines.forEach(function(seg, segId) {
      if (seg.turnId === turnId) segmentTimelines.delete(segId);
    });
    if (turnId === activeTurnId) {
      activeTurnId = null;
      nextStartFrame = 0;
    }
    if (turnId === timelineTurnId) timelineTurnId = null;
  }

  function stopAll() {
    if (scheduledSpans.size > 0) post({ type: 'dropAll' });
    scheduledSpans.clear();
    segmentTimelines.clear();
    leftovers.clear();
    activeTurnId = null;
    timelineTurnId = null;
    nextStartFrame = 0;
  }

  // What is audible RIGHT NOW, as a segment-local playback
  // position. Returns null during silence (nothing scheduled covers the
  // clock — e.g. while a tool runs), which the caller treats as "freeze,
  // do not advance". offset/total are seconds within the segment's
  // scheduled range; total grows as chunks arrive ahead of realtime.
  function getPlaybackPosition() {
    const ctx = playCtx;
    if (!ctx) return null;
    const now = ctx.currentTime;
    let best = null;
    segmentTimelines.forEach(function(seg, segId) {
      if (now >= seg.start && now < seg.end && (!best || seg.start > best.start)) {
        best = { segmentId: segId, offset: now - seg.start, total: seg.end - seg.start, start: seg.start };
      }
    });
    return best;
  }

  // ── WebSocket message handlers ─────────────────────────────────────
  function handleStsAudioDelta(data) {
    if (!data || !data.content) return false;
    let bytes;
    try {
      bytes = base64ToBytes(data.content);
    } catch (e) {
      console.error("[STS] Failed to decode audio delta:", e);
      return false;
    }
    const sampleRate = Number(data.sample_rate) || 24000;
    return scheduleChunk(data.turn_id, bytes, sampleRate, data.segment_id);
  }

  function handleStsAudioDone(data) {
    if (!data) return;
    finishTurn(data.turn_id);
  }

  function handleStsAudioCancelled(data) {
    if (!data) return;
    cancelTurn(data.turn_id);
  }

  // ── Namespace export ───────────────────────────────────────────────
  const ns = {
    LEAD_IN_SEC: LEAD_IN_SEC,
    scheduleChunk: scheduleChunk,
    finishTurn: finishTurn,
    cancelTurn: cancelTurn,
    stopAll: stopAll,
    handleStsAudioDelta: handleStsAudioDelta,
    handleStsAudioDone: handleStsAudioDone,
    handleStsAudioCancelled: handleStsAudioCancelled,
    getPlaybackPosition: getPlaybackPosition,
    // True while any turn still has audio scheduled or playing. Used by the
    // Live Conversation echo gate (mic chunks are energy-gated while the
    // assistant is audible) — arrival-time flags are wrong for this because
    // deltas arrive faster than realtime and playback outlives them.
    isPlaying: function() {
      return Array.from(scheduledSpans.keys()).some(function(id) { return liveSpans(id).length > 0; });
    },
    // Makes the player ready (its worklet loaded) before the first chunk.
    prepare: function(sampleRate) { return !!ensurePlayer(sampleRate || 24000); },
    // Diagnostics / tests
    getNextStartTime: function() { return playCtx && nextStartFrame > 0 ? nextStartFrame / playCtx.sampleRate : 0; },
    getActiveTurnId: function() { return activeTurnId; },
    getScheduledCount: function(turnId) { return liveSpans(normalizeTurnId(turnId)).length; }
  };

  window.WsStsPlayback = ns;

  // Support for Jest testing environment (CommonJS)
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = ns;
  }
})();
