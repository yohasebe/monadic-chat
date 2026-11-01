// Shared classification of TTS selector values (not model IDs), resolved
// through ttsChoices in model_spec.js — the same table and alias rule as
// Monadic::Utils::TtsProvider in Ruby.
(function (root) {
  "use strict";
  const MAX_ALIAS_HOPS = 5;
  const geminiLabels = new Set(["gemini", "gemini-flash", "gemini-flash-lite", "gemini-pro"]);

  function table() {
    return (root && root.ttsChoices) || {};
  }

  // { requestedId, id, provider, model, execution } for a selector value,
  // following `alias` for values saved by earlier versions; null for an
  // empty, unknown or broken value.
  function choice(label) {
    const requested = (label == null ? "" : String(label)).trim();
    if (!requested) return null;
    const choices = table();
    let id = requested;
    for (let i = 0; i < MAX_ALIAS_HOPS; i += 1) {
      const entry = Object.prototype.hasOwnProperty.call(choices, id) ? choices[id] : null;
      if (!entry || typeof entry !== "object") return null;
      if (entry.alias) {
        id = String(entry.alias);
        continue;
      }
      if (!entry.provider) return null;
      return { requestedId: requested, id: id, provider: String(entry.provider),
        model: entry.model == null ? null : entry.model, execution: entry.execution || "server" };
    }
    return null;
  }

  function providerOf(label) {
    const c = choice(label);
    return c ? c.provider : null;
  }

  function modelFor(label) {
    const c = choice(label);
    return c ? c.model : null;
  }

  // From the table; the fixed set only where the table is not loaded.
  function isGemini(provider) {
    if (root && root.ttsChoices) return providerOf(provider) === "gemini";
    return geminiLabels.has(provider);
  }

  // The selector values (not aliases) that belong to a provider; the
  // fixed OpenAI set only where the table is not loaded.
  function idsOf(provider) {
    const choices = table();
    if (!root || !root.ttsChoices) return provider === "openai" ? ["openai-tts-4o", "openai-tts", "openai-tts-hd"] : [];
    return Object.keys(choices).filter(function (id) {
      const entry = choices[id];
      return entry && !entry.alias && entry.provider === provider;
    });
  }

  // Selects the option a saved value (possibly an alias) stands for, when
  // it belongs to `provider` (any provider when omitted) and the option is
  // present and enabled. Returns true when the selector was changed.
  function restoreSaved(selectEl, saved, provider) {
    const c = choice(saved);
    if (!selectEl || !c || (provider && c.provider !== provider)) return false;
    const option = Array.prototype.find.call(selectEl.options || [], function (o) { return o.value === c.id; });
    if (!option || option.disabled) return false;
    selectEl.value = c.id;
    if (!noteRetired(saved, selectEl) && pendingNotice === c.id) noteRetired(null, selectEl);
    if (typeof root.$dispatch === "function") root.$dispatch(selectEl, "change");
    return true;
  }

  // The successor a retired value moved to while its option was still
  // disabled (the page restores the saved choice before the provider's
  // voices arrive); told when restoreSaved selects it once available.
  let pendingNotice = null;

  // Tells the user once that a saved choice was retired and which option
  // the selector now holds; nothing for a value that is still offered.
  // While that option is disabled the notice waits (see pendingNotice).
  // With `saved` null, tells the waiting notice.
  function noteRetired(saved, selectEl) {
    const option = selectEl && selectEl.options ? selectEl.options[selectEl.selectedIndex] : null;
    if (saved != null) {
      const entry = table()[String(saved).trim()];
      if (!entry || !entry.retired) return false;
      if (!option || option.disabled) {
        pendingNotice = option ? option.value : null;
        return false;
      }
    } else if (!option || option.disabled || pendingNotice !== option.value) {
      return false;
    }
    pendingNotice = null;
    if (typeof root.setAlert !== "function") return false;
    const label = option.textContent;
    const fallback = "The text-to-speech option used before is no longer available. Switched to {to}.";
    const text = typeof root.getTranslation === "function"
      ? root.getTranslation("ui.messages.ttsChoiceRetired", fallback) : fallback;
    root.setAlert(text.replace("{to}", label), "info");
    return true;
  }

  root.TtsProvider = { isGemini, choice, providerOf, modelFor, idsOf, restoreSaved, noteRetired };
  if (typeof module !== "undefined" && module.exports) module.exports = root.TtsProvider;
})(window);
