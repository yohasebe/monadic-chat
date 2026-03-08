/**
 * WebSocket Streaming Handler for Monadic Chat
 *
 * Handles streaming lifecycle messages:
 * - streaming_complete: Reset streaming state, hide spinner, show ready status
 *
 * Extracted from websocket.js to reduce the size of connect_websocket().
 */

const BUSY_CHECK_INTERVAL_MS = (typeof window !== 'undefined' && window.WsAudioConstants || {}).BUSY_CHECK_INTERVAL_MS || 500;
const BUSY_CHECK_MAX_WAIT_MS = (typeof window !== 'undefined' && window.WsAudioConstants || {}).BUSY_CHECK_MAX_WAIT_MS || 10000;

/**
 * Handle "streaming_complete" WebSocket message.
 * Resets streaming state, manages spinner visibility based on Auto Speech,
 * and shows "Ready for input" status with busy-check retry logic.
 * @param {Object} _data - Message data (unused)
 */
function handleStreamingComplete(_data) {
  // Reset streaming state
  window.streamingResponse = false;
  if (window.UIState) {
    window.UIState.set('streamingResponse', false);
    window.UIState.set('isStreaming', false);
  }

  // Clear any pending spinner check interval
  if (window.spinnerCheckInterval) {
    clearInterval(window.spinnerCheckInterval);
    window.spinnerCheckInterval = null;
  }

  // Hide spinner unless we're calling functions or streaming
  if (!window.callingFunction && !window.streamingResponse) {
    // Mark text response as completed
    if (typeof window.setTextResponseCompleted === 'function') {
      window.setTextResponseCompleted(true);
    }

    // Check foreground state
    const inForeground = typeof window.isForegroundTab === 'function' ? window.isForegroundTab() : true;

    // Check Auto Speech from multiple sources
    const paramsEnabled = window.params && (window.params["auto_speech"] === true || window.params["auto_speech"] === "true");
    const checkboxEnabled = typeof $ !== 'undefined' && $("#check-auto-speech").is(":checked");
    const autoSpeechActive = window.autoSpeechActive === true;
    const autoSpeechEnabled = paramsEnabled || checkboxEnabled || autoSpeechActive;

    if (autoSpeechEnabled && !window.ttsPlaybackStarted && inForeground) {
      // Auto Speech enabled, TTS not started yet, and tab is foreground
      // Server will send audio directly
      if (window.debugWebSocket) console.log('[streaming_complete] Auto Speech enabled - server will send audio');
    } else {
      // Check if we can hide spinner
      if (typeof window.checkAndHideSpinner === 'function') {
        window.checkAndHideSpinner();
      } else {
        $("#monadic-spinner").hide();
      }
    }
  }

  // Check if system is busy before showing "Ready for input"
  setTimeout(function() {
    if (!isSystemBusy()) {
      const readyText = typeof webUIi18n !== 'undefined' ?
        webUIi18n.t('ui.messages.readyForInput') : 'Ready for input';
      setAlert(`<i class='fa-solid fa-circle-check'></i> ${readyText}`, "success");
    } else {
      // If system is still busy, wait and check again
      let checkInterval = setInterval(function() {
        if (!isSystemBusy()) {
          clearInterval(checkInterval);
          const readyText = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.readyForInput') : 'Ready for input';
          setAlert(`<i class='fa-solid fa-circle-check'></i> ${readyText}`, "success");
        }
      }, BUSY_CHECK_INTERVAL_MS);

      // Safety timeout to prevent infinite checking
      setTimeout(function() {
        clearInterval(checkInterval);
        const readyText = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.readyForInput') : 'Ready for input';
        setAlert(`<i class='fa-solid fa-circle-check'></i> ${readyText}`, "success");
      }, BUSY_CHECK_MAX_WAIT_MS);
    }

    // Always ensure UI elements are enabled
    $("#message").prop("disabled", false);
    $("#send, #clear, #image-file, #voice, #doc, #url, #pdf-import").prop("disabled", false);
    $("#select-role").prop("disabled", false);

    // Focus on the message input
    setInputFocus();

    // Reset sequence tracking for next message (realtime TTS)
    if (typeof window.resetSequenceTracking === 'function') {
      window.resetSequenceTracking();
    }
  }, 250);
}

// Export for browser environment
window.WsStreamingHandler = {
  handleStreamingComplete
};

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = window.WsStreamingHandler;
}
