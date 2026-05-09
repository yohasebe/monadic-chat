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
  // Malformed BBCode-style hybrids the LLM sometimes emits: [/word] closing-
  // style square brackets, and [wrap-tag] where the word belongs in <>.
  var XAI_MALFORMED_CLOSING_RE = /\[\/[a-z-]+\]/gi;
  var XAI_MALFORMED_SQUARE_WRAP_RE = new RegExp(
    "\\[(?:" + XAI_WRAP_TAGS.join("|") + ")\\]", "gi"
  );

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
  // Strict variant — fixed markers only, no free-form catch-all. Used for
  // cross-family union cleanup where false-positives on user-typed
  // lowercase brackets would be unacceptable.
  var ELEVENLABS_INLINE_STRICT_RE = new RegExp(
    "\\[(?:" + ELEVENLABS_INLINE_MARKERS.join("|") + ")\\]",
    "gi"
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
  var GEMINI_INLINE_STRICT_RE = new RegExp(
    "\\[(?:" + GEMINI_INLINE_MARKERS.join("|") + ")\\]",
    "gi"
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
    // gpt-4o-mini-tts (dropdown value "openai-tts-4o") is the only OpenAI TTS
    // model with the out-of-band `instructions` parameter. Other variants
    // (tts-1, tts-1-hd) must stay in the generic `openai` family.
    if (key === "openai-tts-4o")                                       return "openai-instruction";
    if (key.indexOf("openai") === 0 || key.indexOf("tts-") === 0)      return "openai";
    return key;
  }

  // Expressive Speech instruction-mode sentinel: `<<TTS:...>>` at the start
  // of the text (optional leading whitespace + optional trailing newline).
  // Non-greedy body so the first `>>` closes the block. Mirror of the Ruby
  // INSTRUCTION_SENTINEL_DISPLAY_RE.
  //
  // JS regex has no `m` flag equivalent to Ruby's `.` matching newlines, so
  // we use `[\s\S]` instead of `.` to traverse multi-line directive blocks.
  var INSTRUCTION_SENTINEL_DISPLAY_RE = /^\s*<<TTS:[\s\S]*?>>\n?/;

  var DISPLAY_SANITIZE = {
    "xai": function(text) {
      return String(text)
        .replace(XAI_WRAP_RE, "")
        .replace(XAI_INLINE_RE, "")
        .replace(XAI_MALFORMED_CLOSING_RE, "")
        .replace(XAI_MALFORMED_SQUARE_WRAP_RE, "")
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
      // Gemini supports BOTH inline tags AND a leading `<<TTS:...>>`
      // directive block (hybrid mode — see
      // docs_dev/expressive_speech.md §Layer 5). Strip both shapes here
      // so the reply card displays only the spoken content. The trim at
      // the end removes whitespace left by tags sitting right after the
      // directive newline or at the end of the reply.
      return String(text)
        .replace(INSTRUCTION_SENTINEL_DISPLAY_RE, "")
        .replace(GEMINI_INLINE_RE, "")
        .replace(/[ \t]{2,}/g, " ")
        .replace(/\s+([,.!?;:])/g, "$1")
        .replace(/^\s+|\s+$/g, "");
    },
    // Expressive Speech instruction mode (OpenAI gpt-4o-mini-tts):
    // strip the leading `<<TTS:...>>` directive from display.
    "openai-instruction": function(text) {
      return String(text).replace(INSTRUCTION_SENTINEL_DISPLAY_RE, "");
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
    var activeProvider = provider != null ? provider : currentProvider();
    if (!tagAware(activeProvider)) return text;

    var fam = familyFor(activeProvider);
    // Own family: full sanitizer (includes free-form catch-all for
    // ElevenLabs/Gemini).
    var result = DISPLAY_SANITIZE[fam](String(text));
    // Cross-family cleanup: strip OTHER families' markers that may remain
    // from previous turns, but use STRICT regexes (no catch-all) so that
    // user-typed lowercase brackets like [done] or [foo bar] are not
    // false-positive stripped when the active engine would leave them.
    if (fam !== "xai") {
      result = result.replace(XAI_WRAP_RE, "")
                     .replace(XAI_INLINE_RE, "")
                     .replace(XAI_MALFORMED_CLOSING_RE, "")
                     .replace(XAI_MALFORMED_SQUARE_WRAP_RE, "");
    }
    if (fam !== "elevenlabs-v3") {
      result = result.replace(ELEVENLABS_INLINE_STRICT_RE, "");
    }
    if (fam !== "gemini") {
      result = result.replace(GEMINI_INLINE_STRICT_RE, "");
    }
    // Cross-family cleanup for the instruction-mode sentinel: strip any
    // residual `<<TTS:...>>` left over from a previous openai-tts-4o or
    // gemini session so it does not surface in the transcript.
    // openai-instruction and gemini handle the strip in their own
    // sanitizer; every other family needs the cross-family sweep.
    if (fam !== "openai-instruction" && fam !== "gemini") {
      result = result.replace(INSTRUCTION_SENTINEL_DISPLAY_RE, "");
    }
    return result.replace(/[ \t]{2,}/g, " ").replace(/\s+([,.!?;:])/g, "$1");
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
