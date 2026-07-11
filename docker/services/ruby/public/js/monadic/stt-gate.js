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

// ─── STT select empty state ───
//
// Every #stt-model option ships disabled and is enabled per verified
// API key by three different handlers (ws-connection-handler.js for
// OpenAI, ws-app-data-handlers.js for Gemini/ElevenLabs, monadic.js
// for Mistral/Cohere/xAI). When NO key is present the select used to
// display the first disabled OpenAI option as if it were usable. A
// hidden placeholder option (value="") now owns that state, and a
// MutationObserver keeps it in sync with option enablement so no
// enable/disable call site needs to know about it.

function updateSttEmptyState() {
  const sel = (typeof $id === 'function') ? $id('stt-model')
    : (typeof document !== 'undefined' ? document.getElementById('stt-model') : null);
  if (!sel) return;
  const enabled = Array.from(sel.options).filter(function(o) {
    return !o.disabled && o.value !== '';
  });
  if (enabled.length === 0) {
    // Nothing usable — show the placeholder instead of a random
    // disabled model name. Only when a placeholder option exists:
    // setting value='' with no matching option would leave the select
    // blank (selectedIndex -1), the very defect this code prevents.
    const placeholder = Array.from(sel.options).find(function(o) {
      return o.value === '';
    });
    if (placeholder) sel.value = '';
    return;
  }
  const selectedOption = sel.options[sel.selectedIndex];
  if (!sel.value || (selectedOption && selectedOption.disabled)) {
    // Same policy as the TTS provider select: move to a REAL enabled
    // option rather than leaving the placeholder or a disabled model
    // selected
    sel.value = enabled[0].value;
    if (typeof $dispatch === 'function') {
      $dispatch(sel, 'change');
    } else {
      sel.dispatchEvent(new Event('change', { bubbles: true }));
    }
  }
}

function initSttEmptyStateObserver() {
  const sel = (typeof $id === 'function') ? $id('stt-model')
    : (typeof document !== 'undefined' ? document.getElementById('stt-model') : null);
  if (!sel || typeof MutationObserver === 'undefined') return;
  updateSttEmptyState();
  const observer = new MutationObserver(function() { updateSttEmptyState(); });
  observer.observe(sel, { attributes: true, subtree: true, attributeFilter: ['disabled'] });
}

if (typeof document !== 'undefined') {
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initSttEmptyStateObserver);
  } else {
    initSttEmptyStateObserver();
  }
}

const SttGate = { isRealtimeSttEnabled, updateSttEmptyState, initSttEmptyStateObserver };

if (typeof window !== 'undefined') {
  window.SttGate = SttGate;
}
if (typeof module !== 'undefined' && module.exports) {
  module.exports = SttGate;
}
})();
