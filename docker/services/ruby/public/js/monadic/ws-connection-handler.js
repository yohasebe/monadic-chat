/**
 * WebSocket Connection Handler for Monadic Chat
 *
 * Handles OpenAI API token verification and connection status:
 * - token_verified: Enable OpenAI TTS/STT features
 * - open_ai_api_error: Disable OpenAI features on API failure
 * - token_not_verified: Disable OpenAI features on invalid token
 *
 * Note: The "error" and "cancel" cases remain in websocket.js
 * because they depend on streaming state variables (responseStarted,
 * callingFunction, streamingResponse).
 *
 * Extracted from websocket.js to reduce the size of connect_websocket().
 */
(function() {
'use strict';

/**
 * Handle "token_verified" WebSocket message.
 * Enables OpenAI TTS/STT models and updates UI state.
 * @param {Object} data - Message data with token and ai_user_initial_prompt
 */
function handleTokenVerified(data) {
  // Use the handler if available, otherwise use inline code
  let handled = false;
  if (typeof wsHandlers !== 'undefined' && wsHandlers && typeof wsHandlers.handleTokenVerification === 'function') {
    handled = wsHandlers.handleTokenVerification(data);
  } else {
    // Fallback to inline handling
    $("#api-token").val(data["token"]);
    $("#ai-user-initial-prompt").val(data["ai_user_initial_prompt"]);
    handled = true;
  }

  if (handled) {
    window.verified = "full";

    // Enable OpenAI TTS options when token is verified
    $("#openai-tts-4o").prop("disabled", false);
    $("#openai-tts").prop("disabled", false);
    $("#openai-tts-hd").prop("disabled", false);

    // Enable OpenAI STT models when token is verified
    $("#openai-stt-4o-mini").prop("disabled", false);
    $("#openai-stt-4o").prop("disabled", false);
    $("#openai-stt-4o-diarize").prop("disabled", false);
    $("#openai-stt-whisper").prop("disabled", false);

    // Set default STT model if none selected or current selection is disabled
    const currentSTTModel = $("#stt-model").val();
    if (!currentSTTModel || $("#stt-model option:selected").prop("disabled")) {
      const defaultSTTModel = window.providerDefaults?.openai?.audio_transcription?.[0]
        || "gpt-4o-mini-transcribe-2025-12-15";
      $("#stt-model").val(defaultSTTModel).trigger("change");
    }

    // Set OpenAI TTS as default when it becomes available
    const currentProvider = $("#tts-provider").val();
    if (currentProvider === "webspeech") {
      $("#tts-provider").val("openai-tts-4o").trigger("change");
    }
    $("#start").prop("disabled", false);
    $("#send, #clear, #voice, #tts-provider, #elevenlabs-tts-voice, #tts-voice, #conversation-language, #ai-user-initial-prompt-toggle, #ai-user-toggle, #check-auto-speech, #check-easy-submit").prop("disabled", false);

    // Update the available AI User providers when token is verified
    if (typeof window.updateAvailableProviders === 'function') {
      window.updateAvailableProviders();
    }
  }
}

/**
 * Handle "open_ai_api_error" WebSocket message.
 * Disables OpenAI TTS/STT options on API connection failure.
 * @param {Object} _data - Message data (unused)
 */
function handleOpenAIAPIError(_data) {
  window.verified = "partial";

  $("#start").prop("disabled", false);
  $("#send, #clear").prop("disabled", false);

  $("#api-token").val("");

  // Disable OpenAI TTS options
  $("#openai-tts-4o").prop("disabled", true);
  $("#openai-tts").prop("disabled", true);
  $("#openai-tts-hd").prop("disabled", true);

  // Disable OpenAI STT models
  $("#openai-stt-4o").prop("disabled", true);
  $("#openai-stt-4o-diarize").prop("disabled", true);
  $("#openai-stt-4o-mini").prop("disabled", true);
  $("#openai-stt-whisper").prop("disabled", true);

  const cannotConnectText = getTranslation('ui.messages.cannotConnectToAPI', 'Cannot connect to OpenAI API');
  setAlert(`<i class='fa-solid fa-bolt'></i> ${cannotConnectText}`, "warning");
}

/**
 * Handle "token_not_verified" WebSocket message.
 * Disables OpenAI TTS/STT options for invalid token.
 * @param {Object} _data - Message data (unused)
 */
function handleTokenNotVerified(_data) {
  window.verified = "partial";

  $("#start").prop("disabled", false);
  $("#send, #clear").prop("disabled", false);

  $("#api-token").val("");

  // Disable OpenAI TTS options
  $("#openai-tts-4o").prop("disabled", true);
  $("#openai-tts").prop("disabled", true);
  $("#openai-tts-hd").prop("disabled", true);

  // Disable OpenAI STT models
  $("#openai-stt-4o").prop("disabled", true);
  $("#openai-stt-4o-diarize").prop("disabled", true);
  $("#openai-stt-4o-mini").prop("disabled", true);
  $("#openai-stt-whisper").prop("disabled", true);

  const tokenNotSetText = getTranslation('ui.messages.validTokenNotSet', 'Valid OpenAI token not set');
  setAlert(`<i class='fa-solid fa-bolt'></i> ${tokenNotSetText}`, "warning");
}

// Export for browser environment
window.WsConnectionHandler = {
  handleTokenVerified,
  handleOpenAIAPIError,
  handleTokenNotVerified
};

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = window.WsConnectionHandler;
}
})();
