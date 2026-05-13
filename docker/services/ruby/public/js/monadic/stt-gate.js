/**
 * STT capability gate for Monadic Chat.
 *
 * Extracted from recording.js so the same function is reachable from
 * both the bundle (via window.SttGate) and Jest (via require). Before
 * this split, recording.js could not be required directly under jsdom
 * because it attaches DOM listeners at top level, so the test file
 * duplicated the function body and the two had to be hand-kept in
 * sync. The standalone module removes that drift risk.
 *
 * Decision policy (single source of truth):
 *   1. If the selected STT model declares
 *      `supports_realtime_streaming: true` in model_spec.js, streaming
 *      is on.
 *   2. Otherwise the `localStorage.stt_realtime` debug back door (`'1'`
 *      to force on) decides. This exists for development against
 *      future streaming models before their spec entry lands.
 *   3. If both checks fail or the surrounding env is incomplete
 *      (no #stt-model element, no window.modelSpec, localStorage
 *      access throws), the gate returns false — batch STT is always
 *      a safe fallback.
 */
(function() {
'use strict';

function isRealtimeSttEnabled() {
  const sttModelEl = (typeof $id === 'function') ? $id('stt-model') : document.getElementById('stt-model');
  const model = sttModelEl ? sttModelEl.value : '';
  if (model && typeof window !== 'undefined' && window.modelSpec
      && window.modelSpec[model]
      && window.modelSpec[model].supports_realtime_streaming) {
    return true;
  }
  try { return localStorage.getItem('stt_realtime') === '1'; }
  catch (_) { return false; }
}

const SttGate = { isRealtimeSttEnabled };

if (typeof window !== 'undefined') {
  window.SttGate = SttGate;
}
if (typeof module !== 'undefined' && module.exports) {
  module.exports = SttGate;
}
})();
