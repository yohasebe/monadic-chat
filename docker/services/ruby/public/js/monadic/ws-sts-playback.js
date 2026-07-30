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
 * So chunks are scheduled ahead of time against `audioCtx.currentTime`
 * instead: each chunk is started at the exact moment the previous one
 * ends, with a small jitter buffer (LEAD_IN_SEC) absorbing network
 * variance.
 *
 * Wire contract (see tmp/memo/sts_pipeline_v1.0.md §3-5):
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

  // Playback position in AudioContext time. Only ever moves forward.
  let nextStartTime = 0;
  let activeTurnId = null;

  // turnId -> Set of AudioBufferSourceNode still scheduled or playing.
  const scheduledSources = new Map();

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

  // ── AudioContext ───────────────────────────────────────────────────
  function ensureAudioContext() {
    if (!window.audioCtx) {
      const AudioContextClass = window.AudioContext || window.webkitAudioContext;
      if (!AudioContextClass) return null;
      try {
        window.audioCtx = new AudioContextClass();
      } catch (e) {
        console.error("[STS] Failed to create AudioContext:", e);
        return null;
      }
    }
    // A suspended context does not advance currentTime, so chunks scheduled
    // while suspended stay correctly ordered and play once it resumes.
    if (window.audioCtx.state === 'suspended' && typeof window.audioCtx.resume === 'function') {
      try {
        const p = window.audioCtx.resume();
        if (p && typeof p.catch === 'function') {
          p.catch(function(err) { console.warn("[STS] AudioContext resume failed:", err); });
        }
      } catch (e) {
        console.warn("[STS] AudioContext resume threw:", e);
      }
    }
    return window.audioCtx;
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

  // ── Source bookkeeping ─────────────────────────────────────────────
  function trackSource(turnId, source) {
    let set = scheduledSources.get(turnId);
    if (!set) {
      set = new Set();
      scheduledSources.set(turnId, set);
    }
    set.add(source);
    source.onended = function() {
      set.delete(source);
      if (set.size === 0) scheduledSources.delete(turnId);
    };
  }

  function stopSources(turnId) {
    const set = scheduledSources.get(turnId);
    if (!set) return;
    set.forEach(function(source) {
      try {
        // Detach first: onended fires on stop() too, and we are discarding
        // this turn wholesale rather than reacting per source.
        source.onended = null;
        source.stop();
      } catch (e) {
        // stop() throws if the source already ended.
      }
    });
    set.clear();
    scheduledSources.delete(turnId);
  }

  // ── scheduleChunk ──────────────────────────────────────────────────
  /**
   * Schedule one PCM chunk for playback.
   * @param {string} turnId - Response turn this chunk belongs to.
   * @param {Uint8Array} pcmBytes - PCM16 mono little-endian samples.
   * @param {number} sampleRate - Sample rate of pcmBytes (e.g. 24000).
   * @returns {boolean} true if scheduled, false if dropped.
   */
  function scheduleChunk(rawTurnId, pcmBytes, sampleRate) {
    const turnId = normalizeTurnId(rawTurnId);
    if (isCancelled(turnId)) return false;
    if (!pcmBytes || pcmBytes.length < 2) return false;

    const ctx = ensureAudioContext();
    if (!ctx) return false;

    // A new turn starts its own timeline; do not inherit the previous one's
    // tail, which may be in the past by now. Two unidentified turns compare
    // equal here and so share a timeline — harmless, because the underrun
    // re-prime below moves a stale anchor forward anyway.
    if (turnId !== activeTurnId) {
      activeTurnId = turnId;
      nextStartTime = 0;
    }

    const samples = pcm16ToFloat32(pcmBytes);
    if (samples.length === 0) return false;

    let buffer;
    try {
      buffer = ctx.createBuffer(1, samples.length, sampleRate);
      buffer.getChannelData(0).set(samples);
    } catch (e) {
      console.error("[STS] Failed to create audio buffer:", e);
      return false;
    }

    const source = ctx.createBufferSource();
    source.buffer = buffer;
    source.connect(ctx.destination);

    // Underrun: deltas fell behind playback, so the timeline has already
    // passed. Re-prime forward from now — never rewind nextStartTime, since
    // start() with a past time plays immediately and would collapse every
    // remaining chunk into one instant.
    const earliest = ctx.currentTime + LEAD_IN_SEC;
    const startAt = nextStartTime > earliest ? nextStartTime : earliest;

    trackSource(turnId, source);
    try {
      source.start(startAt);
    } catch (e) {
      console.error("[STS] Failed to start audio source:", e);
      return false;
    }
    nextStartTime = startAt + (samples.length / sampleRate);

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
    stopSources(turnId);
    if (turnId === activeTurnId) {
      activeTurnId = null;
      nextStartTime = 0;
    }
  }

  function stopAll() {
    Array.from(scheduledSources.keys()).forEach(stopSources);
    scheduledSources.clear();
    activeTurnId = null;
    nextStartTime = 0;
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
    return scheduleChunk(data.turn_id, bytes, sampleRate);
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
    // Diagnostics / tests
    getNextStartTime: function() { return nextStartTime; },
    getActiveTurnId: function() { return activeTurnId; },
    getScheduledCount: function(turnId) {
      const set = scheduledSources.get(normalizeTurnId(turnId));
      return set ? set.size : 0;
    }
  };

  window.WsStsPlayback = ns;

  // Support for Jest testing environment (CommonJS)
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = ns;
  }
})();
