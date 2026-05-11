/**
 * @jest-environment jsdom
 */

/**
 * Realtime STT capability-gate (`isRealtimeSttEnabled`) tests.
 *
 * The function under test lives in
 *   docker/services/ruby/public/js/monadic/recording.js
 * but recording.js cannot be required directly in jsdom because it
 * attaches DOM listeners at top level (voiceButton.click, document
 * keydown capture). To avoid that side-effect, we mirror the function
 * verbatim here. KEEP IN SYNC with the source.
 *
 * Source body (as of Phase 4):
 *
 *   function isRealtimeSttEnabled() {
 *     const sttModelEl = $id('stt-model');
 *     const model = sttModelEl ? sttModelEl.value : '';
 *     if (model && typeof window !== 'undefined' && window.modelSpec
 *         && window.modelSpec[model]
 *         && window.modelSpec[model].supports_realtime_streaming) {
 *       return true;
 *     }
 *     try { return localStorage.getItem('stt_realtime') === '1'; }
 *     catch (_) { return false; }
 *   }
 */

function $id(id) { return document.getElementById(id); }

function isRealtimeSttEnabled() {
  const sttModelEl = $id('stt-model');
  const model = sttModelEl ? sttModelEl.value : '';
  if (model && typeof window !== 'undefined' && window.modelSpec
      && window.modelSpec[model]
      && window.modelSpec[model].supports_realtime_streaming) {
    return true;
  }
  try { return localStorage.getItem('stt_realtime') === '1'; }
  catch (_) { return false; }
}

describe('isRealtimeSttEnabled (capability gate)', () => {
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
  });

  afterEach(() => {
    document.body.innerHTML = '';
    delete window.modelSpec;
    try { localStorage.clear(); } catch (_) {}
  });

  it('returns true when the selected model declares supports_realtime_streaming', () => {
    $id('stt-model').value = 'gpt-realtime-whisper';
    expect(isRealtimeSttEnabled()).toBe(true);
  });

  it('returns false when the selected model lacks the flag and localStorage is unset', () => {
    $id('stt-model').value = 'gpt-4o-mini-transcribe-2025-12-15';
    expect(isRealtimeSttEnabled()).toBe(false);
  });

  it('returns false when the selected model is unknown to modelSpec', () => {
    $id('stt-model').value = 'whisper-1';
    expect(isRealtimeSttEnabled()).toBe(false);
  });

  it('falls back to localStorage debug back door when no capability match', () => {
    $id('stt-model').value = 'whisper-1';
    localStorage.setItem('stt_realtime', '1');
    expect(isRealtimeSttEnabled()).toBe(true);
  });

  it('capability flag takes precedence over localStorage', () => {
    $id('stt-model').value = 'gpt-realtime-whisper';
    localStorage.setItem('stt_realtime', '0');
    expect(isRealtimeSttEnabled()).toBe(true);
  });

  it('returns false when stt-model element is missing entirely and localStorage is unset', () => {
    document.body.innerHTML = '';
    expect(isRealtimeSttEnabled()).toBe(false);
  });

  it('handles modelSpec being undefined (e.g. before bundle loaded)', () => {
    delete window.modelSpec;
    $id('stt-model').value = 'gpt-realtime-whisper';
    expect(isRealtimeSttEnabled()).toBe(false);
  });
});
