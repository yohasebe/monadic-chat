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
 * Realtime STT is an OpenAI-only WebSocket transcription path. Its
 * endpoint rejects any non-OpenAI model value (e.g. ElevenLabs
 * "scribe_v2" → 400 "Invalid value"). Non-OpenAI STT models are
 * identified by the same provider-routing prefixes the batch router
 * uses (stt_utils.rb: gemini-/scribe/cohere-transcribe/voxtral/xai-stt)
 * and must ALWAYS use the batch path — never realtime, not even via the
 * debug back door. Batch STT routes by provider, so every TTS/STT
 * combination works as long as the provider's API key is present.
 *
 * Decision policy (single source of truth):
 *   0. If the selected STT model is not an OpenAI STT model, return
 *      false immediately — realtime is OpenAI-only.
 *   1. If the selected STT model declares
 *      `supports_realtime_streaming: true` in model_spec.js, streaming
 *      is on.
 *   2. Otherwise the `localStorage.stt_realtime` debug back door (`'1'`
 *      to force on) decides. This exists for development against
 *      future OpenAI streaming models before their spec entry lands.
 *   3. If checks fail or the surrounding env is incomplete
 *      (no #stt-model element, no window.modelSpec, localStorage
 *      access throws), the gate returns false — batch STT is always
 *      a safe fallback.
 */
(function() {
'use strict';

// Provider-routing prefixes for NON-OpenAI STT models. Mirrors the
// batch router in stt_utils.rb. A model matching any of these is served
// by its own provider's batch endpoint and can never use the
// OpenAI-only realtime WebSocket path.
const NON_OPENAI_STT_PREFIXES = ['gemini-', 'scribe', 'cohere-transcribe', 'voxtral', 'xai-stt'];

function isOpenAiSttModel(model) {
  if (!model) return false;
  return !NON_OPENAI_STT_PREFIXES.some(function(prefix) { return model.indexOf(prefix) === 0; });
}

function isRealtimeSttEnabled() {
  const sttModelEl = (typeof $id === 'function') ? $id('stt-model') : document.getElementById('stt-model');
  const model = sttModelEl ? sttModelEl.value : '';
  // Realtime is an OpenAI-only path. Non-OpenAI STT models (ElevenLabs
  // Scribe, Gemini, Cohere, Mistral Voxtral, xAI) must fall back to the
  // batch path regardless of the model-spec flag or the debug back door.
  if (!isOpenAiSttModel(model)) return false;
  if (typeof window !== 'undefined' && window.modelSpec
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
