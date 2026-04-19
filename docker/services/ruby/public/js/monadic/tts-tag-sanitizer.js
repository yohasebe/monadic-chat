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

  // ElevenLabs v3 audio tags. The prompt restricts the LLM to the curated
  // single-word set, but the regex accepts multi-word lowercase descriptors
  // up to ~30 chars so the UI still cleans up when the model improvises.
  var ELEVENLABS_INLINE_MARKERS = [
    "laughs", "sighs", "whispers", "excited", "sarcastic", "curious",
    "crying", "angry", "sad", "happy", "giggles", "sobs", "sings",
    "exhales", "inhales"
  ];
  // NOTE: the "g" flag alone (no "i") keeps the catch-all lowercase-only so
  // that transcripts preserve all-caps brackets like [TODO] and numeric
  // brackets like [1] that are not TTS markers.
  var ELEVENLABS_INLINE_RE = new RegExp(
    "\\[(?:" + ELEVENLABS_INLINE_MARKERS.join("|") + "|[a-z][a-z ]{2,30})\\]",
    "g"
  );

  // Gemini TTS 16 fixed tags plus a loose free-form catch-all.
  var GEMINI_INLINE_MARKERS = [
    "amazed", "crying", "curious", "excited", "sighs", "gasp", "giggles",
    "laughs", "mischievously", "panicked", "sarcastic", "serious",
    "shouting", "tired", "trembling", "whispers"
  ];
  var GEMINI_INLINE_RE = new RegExp(
    "\\[(?:" + GEMINI_INLINE_MARKERS.join("|") + "|[a-z][a-z ,]{2,60})\\]",
    "g"
  );

  // Normalize a provider string to a canonical family key.
  // NOTE: ONLY ElevenLabs v3 interprets inline audio tags — Flash v2.5 and
  // Multilingual v2 read bracket content as literal text. The v3 variant
  // therefore gets its own family key so Expressive Speech does not activate
  // for the legacy ElevenLabs models.
  function familyFor(provider) {
    var key = String(provider == null ? "" : provider).toLowerCase();
    if (key === "grok" || key.indexOf("xai") === 0)                    return "xai";
    if (key === "elevenlabs-v3" || key === "eleven_v3")                return "elevenlabs-v3";
    if (key.indexOf("elevenlabs") === 0 || key.indexOf("eleven_") === 0) return "elevenlabs";
    if (key.indexOf("gemini") === 0)                                   return "gemini";
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
    },
    "elevenlabs-v3": function(text) {
      return String(text)
        .replace(ELEVENLABS_INLINE_RE, "")
        .replace(/[ \t]{2,}/g, " ")
        .replace(/\s+([,.!?;:])/g, "$1");
    },
    "gemini": function(text) {
      return String(text)
        .replace(GEMINI_INLINE_RE, "")
        .replace(/[ \t]{2,}/g, " ")
        .replace(/\s+([,.!?;:])/g, "$1");
    }
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
