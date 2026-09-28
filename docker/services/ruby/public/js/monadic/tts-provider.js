// Shared classification of TTS selector values (not model IDs).
(function (root) {
  "use strict";
  const geminiLabels = new Set(["gemini", "gemini-flash", "gemini-flash-lite", "gemini-pro"]);
  function isGemini(provider) {
    return geminiLabels.has(provider);
  }
  root.TtsProvider = { isGemini };
  if (typeof module !== "undefined" && module.exports) module.exports = root.TtsProvider;
})(window);
