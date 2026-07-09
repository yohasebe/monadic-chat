/**
 * Show Thinking ⇄ Reasoning Effort link.
 *
 * Some models (OpenAI gpt-5.x family, and any spec whose reasoning_effort
 * enumeration includes "none") produce NO reasoning at all while the effort
 * is "none". Turning the "Show Thinking" toggle ON in that state is a silent
 * contradiction: the user asked to see the model's thinking, but the model
 * is configured not to think, so the panel never appears and nothing
 * explains why.
 *
 * This module resolves the contradiction in the direction the user
 * expressed intent: switching Show Thinking ON while effort is "none" bumps
 * the effort to the model's lowest thinking level (the first non-"none"
 * entry of the spec's own enumeration, so the order stays SSOT-driven).
 * Switching Show Thinking OFF never touches the effort — reasoning affects
 * answer quality, not just display, so hiding the panel must not silently
 * degrade the model.
 *
 * Standalone module (same pattern as stt-gate.js) so the decision logic is
 * unit-testable via require() without dragging in monadic.js.
 */
(function () {
'use strict';

// Decide the effort value to switch to when Show Thinking turns ON.
// Returns the replacement effort string, or null when no change is needed
// (model doesn't declare reasoning_effort, its enumeration has no "none",
// or the current value is already a thinking level).
function effortBumpForThinking(spec, currentEffort) {
  if (!spec || !Array.isArray(spec.reasoning_effort)) return null;
  const options = spec.reasoning_effort[0];
  if (!Array.isArray(options) || !options.includes('none')) return null;
  if (currentEffort !== 'none') return null;
  const firstThinking = options.find(function (o) { return o !== 'none'; });
  return firstThinking || null;
}

// Wire the change listener. Idempotent: safe to call more than once.
function wireShowThinkingEffortLink() {
  const toggle = (typeof $id === 'function') ? $id('show-thinking') : document.getElementById('show-thinking');
  if (!toggle || toggle._mcEffortLinkWired) return;
  toggle._mcEffortLinkWired = true;
  toggle.addEventListener('change', function () {
    if (!toggle.checked) return; // OFF never touches the effort
    const modelEl = (typeof $id === 'function') ? $id('model') : document.getElementById('model');
    const effortEl = (typeof $id === 'function') ? $id('reasoning-effort') : document.getElementById('reasoning-effort');
    if (!modelEl || !effortEl) return;
    const spec = (typeof window !== 'undefined' && window.modelSpec) ? window.modelSpec[modelEl.value] : null;
    const bump = effortBumpForThinking(spec, effortEl.value);
    if (!bump) return;
    effortEl.value = bump;
    // Propagate like a user selection so params / the model-selected label update.
    effortEl.dispatchEvent(new Event('change', { bubbles: true }));
  });
}

const ThinkingEffortLink = { effortBumpForThinking, wireShowThinkingEffortLink };

if (typeof window !== 'undefined') {
  window.ThinkingEffortLink = ThinkingEffortLink;
  if (typeof document !== 'undefined') {
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', wireShowThinkingEffortLink);
    } else {
      wireShowThinkingEffortLink();
    }
  }
}
if (typeof module !== 'undefined' && module.exports) {
  module.exports = ThinkingEffortLink;
}
})();
