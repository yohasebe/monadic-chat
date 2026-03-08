/**
 * WebSocket Audio Handler for Monadic Chat
 *
 * Handles "audio" and "fragment_with_audio" WebSocket messages.
 * Manages audio data processing through MediaSource, Firefox fallback,
 * iOS basic mode, and PCM (Gemini) audio pipelines.
 *
 * Extracted from websocket.js to reduce the size of connect_websocket().
 */

const _MAX_AUDIO_QUEUE_SIZE = (typeof window !== 'undefined' && window.WsAudioConstants || {}).MAX_AUDIO_QUEUE_SIZE || 50;

/**
 * Create a processAudio callback that captures the audio pipeline state.
 * Used by both audio and fragment_with_audio handlers for wsHandlers delegation.
 * @returns {Function} processAudio callback
 * @private
 */
function _createProcessAudioCallback() {
  return function processAudio(audioData) {
    try {
      // Ensure MediaSource is initialized if not already
      if (!window.mediaSource && 'MediaSource' in window && !window.basicAudioMode) {
        if (typeof window.initializeMediaSourceForAudio === 'function') {
          window.initializeMediaSourceForAudio();
        }
      }

      // Handle based on browser environment
      if (window.firefoxAudioMode) {
        if (!window.firefoxAudioQueue) {
          window.firefoxAudioQueue = [];
        }
        if (window.firefoxAudioQueue.length >= _MAX_AUDIO_QUEUE_SIZE) {
          window.firefoxAudioQueue = window.firefoxAudioQueue.slice(Math.floor(_MAX_AUDIO_QUEUE_SIZE / 2));
        }
        window.firefoxAudioQueue.push(audioData);
        if (typeof window.processAudioDataQueue === 'function') {
          window.processAudioDataQueue();
        }
      } else if (window.basicAudioMode) {
        // For iOS and other devices without MediaSource
        if (typeof window.playAudioDirectly === 'function') {
          window.playAudioDirectly(audioData);
        }
      } else {
        // Standard approach for modern browsers
        if (window.audioDataQueue) {
          window.audioDataQueue.push(audioData);
        }
        if (typeof window.processAudioDataQueue === 'function') {
          window.processAudioDataQueue();
        }

        // Ensure audio playback starts automatically
        // Skip if segment-based queue is active to prevent duplicate audio
        const audio = window.audio;
        if (audio && !(window.getIsProcessingAudioQueue && window.getIsProcessingAudioQueue()) && window.globalAudioQueue.length === 0 && !(window.WsAudioQueue && window.WsAudioQueue.getCurrentSegmentAudio())) {
          audio.play().catch(err => {
            if (err.name === 'NotAllowedError') {
              const clickAudioText = typeof getTranslation === 'function' ?
                getTranslation('ui.messages.clickToEnableAudioSimple', 'Click to enable audio') :
                'Click to enable audio';
              setAlert(`<i class="fas fa-volume-up"></i> ${clickAudioText}`, 'info');
            }
          });
        }
      }
    } catch (e) {
      console.error("Error in audio processing:", e);
    }
  };
}

/**
 * Handle "fragment_with_audio" WebSocket message.
 * Delegates to wsHandlers.handleFragmentWithAudio with a processAudio callback.
 * @param {Object} data - Message data with fragment and audio content
 */
function handleFragmentWithAudio(data) {
  let handled = false;

  const wsHandlers = window.wsHandlers;
  if (wsHandlers && typeof wsHandlers.handleFragmentWithAudio === 'function') {
    const processAudio = _createProcessAudioCallback();
    handled = wsHandlers.handleFragmentWithAudio(data, processAudio);
  }

  if (!handled) {
    console.warn("Combined fragment_with_audio message was not handled properly");
  }
}

/**
 * Handle "audio" WebSocket message.
 * Delegates to wsHandlers.handleAudioMessage, with fallback inline processing
 * for error detection, PCM audio (Gemini), and device-specific playback.
 * @param {Object} data - Message data with audio content (base64 encoded)
 */
