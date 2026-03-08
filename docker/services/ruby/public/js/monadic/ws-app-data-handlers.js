/**
 * WebSocket App Data Handlers for Monadic Chat
 *
 * Handles app/parameter/voice configuration messages:
 * - elevenlabs_voices: Populate ElevenLabs TTS voice selector
 * - gemini_voices: Populate Gemini TTS voice selector
 *
 * Extracted from websocket.js to reduce the size of connect_websocket().
 */

/**
 * Handle ElevenLabs voices message.
 * Populates voice selector, enables/disables provider options,
 * and restores saved cookie preferences.
 * @param {Object} data - Message data with content array of {voice_id, name}
 */
function handleElevenLabsVoices(data) {
  const cookieValue = getCookie("elevenlabs-tts-voice");
  const voices = data["content"];

  if (voices.length > 0) {
    // Enable ElevenLabs TTS provider options
    $("#elevenlabs-flash-provider-option").prop("disabled", false);
    $("#elevenlabs-multilingual-provider-option").prop("disabled", false);
    $("#elevenlabs-v3-provider-option").prop("disabled", false);
    // Enable ElevenLabs STT options
    $("#elevenlabs-stt-scribe-v2").prop("disabled", false);
    $("#elevenlabs-stt-scribe").prop("disabled", false);
    $("#elevenlabs-stt-scribe-experimental").prop("disabled", false);
  } else {
    // Disable ElevenLabs TTS provider options
    $("#elevenlabs-flash-provider-option").prop("disabled", true);
    $("#elevenlabs-multilingual-provider-option").prop("disabled", true);
    $("#elevenlabs-v3-provider-option").prop("disabled", true);
    // Disable ElevenLabs STT options
    $("#elevenlabs-stt-scribe-v2").prop("disabled", true);
    $("#elevenlabs-stt-scribe").prop("disabled", true);
    $("#elevenlabs-stt-scribe-experimental").prop("disabled", true);
  }

  $("#elevenlabs-tts-voice").empty();
  voices.forEach((voice) => {
    if (cookieValue === voice.voice_id) {
      $("#elevenlabs-tts-voice").append(`<option value="${voice.voice_id}" selected>${voice.name}</option>`);
    } else {
      $("#elevenlabs-tts-voice").append(`<option value="${voice.voice_id}">${voice.name}</option>`);
    }
  });

  // Restore saved cookie value for voice
  const savedVoice = getCookie("elevenlabs-tts-voice");
  if (savedVoice && $(`#elevenlabs-tts-voice option[value="${savedVoice}"]`).length > 0) {
    $("#elevenlabs-tts-voice").val(savedVoice);
  }

  // Restore saved cookie value for provider if it was elevenlabs
  const savedProvider = getCookie("tts-provider");
  if (["elevenlabs", "elevenlabs-flash", "elevenlabs-multilingual", "elevenlabs-v3"].includes(savedProvider)) {
    $("#tts-provider").val(savedProvider).trigger("change");
  }
}

/**
 * Handle Gemini voices message.
 * Populates voice selector, enables/disables provider and STT options,
 * and restores saved cookie preferences.
 * @param {Object} data - Message data with content array of {voice_id, name}
 */
function handleGeminiVoices(data) {
  const cookieValue = getCookie("gemini-tts-voice");
  const voices = data["content"];

  if (voices.length > 0) {
    // Enable Gemini TTS provider options
    $("#gemini-flash-provider-option").prop("disabled", false);
    $("#gemini-pro-provider-option").prop("disabled", false);
    // Enable Gemini STT model
    $("#gemini-stt-flash").prop("disabled", false);

    // Populate the voice selector
    $("#gemini-tts-voice").empty();
    voices.forEach((voice) => {
      if (cookieValue === voice.voice_id) {
        $("#gemini-tts-voice").append(`<option value="${voice.voice_id}" selected>${voice.name}</option>`);
      } else {
        $("#gemini-tts-voice").append(`<option value="${voice.voice_id}">${voice.name}</option>`);
      }
    });

    // Restore saved cookie value for voice
    const savedVoice = getCookie("gemini-tts-voice");
    if (savedVoice && $(`#gemini-tts-voice option[value="${savedVoice}"]`).length > 0) {
      $("#gemini-tts-voice").val(savedVoice);
    }
  } else {
    // Disable Gemini TTS provider options
    $("#gemini-flash-provider-option").prop("disabled", true);
    $("#gemini-pro-provider-option").prop("disabled", true);
    // Disable Gemini STT model
    $("#gemini-stt-flash").prop("disabled", true);
  }

  // Restore saved cookie value for provider if it was gemini
  const savedProvider = getCookie("tts-provider");
  if (savedProvider === "gemini-flash" || savedProvider === "gemini-pro") {
    $("#tts-provider").val(savedProvider).trigger("change");
  }
}

/**
 * Update app and model selection after import/session restore.
 * Marks import flow, updates dropdowns, and handles model selection.
 * Extracted from connect_websocket() closure.
 * @param {Object} parameters - Parameters with app_name and model
 */
function updateAppAndModelSelection(parameters) {
  // Mark import flow to preserve app/model/group during proceedWithAppChange
  if (typeof window !== 'undefined') {
    window.isImporting = true;
    window.lastImportTime = Date.now();
  }
  // Only update if the values are not already set correctly
  if (parameters.app_name && $("#apps").val() !== parameters.app_name) {
    $("#apps").val(parameters.app_name).trigger('change');
    // Update overlay icon immediately to avoid blank state until proceedWithAppChange runs
    if (typeof updateAppSelectIcon === 'function') {
      setTimeout(() => updateAppSelectIcon(parameters.app_name), 0);
    }
  }
  // Wait for app change to complete before setting model
  setTimeout(() => {
    if (parameters.model && $("#model").val() !== parameters.model) {
      $("#model").val(parameters.model).trigger('change');
    }
    // End of import flow; allow normal app/model changes afterwards
    if (typeof window !== 'undefined') {
      setTimeout(() => { window.isImporting = false; }, 500);
    }
  }, 200);
}

// Export for browser environment
window.WsAppDataHandlers = {
  handleElevenLabsVoices,
  handleGeminiVoices,
  updateAppAndModelSelection
};

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = window.WsAppDataHandlers;
}
