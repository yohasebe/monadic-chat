/**
 * WebSocket TTS Handler for Monadic Chat
 *
 * Handles text-to-speech related WebSocket messages that are
 * independent of streaming audio state:
 * - web_speech: Browser Web Speech API synthesis
 * - tts_progress: Processing spinner update
 * - tts_complete: Generation completion with spinner management
 * - tts_notice: Partial output or length warnings
 *
 * Note: The "audio" case is handled by ws-audio-handler.js.
 *
 * Extracted from websocket.js to reduce the size of connect_websocket().
 */
(function() {
'use strict';

/**
 * Handle "web_speech" WebSocket message.
 * Uses the browser's Web Speech API to synthesize speech from text.
 * @param {Object} data - Message data with content string
 */
function handleWebSpeech(data) {
  window.lastTTSMode = 'web_speech';
  var spinnerEl = $id("monadic-spinner");
  $hide(spinnerEl);

  if (window.speechSynthesis && typeof window.ttsSpeak === 'function') {
    try {
      const text = data.content || '';
      const utterance = new SpeechSynthesisUtterance(text);

      // Get voice settings from UI
      const voiceElement = $id('webspeech-voice');
      if (voiceElement && voiceElement.value) {
        const selectedVoice = window.speechSynthesis.getVoices().find(v =>
          v.name === voiceElement.value);
        if (selectedVoice) {
          utterance.voice = selectedVoice;
        }
      }

      // Get speed setting
      const speedElement = $id('tts-speed');
      if (speedElement && speedElement.value) {
        utterance.rate = parseFloat(speedElement.value) || 1.0;
      }

      // Set event handlers for proper button state management
      utterance.onend = function() {
        if (typeof removeStopButtonHighlight === 'function') {
          removeStopButtonHighlight();
        }
      };

      utterance.onerror = function(event) {
        console.error('Web Speech API error:', event);
        if (typeof removeStopButtonHighlight === 'function') {
          removeStopButtonHighlight();
        }
      };

      window.speechSynthesis.speak(utterance);
    } catch (e) {
      console.error("Error using Web Speech API:", e);
      setAlert("Web Speech API error: " + e.message, "warning");
      if (typeof removeStopButtonHighlight === 'function') {
        removeStopButtonHighlight();
      }
    }
  } else {
    console.error("Web Speech API not available");
    const notAvailableText = typeof webUIi18n !== 'undefined' ?
      webUIi18n.t('ui.messages.webSpeechNotAvailable') : 'Web Speech API not available in this browser';
    setAlert(notAvailableText, "warning");
    if (typeof removeStopButtonHighlight === 'function') {
      removeStopButtonHighlight();
    }
  }
}

/**
 * Handle "tts_progress" WebSocket message.
 * Updates the spinner to show audio processing state.
 * @param {Object} _data - Message data (unused)
 */
function handleTTSProgress(_data) {
  var spinnerEl = $id("monadic-spinner");
  if (spinnerEl) {
    var span = spinnerEl.querySelector("span");
    if (span) span.innerHTML = '<i class="fas fa-headphones fa-pulse"></i> Processing audio';
  }
}

/**
 * Handle "tts_complete" WebSocket message.
 * Hides spinner for manual TTS; auto TTS keeps spinner until playback.
 * @param {Object} _data - Message data (unused)
 */
function handleTTSComplete(_data) {
  var spinnerEl = $id("monadic-spinner");
  if (!window.autoSpeechActive && !window.autoPlayAudio) {
    // Manual TTS: hide spinner immediately
    if (spinnerEl) {
      $hide(spinnerEl);
      // Reset spinner to default state for other operations
      var spanIcon = spinnerEl.querySelector("span i");
      if (spanIcon) {
        spanIcon.classList.remove("fa-headphones");
        spanIcon.classList.add("fa-comment");
      }
      var span = spinnerEl.querySelector("span");
      if (span) span.innerHTML = '<i class="fas fa-comment fa-pulse"></i> Starting';
    }
  }
  // For Auto TTS: spinner will be hidden when audio playback actually starts
}

/**
 * Handle "tts_notice" WebSocket message.
 * Shows partial output or text length warning notice.
 * @param {Object} data - Message data with content string
 */
function handleTTSNotice(data) {
  const noticeContent = data.content;
  if (noticeContent) {
    showTtsNotice(noticeContent);
  }
}

/**
 * Handle "tts_stopped" WebSocket message.
 * Resets UI state when TTS playback is stopped.
 * @param {Object} _data - Message data (unused)
 */
function handleTTSStopped(_data) {
  var spinnerEl = $id("monadic-spinner");
  $hide(spinnerEl);

  // Reset response state
  window.responseStarted = false;

  // Set alert to ready state - only if system is not busy
  if (!isSystemBusy()) {
    const readyToStartText = typeof webUIi18n !== 'undefined' ?
      webUIi18n.t('ui.messages.readyToStart') : 'Ready to start';
    setAlert(`<i class='fa-solid fa-circle-check'></i> ${readyToStartText}`, "success");
  }
}

// Export for browser environment
window.WsTTSHandler = {
  handleWebSpeech,
  handleTTSProgress,
  handleTTSComplete,
  handleTTSNotice,
  handleTTSStopped
};

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = window.WsTTSHandler;
}
})();