function handleAudio(data) {
  // Use the handler if available
  let handled = false;
  const wsHandlers = window.wsHandlers;
  if (wsHandlers && typeof wsHandlers.handleAudioMessage === 'function') {
    const processAudio = _createProcessAudioCallback();
    handled = wsHandlers.handleAudioMessage(data, processAudio);
  }

  if (!handled) {
    // Fallback to inline handling
    // For Auto TTS, keep spinner visible until audio actually starts playing
    // For manual TTS (Play button), hide immediately as before
    if (!window.autoSpeechActive && !window.autoPlayAudio) {
      $("#monadic-spinner").hide();
    }

    // Check for duplicate audio - use same ID generation as handler
    const fallbackAudioId = data.sequence_id || data.t_index ||
                            (data.content ? String(data.content).substring(0, 50) : Date.now().toString());

    // Skip if this audio was already processed by the handler
    if (window.wsHandlers && typeof window.wsHandlers.isAudioProcessed === 'function') {
      if (window.wsHandlers.isAudioProcessed(fallbackAudioId)) {
        console.debug('[Fallback Audio] Skipping duplicate audio:', fallbackAudioId);
        return; // Skip this audio - already processed by handler
      }
      // Mark as processed to prevent future duplicates
      if (typeof window.wsHandlers.markAudioProcessed === 'function') {
        window.wsHandlers.markAudioProcessed(fallbackAudioId);
      }
    }

    try {
      // Check if response contains an error
      if (data.content) {
        // Handle error that might be an object
        if (typeof data.content === 'object' && (data.content.error || data.content.type === 'error')) {
          console.error("API error:", data.content.error || data.content.message || data.content);
          // Convert to error message format
          data.type = 'error';
          data.content = data.content.message || data.content.error || JSON.stringify(data.content);
          if (window.wsHandlers && typeof window.wsHandlers.handleErrorMessage === 'function') {
            window.wsHandlers.handleErrorMessage(data);
          }
          return;
        }
        // Handle error in string format
        else if (typeof data.content === 'string' && data.content.includes('error')) {
          try {
            const errorData = JSON.parse(data.content);
            if (errorData.error || errorData.type === 'error') {
              console.error("API error:", errorData.error || errorData.message);
              data.type = 'error';
              data.content = errorData.message || errorData.error || JSON.stringify(errorData);
              if (window.wsHandlers && typeof window.wsHandlers.handleErrorMessage === 'function') {
                window.wsHandlers.handleErrorMessage(data);
              }
              return;
            }
          } catch (e) {
            // If not valid JSON, continue with regular processing
          }
        }
      }

      // Check if this is PCM audio from Gemini
      const provider = typeof $ !== 'undefined' ? $("#tts-provider").val() : '';
      const isPCMFromGemini = (provider === "gemini-flash" || provider === "gemini-pro") && data.mime_type && data.mime_type.includes("audio/L16");

      if (isPCMFromGemini) {
        // Handle PCM audio from Gemini
        const audioData = Uint8Array.from(atob(data.content), c => c.charCodeAt(0));
        const mimeMatch = data.mime_type.match(/rate=(\d+)/);
        const sampleRate = mimeMatch ? parseInt(mimeMatch[1]) : 24000;

        // Convert PCM to playable audio using Web Audio API
        if (window.WsAudioPlayback && typeof window.WsAudioPlayback.playPCMAudio === 'function') {
          window.WsAudioPlayback.playPCMAudio(audioData, sampleRate);
        }
        return;
      }

      const audioData = Uint8Array.from(atob(data.content), c => c.charCodeAt(0));

      // Device/browser specific audio processing
      if (window.firefoxAudioMode) {
        if (!window.firefoxAudioQueue) {
          window.firefoxAudioQueue = [];
        }
        if (window.firefoxAudioQueue.length >= _MAX_AUDIO_QUEUE_SIZE) {
          window.firefoxAudioQueue = window.firefoxAudioQueue.slice(Math.floor(_MAX_AUDIO_QUEUE_SIZE / 2));
        }
        window.firefoxAudioQueue.push(audioData);
        if (typeof window.processAudioDataQueue === 'function') {
          window.processAudioDataQueue();
        }
      } else if (window.basicAudioMode) {
        if (typeof window.playAudioDirectly === 'function') {
          window.playAudioDirectly(audioData);
        }
      } else {
        // Standard MediaSource approach
        if (window.audioDataQueue) {
          window.audioDataQueue.push(audioData);
        }
        if (typeof window.processAudioDataQueue === 'function') {
          window.processAudioDataQueue();
        }

        // Make sure audio is playing with error handling
        const audio = window.audio;
        if (audio && !(window.getIsProcessingAudioQueue && window.getIsProcessingAudioQueue()) && window.globalAudioQueue.length === 0 && !(window.WsAudioQueue && window.WsAudioQueue.getCurrentSegmentAudio())) {
          const playPromise = audio.play();
          if (playPromise !== undefined) {
            playPromise.catch(err => {
              if (err.name === 'NotAllowedError') {
                const clickAudioText = typeof getTranslation === 'function' ?
                  getTranslation('ui.messages.clickToEnableAudioSimple', 'Click to enable audio') :
                  'Click to enable audio';
                setAlert(`<i class="fas fa-volume-up"></i> ${clickAudioText}`, 'info');
              }
            });
          }
        }
      }

    } catch (e) {
      console.error("Error processing audio data:", e);
    }
  }
}

// Export for browser environment
window.WsAudioHandler = {
  handleAudio,
  handleFragmentWithAudio
};

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = window.WsAudioHandler;
}
