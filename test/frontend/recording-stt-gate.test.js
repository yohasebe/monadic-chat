/**
 * @jest-environment jsdom
 */

/**
 * Realtime STT capability-gate tests.
 *
 * Source of truth: docker/services/ruby/public/js/monadic/stt-gate.js
 * — a standalone module so this test can `require()` it directly
 * without dragging in recording.js (which attaches DOM listeners at
 * top level and would explode under jsdom).
 *
 * Until 2026-05-12 this file mirrored the function body verbatim
 * with a "KEEP IN SYNC" docstring. That drift risk is now gone: the
 * module is loaded the same way the browser loads it (assigning to
 * window.SttGate) and the test exercises the exact code that ships.
 */

const path = require('path');
const STT_GATE_PATH = path.resolve(
  __dirname,
  '../../docker/services/ruby/public/js/monadic/stt-gate.js'
);

describe('isRealtimeSttEnabled (capability gate)', () => {
  let SttGate;

  beforeEach(() => {
    document.body.innerHTML = `
      <select id="stt-model">
        <option value="gpt-realtime-whisper" selected>GPT Realtime Whisper</option>
        <option value="gpt-4o-mini-transcribe-2025-12-15">GPT-4o Mini Transcribe</option>
        <option value="whisper-1">Whisper-1</option>
      </select>
    `;
    window.modelSpec = {
      'gpt-realtime-whisper': {
        stt_capability: true,
        supports_realtime_streaming: true
      },
      'gpt-4o-mini-transcribe-2025-12-15': {
        // No supports_realtime_streaming flag → not streaming-capable.
      }
    };
    try { localStorage.clear(); } catch (_) {}

    // Fresh module instance per test so the IIFE re-runs against the
    // current DOM / window state. Without resetModules the cached
    // export would be reused (still correct since the module reads the
    // DOM on each call, but the reset keeps the assignment to
    // window.SttGate consistent with a real page load).
    jest.resetModules();
    delete window.SttGate;
    SttGate = require(STT_GATE_PATH);
  });

  afterEach(() => {
    document.body.innerHTML = '';
    delete window.modelSpec;
    delete window.SttGate;
    try { localStorage.clear(); } catch (_) {}
  });

  it('returns true when the selected model declares supports_realtime_streaming', () => {
    document.getElementById('stt-model').value = 'gpt-realtime-whisper';
    expect(SttGate.isRealtimeSttEnabled()).toBe(true);
  });

  it('returns false when the selected model lacks the flag and localStorage is unset', () => {
    document.getElementById('stt-model').value = 'gpt-4o-mini-transcribe-2025-12-15';
    expect(SttGate.isRealtimeSttEnabled()).toBe(false);
  });

  it('returns false when the selected model is unknown to modelSpec', () => {
    document.getElementById('stt-model').value = 'whisper-1';
    expect(SttGate.isRealtimeSttEnabled()).toBe(false);
  });

  it('falls back to localStorage debug back door when no capability match', () => {
    document.getElementById('stt-model').value = 'whisper-1';
    localStorage.setItem('stt_realtime', '1');
    expect(SttGate.isRealtimeSttEnabled()).toBe(true);
  });

  // Realtime STT is an OpenAI-only WebSocket path. A non-OpenAI STT model
  // (ElevenLabs Scribe, Gemini, Cohere, Mistral Voxtral, xAI) must ALWAYS use
  // the batch path — the realtime endpoint 400s on its model value
  // ("Realtime STT: Invalid value: 'scribe_v2'"). This must hold even when the
  // stale localStorage debug back door is set from a prior OpenAI-realtime run.
  describe('non-OpenAI STT models never enter realtime (batch fallback)', () => {
    const nonOpenAiModels = [
      'scribe_v2', 'scribe_v1', 'gemini-2.5-flash', 'cohere-transcribe-03-2026',
      'voxtral-mini-transcribe-26-02', 'xai-stt-1'
    ];

    nonOpenAiModels.forEach((model) => {
      it(`returns false for ${model} even with the debug back door set`, () => {
        const sel = document.getElementById('stt-model');
        sel.innerHTML = `<option value="${model}" selected>${model}</option>`;
        sel.value = model;
        localStorage.setItem('stt_realtime', '1');
        expect(SttGate.isRealtimeSttEnabled()).toBe(false);
      });
    });

    it('returns false for a non-OpenAI model even if it somehow carried the streaming flag', () => {
      const sel = document.getElementById('stt-model');
      sel.innerHTML = '<option value="scribe_v2" selected>ElevenLabs Scribe v2</option>';
      sel.value = 'scribe_v2';
      window.modelSpec['scribe_v2'] = { supports_realtime_streaming: true };
      expect(SttGate.isRealtimeSttEnabled()).toBe(false);
    });
  });

  it('capability flag takes precedence over localStorage', () => {
    document.getElementById('stt-model').value = 'gpt-realtime-whisper';
    localStorage.setItem('stt_realtime', '0');
    expect(SttGate.isRealtimeSttEnabled()).toBe(true);
  });

  it('returns false when stt-model element is missing entirely and localStorage is unset', () => {
    document.body.innerHTML = '';
    expect(SttGate.isRealtimeSttEnabled()).toBe(false);
  });

  it('handles modelSpec being undefined (e.g. before bundle loaded)', () => {
    delete window.modelSpec;
    document.getElementById('stt-model').value = 'gpt-realtime-whisper';
    expect(SttGate.isRealtimeSttEnabled()).toBe(false);
  });

  it('exposes itself as window.SttGate when the module evaluates', () => {
    // Mirrors the browser-side contract: recording.js calls
    // window.SttGate.isRealtimeSttEnabled() rather than holding a
    // local copy of the function.
    expect(window.SttGate).toBeDefined();
    expect(typeof window.SttGate.isRealtimeSttEnabled).toBe('function');
    expect(window.SttGate.isRealtimeSttEnabled).toBe(SttGate.isRealtimeSttEnabled);
  });
});
