/**
 * TTS Tag Sanitizer — frontend mirror of
 * `lib/monadic/utils/tts_text_processors.rb`.
 *
 * Some TTS engines (xAI Grok today, ElevenLabs v3 planned) consume inline
 * audio-control markers embedded in the LLM response (for example `[laugh]`
 * or `<whisper>...</whisper>`). The backend forwards the raw text to the
 * TTS engine unchanged — that is what lets those engines speak expressively.
 *
 * The UI, however, should not display those markers as literal strings in
 * the chat transcript. This module provides a provider-keyed display
 * sanitizer that is invoked from the Markdown rendering pipeline. Providers
 * without a registered sanitizer pass through identity (zero behavioural
 * change), which preserves the current behaviour for OpenAI / Gemini /
 * Mistral / Cohere / Web Speech.
 *
 * To add a new provider (e.g., ElevenLabs v3), register a function on the
 * DISPLAY_SANITIZE table with the canonical family key.
 */
(function(global) {
  "use strict";

  var XAI_INLINE_MARKERS = [
    "pause", "long-pause", "laugh", "sigh", "cry",
    "click", "smack", "inhale", "exhale"
  ];
  var XAI_WRAP_TAGS = [
    "loud", "soft", "high", "low", "fast", "slow", "whisper", "sing"
  ];

  var XAI_INLINE_RE = new RegExp("\\[(?:" + XAI_INLINE_MARKERS.join("|") + ")\\]", "gi");
  var XAI_WRAP_RE   = new RegExp("</?(?:" + XAI_WRAP_TAGS.join("|") + ")>", "gi");

  // Normalize a provider string to a canonical family key.
  function familyFor(provider) {
    var key = String(provider == null ? "" : provider).toLowerCase();
    if (key === "grok" || key.indexOf("xai") === 0)         return "xai";
    if (key.indexOf("elevenlabs") === 0)                    return "elevenlabs";
    if (key.indexOf("gemini") === 0)                        return "gemini";
    if (key.indexOf("mistral") === 0 || key.indexOf("voxtral") !== -1) return "mistral";
    if (key.indexOf("openai") === 0 || key.indexOf("tts-") === 0)      return "openai";
    return key;
  }

  var DISPLAY_SANITIZE = {
    "xai": function(text) {
      return String(text)
        .replace(XAI_WRAP_RE, "")
        .replace(XAI_INLINE_RE, "")
        .replace(/[ \t]{2,}/g, " ")
        .replace(/\s+([,.!?;:])/g, "$1");
    }
    // "elevenlabs": TODO — activate once any app uses Eleven v3 audio tags.
  };

  // Resolve the current TTS provider from global params (monadic.js exposes
  // params on window). Falls back to null when unknown.
  function currentProvider() {
    try {
      if (typeof global.params !== "undefined" && global.params && global.params.tts_provider) {
        return global.params.tts_provider;
      }
    } catch (e) { /* ignore */ }
    return null;
  }

  function sanitizeForDisplay(text, provider) {
    if (text == null || text === "") return text;
    var fam = familyFor(provider != null ? provider : currentProvider());
    var fn = DISPLAY_SANITIZE[fam];
    return fn ? fn(text) : text;
  }

  function tagAware(provider) {
    var fam = familyFor(provider != null ? provider : currentProvider());
    return Object.prototype.hasOwnProperty.call(DISPLAY_SANITIZE, fam);
  }

  global.TtsTagSanitizer = {
    familyFor: familyFor,
    sanitizeForDisplay: sanitizeForDisplay,
    tagAware: tagAware
  };

  if (typeof module !== "undefined" && module.exports) {
    module.exports = global.TtsTagSanitizer;
  }
})(typeof window !== "undefined" ? window : globalThis);
