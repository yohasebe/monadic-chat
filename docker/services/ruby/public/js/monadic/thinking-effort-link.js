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

// True when the model's declared enumeration includes "none" and the current
// effort IS "none" — i.e. the model will produce no reasoning, so a checked
// Show Thinking toggle would be a silent contradiction.
function effortSuppressesThinking(spec, currentEffort) {
  if (!spec || !Array.isArray(spec.reasoning_effort)) return false;
  const options = spec.reasoning_effort[0];
  if (!Array.isArray(options) || !options.includes('none')) return false;
  return currentEffort === 'none';
}

function getEl(id) {
  return (typeof $id === 'function') ? $id(id) : document.getElementById(id);
}

// One-shot coherence sync, called from the model-selection handler (which
// also runs on initial load): when the effective effort is "none", the
// Show Thinking toggle is turned OFF so the UI never claims it will show
// thinking that the model is configured not to produce. The model's default
// effort is never touched here — display follows reality, not vice versa.
function syncShowThinkingToEffort() {
  const toggle = getEl('show-thinking');
  const modelEl = getEl('model');
  const effortEl = getEl('reasoning-effort');
  if (!toggle || !modelEl || !effortEl) return;
  const spec = (typeof window !== 'undefined' && window.modelSpec) ? window.modelSpec[modelEl.value] : null;
  if (effortSuppressesThinking(spec, effortEl.value) && toggle.checked) {
    toggle.checked = false;
  }
}

// Wire both directions of the link. Idempotent: safe to call more than once.
//  - Show Thinking turned ON while effort is "none"  → bump effort to the
//    model's lowest thinking level (user intent: see the reasoning).
//  - Effort set to "none" while Show Thinking is ON  → turn the toggle OFF
//    (user intent: no reasoning, so nothing will be shown).
// Turning Show Thinking OFF never touches the effort: reasoning affects
// answer quality, not just display.
function wireShowThinkingEffortLink() {
  const toggle = getEl('show-thinking');
  if (toggle && !toggle._mcEffortLinkWired) {
    toggle._mcEffortLinkWired = true;
    toggle.addEventListener('change', function () {
      if (!toggle.checked) return; // OFF never touches the effort
      const modelEl = getEl('model');
      const effortEl = getEl('reasoning-effort');
      if (!modelEl || !effortEl) return;
      const spec = (typeof window !== 'undefined' && window.modelSpec) ? window.modelSpec[modelEl.value] : null;
      const bump = effortBumpForThinking(spec, effortEl.value);
      if (!bump) return;
      effortEl.value = bump;
      // Propagate like a user selection so params / the model-selected label update.
      effortEl.dispatchEvent(new Event('change', { bubbles: true }));
    });
  }

  const effortEl = getEl('reasoning-effort');
  if (effortEl && !effortEl._mcEffortLinkWired) {
    effortEl._mcEffortLinkWired = true;
    effortEl.addEventListener('change', function () {
      // No loop with the bump above: the bump only ever sets a non-"none"
      // value, and this branch only acts on "none".
      if (effortEl.value !== 'none') return;
      const toggle2 = getEl('show-thinking');
      const modelEl = getEl('model');
      if (!toggle2 || !modelEl || !toggle2.checked) return;
      const spec = (typeof window !== 'undefined' && window.modelSpec) ? window.modelSpec[modelEl.value] : null;
      if (effortSuppressesThinking(spec, 'none')) {
        toggle2.checked = false;
      }
    });
  }
}

const ThinkingEffortLink = {
  effortBumpForThinking,
  effortSuppressesThinking,
  syncShowThinkingToEffort,
  wireShowThinkingEffortLink
};

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
