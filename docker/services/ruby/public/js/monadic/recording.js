//////////////////////////////
// Detect silence
//////////////////////////////

function detectSilence(stream, onSilenceCallback, silenceDuration, silenceThreshold = 16) {
  const audioContext = new (window.AudioContext || window.webkitAudioContext)();

  let analyser;
  let streamNode;
  const bufferLength = 32;
  const dataArray = new Uint8Array(bufferLength);

  let silenceStart = performance.now();
  let triggered = false;
  let animationFrameId;

  // For cleanup
  let isActive = true;

  function setupAndStart() {
    analyser = audioContext.createAnalyser();
    streamNode = audioContext.createMediaStreamSource(stream);
    streamNode.connect(analyser);
    analyser.fftSize = 2048;

    // Reset silence timer after AudioContext is ready
    silenceStart = performance.now();
    checkSilence();
  }

  function checkSilence() {
    // Don't process if we've been cleaned up
    if (!isActive) return;

    analyser.getByteFrequencyData(dataArray);
    const totalAmplitude = dataArray.reduce((a, b) => a + b);
    const averageAmplitude = totalAmplitude / bufferLength;
    const isSilent = averageAmplitude < silenceThreshold;

    if (isSilent) {
      const now = performance.now();
      if (!triggered && now - silenceStart > silenceDuration) {
        onSilenceCallback();
        triggered = true;
      }
    } else {
      silenceStart = performance.now();
      triggered = false;
    }

    // Update the bar chart with the average amplitude value
    const chartCanvas = document.querySelector("#amplitude-chart");

    if (chartCanvas) {
      const chartContext = chartCanvas.getContext("2d");

      // Make sure canvas is properly sized for the container
      chartCanvas.width = Math.min(300, chartCanvas.clientWidth * 2); // Handle high DPI displays
      chartCanvas.height = 56; // Fixed height with doubled pixels for high DPI

      // Get dimensions after resize
      const chartWidth = chartCanvas.width;
      const chartHeight = chartCanvas.height;
      const barSpacing = 4;
      const barWidth = (chartWidth - (bufferLength - 1) * barSpacing) / bufferLength;

      // Clear the canvas completely
      chartContext.clearRect(0, 0, chartWidth, chartHeight);

      for (let i = 0; i < bufferLength; i++) {
        const barHeight = dataArray[i] / 255 * chartHeight / 2;
        const x = i * (barWidth + barSpacing);
        const y = chartHeight / 2 - barHeight;
        chartContext.fillStyle = '#666';

        // Draw upward bar
        chartContext.fillRect(x, y, barWidth, barHeight);

        // Draw downward bar
        chartContext.fillRect(x, chartHeight / 2, barWidth, barHeight);
      }
    }

    // Request the next frame only if still active
    if (isActive) {
      animationFrameId = requestAnimationFrame(checkSilence);
    }
  }

  // Ensure AudioContext is running before starting silence detection
  if (audioContext.state === 'suspended') {
    audioContext.resume().then(setupAndStart).catch(function(err) {
      console.warn('Error resuming AudioContext:', err);
      // Try to start anyway as a fallback
      setupAndStart();
    });
  } else {
    setupAndStart();
  }

  // Return a function to close the audio context and cancel animation frame
  return function () {
    // Mark as inactive to prevent further processing
    isActive = false;
    
    // Cancel animation frame if active
    if (animationFrameId) {
      cancelAnimationFrame(animationFrameId);
      animationFrameId = null;
    }
    
    // Disconnect nodes to prevent memory leaks
    try {
      if (streamNode) {
        streamNode.disconnect();
      }
      if (analyser) {
        analyser.disconnect();
      }
    } catch (e) {
      console.warn('Error disconnecting audio nodes:', e);
    }
    
    // Close the audio context (important for macOS)
    if (audioContext && audioContext.state !== 'closed') {
      audioContext.close().catch(err => 
        console.warn('Error closing AudioContext:', err)
      );
    }
  };
}

//////////////////////////////
// Set up audio recording
//////////////////////////////

// Detect iOS/iPadOS
const isIOSDevice = /iPad|iPhone|iPod/.test(navigator.userAgent) || 
                  (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);

// Hide voice button on iOS/iPadOS devices on document ready
document.addEventListener('DOMContentLoaded', function() {
  if (isIOSDevice) {
    // Hide the voice button completely on iOS/iPadOS
    const voiceEl = $id("voice");
    $hide(voiceEl);
  }
});

const voiceButton = $id("voice");
let mediaRecorder;
let localStream;
let isListening = false;
let silenceDetected = true;

let workerOptions = {};

// Build complete URL to properly load WASM file inside Worker
const protocol = window.location.protocol;
const host = window.location.host;
const baseUrl = `${protocol}//${host}`;

workerOptions = {
  OggOpusEncoderWasmPath: `${baseUrl}/vendor/js/OggOpusEncoder.wasm`,
  WebMOpusEncoderWasmPath: `${baseUrl}/vendor/js/WebMOpusEncoder.wasm`
};

// Use native MediaRecorder when it supports opus (Chrome, Firefox, Edge).
// Fall back to OpusMediaRecorder polyfill only when native lacks opus support (Safari).
const NativeMediaRecorder = window.MediaRecorder;
if (!(NativeMediaRecorder && typeof NativeMediaRecorder.isTypeSupported === 'function' &&
      NativeMediaRecorder.isTypeSupported('audio/webm;codecs=opus'))) {
  window.MediaRecorder = OpusMediaRecorder;
}

// Function to start audio capture
function startAudioCapture() {
  // Check if navigator.mediaDevices is available
  if (typeof navigator === 'undefined' || !navigator.mediaDevices || typeof navigator.mediaDevices.getUserMedia !== 'function') {
    const errorMsg = "Media devices API is not available in this environment";
    console.error(errorMsg);
    setAlert(`<i class='fas fa-exclamation-triangle'></i> ${errorMsg}`, "danger");
    // Reset button state
    const voiceEl = $id("voice");
    if (voiceEl) {
      voiceEl.classList.toggle("btn-info");
      voiceEl.classList.toggle("btn-danger");
      voiceEl.innerHTML = '<i class="fas fa-microphone"></i> Speech Input';
    }
    ['send', 'clear', 'voice'].forEach(id => { const el = $id(id); if (el) el.disabled = false; });
    isListening = false;
    return;
  }

  // Enhanced audio constraints for better compatibility in Electron packaged app
  const constraints = {
    audio: {
      echoCancellation: true,
      noiseSuppression: true,
      autoGainControl: true,
      // Try to ensure we get a working microphone
      deviceId: 'default'
    }
  };

  navigator.mediaDevices.getUserMedia(constraints)
    .then(function (stream) {
      localStream = stream;
      // Check which STT model is selected
      const sttModelSelect = $id("stt-model");
      
      // Choose audio formats based on the selected STT model
      let mimeTypes = [
        "audio/webm;codecs=opus", // Excellent compression
        "audio/webm",             // Good compression
        "audio/mp3",              // Fallback option
        "audio/mpeg",             // Same as mp3
        "audio/mpga",             // Same as mp3
        "audio/m4a",              // Good compression
        "audio/mp4",              // Good compression
        "audio/mp4a-latm",        // AAC in MP4 container
        "audio/wav",              // Last resort, uncompressed
        "audio/x-wav",            // Last resort, uncompressed
        "audio/wave"              // Last resort, uncompressed
      ];
      
      let options;
      for (const mimeType of mimeTypes) {
        if (MediaRecorder.isTypeSupported(mimeType)) {
          options = {mimeType: mimeType};
          break;
        }
      }
      
      // Pass workerOptions only when using OpusMediaRecorder polyfill
      if (window.MediaRecorder === OpusMediaRecorder) {
        mediaRecorder = new window.MediaRecorder(stream, options, workerOptions);
      } else {
        mediaRecorder = new window.MediaRecorder(stream, options);
      }

      mediaRecorder.start();

      // Detect silence and stop recording if silence lasts more than the specified duration
      const silenceDuration = 5000; // 5000 milliseconds (5 seconds)
      const closeAudioContext = detectSilence(stream, function () {
        if (isListening) {
          silenceDetected = true;
          voiceButton.click();
        }
      }, silenceDuration);

      // Add this line to store the closeAudioContext function in the localStream object
      localStream.closeAudioContext = closeAudioContext;

    }).catch(function (err) {
      console.error("Error accessing microphone:", err);
      const micErrorText = getTranslation('ui.messages.microphoneAccessError', 'MICROPHONE ACCESS ERROR');
      setAlert(`${micErrorText}: ${err.message}`, "error");

      // Restore button state on error
      voiceButton.classList.toggle("btn-info");
      voiceButton.classList.toggle("btn-danger");
      voiceButton.innerHTML = '<i class="fas fa-microphone"></i> Speech Input';
      ['send', 'clear'].forEach(id => { const el = $id(id); if (el) el.disabled = false; });
      isListening = false;
      const spinnerEl = $id("monadic-spinner");
      $hide(spinnerEl);
      const amplitudeEl = $id("amplitude");
      $hide(amplitudeEl);
    });
}

voiceButton.addEventListener("click", function () {
  if (speechSynthesis.speaking) {
    speechSynthesis.cancel();
  }

  // "Start" button is pressed
  if (!isListening) {
  if (typeof window.isForegroundTab === 'function' && !window.isForegroundTab()) {
    return;
  }

    // Save original placeholder text to restore later
    const messageEl = $id("message");
    const originalPlaceholder = messageEl ? messageEl.getAttribute("placeholder") : '';
    // Store it as a data attribute on the message element
    if (messageEl) messageEl.dataset.originalPlaceholder = originalPlaceholder;
    // Set new placeholder for recording state
    const listeningPlaceholder = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.listeningPlaceholder') : "Listening to your voice input...";
    if (messageEl) messageEl.setAttribute("placeholder", listeningPlaceholder);

    const asrPValue = $id("asr-p-value");
    if (asrPValue) { asrPValue.textContent = ""; $hide(asrPValue); }
    // Show amplitude chart when voice recording starts
    const amplitudeEl = $id("amplitude");
    if (amplitudeEl) amplitudeEl.style.display = "inline-flex";
    silenceDetected = false;
    voiceButton.classList.toggle("btn-info");
    voiceButton.classList.toggle("btn-danger");
    const stopText = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.stopButton') : 'Stop';
    voiceButton.innerHTML = `<i class="fas fa-microphone"></i> ${stopText}`;
    const listeningText = getTranslation('ui.messages.listeningStatus', 'LISTENING . . .');
    setAlert(`<i class='fas fa-microphone'></i> ${listeningText}`, "info");
    ['send', 'clear'].forEach(id => { const el = $id(id); if (el) el.disabled = true; });
    const spinnerEl = $id("monadic-spinner");
    $show(spinnerEl);
    const listeningSpinnerText = getTranslation('ui.messages.spinnerListening', 'Listening...');
    const spinnerSpan = document.querySelector("#monadic-spinner span");
    if (spinnerSpan) spinnerSpan.innerHTML = `<i class="fas fa-microphone fa-pulse"></i> ${listeningSpinnerText}`;
    isListening = true;

    // For Electron environment, try to explicitly request permissions via bridge API
    if (window.electronAPI && window.electronAPI.requestMediaPermissions) {
      // Check if navigator.mediaDevices is available
      if (typeof navigator !== 'undefined' && navigator.mediaDevices && typeof navigator.mediaDevices.enumerateDevices === 'function') {
        // Try to enumerate devices first to trigger permission dialogs if needed
        navigator.mediaDevices.enumerateDevices()
          .then(() => {
            // Now request permissions explicitly through the bridge
            return window.electronAPI.requestMediaPermissions();
          })
          .then(success => {
            if (!success) {
              console.error("Failed to get media permissions via Electron bridge");
            }
            // Continue with getUserMedia regardless of bridge result
            startAudioCapture();
          })
          .catch(err => {
            console.error("Error in requestMediaPermissions:", err);
            // Fall back to direct getUserMedia
            startAudioCapture();
          });
      } else {
        console.warn("navigator.mediaDevices is not available, requesting permissions via bridge only");
        // Request permissions via bridge without enumerating devices
        window.electronAPI.requestMediaPermissions()
          .then(success => {
            if (!success) {
              console.error("Failed to get media permissions via Electron bridge");
            }
            // Continue with getUserMedia regardless of bridge result
            startAudioCapture();
          })
          .catch(err => {
            console.error("Error in requestMediaPermissions:", err);
            // Fall back to direct getUserMedia
            startAudioCapture();
          });
      }
    } else {
      // Standard browser environment
      startAudioCapture();
    }

  // "Stop" button is pressed
  } else if (!silenceDetected) {
    // Restore original placeholder
    const messageElStop = $id("message");
    const originalPlaceholder = (messageElStop && messageElStop.dataset.originalPlaceholder) || (typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messagePlaceholder') : "Type your message or click Speech Input button to use voice . . .");
    if (messageElStop) messageElStop.setAttribute("placeholder", originalPlaceholder);

    voiceButton.classList.toggle("btn-info");
    voiceButton.classList.toggle("btn-danger");
    voiceButton.innerHTML = '<i class="fas fa-microphone"></i> Speech Input';
    const processingText = getTranslation('ui.messages.processingStatus', 'PROCESSING ...');
    setAlert(`<i class='fas fa-cogs'></i> ${processingText}`, "warning");
    ['send', 'clear', 'voice'].forEach(id => { const el = $id(id); if (el) el.disabled = true; });
    // Update spinner to show processing state
    const processingSpeechText = getTranslation('ui.messages.spinnerProcessingSpeech', 'Processing speech...');
    const spinnerSpanStop = document.querySelector("#monadic-spinner span");
    if (spinnerSpanStop) spinnerSpanStop.innerHTML = `<i class="fas fa-cogs fa-pulse"></i> ${processingSpeechText}`;
    // Hide amplitude display immediately when processing starts
    const amplitudeElStop = $id("amplitude");
    $hide(amplitudeElStop);
    // Show cancel button during STT processing
    const cancelQueryEl = $id("cancel_query");
    $show(cancelQueryEl);
    isListening = false;

    if(mediaRecorder){
      try {
        // Set the event listener before stopping the mediaRecorder
        mediaRecorder.ondataavailable = function (event) {
          // Check if the blob size is too small (indicates no sound captured)
          // Increased threshold to 100 bytes to better detect empty recordings
          if (event.data.size <= 100) { // Increased from 44 bytes for better detection
            console.warn("No audio data detected or recording too small. Size: " + event.data.size + " bytes");
            const noAudioText = getTranslation('ui.messages.noAudioDetected', 'NO AUDIO DETECTED: Check your microphone settings');
            setAlert(noAudioText, "error");
            // Restore original placeholder
            const msgElNoAudio = $id("message");
            const origPlaceholder = (msgElNoAudio && msgElNoAudio.dataset.originalPlaceholder) || (typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messagePlaceholder') : "Type your message or click Speech Input button to use voice . . .");
            if (msgElNoAudio) msgElNoAudio.setAttribute("placeholder", origPlaceholder);

            const voiceElNoAudio = $id("voice");
            if (voiceElNoAudio) voiceElNoAudio.innerHTML = '<i class="fas fa-microphone"></i> Speech Input';
            ['send', 'clear', 'voice'].forEach(id => { const el = $id(id); if (el) el.disabled = false; });
            const ampElNoAudio = $id("amplitude");
            $hide(ampElNoAudio);
            const spinElNoAudio = $id("monadic-spinner");
            $hide(spinElNoAudio);
            return; // This prevents further processing
          }
          
          soundToBase64(event.data, function (base64) {
            if (typeof window.isForegroundTab === 'function' && !window.isForegroundTab()) {
              const msgElBg = $id("message");
              const origPlaceholder = (msgElBg && msgElBg.dataset.originalPlaceholder) || (typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messagePlaceholder') : "Type your message or click Speech Input button to use voice . . .");
              if (msgElBg) msgElBg.setAttribute("placeholder", origPlaceholder);
              const voiceElBg = $id("voice");
              if (voiceElBg) voiceElBg.innerHTML = '<i class="fas fa-microphone"></i> Speech Input';
              ['send', 'clear', 'voice'].forEach(id => { const el = $id(id); if (el) el.disabled = false; });
              const ampElBg = $id("amplitude");
              $hide(ampElBg);
              const spinElBg = $id("monadic-spinner");
              $hide(spinElBg);
              return;
            }
            // Double-check the base64 length to ensure we have actual content
            if (!base64 || base64.length < 100) {
              console.warn("Base64 audio data too small. Canceling STT processing.");
              const audioFailedText = getTranslation('ui.messages.audioProcessingFailed', 'AUDIO PROCESSING FAILED');
              setAlert(audioFailedText, "error");
              // Restore original placeholder
              const msgElFail = $id("message");
              const origPlaceholderFail = (msgElFail && msgElFail.dataset.originalPlaceholder) || (typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messagePlaceholder') : "Type your message or click Speech Input button to use voice . . .");
              if (msgElFail) msgElFail.setAttribute("placeholder", origPlaceholderFail);

              const voiceElFail = $id("voice");
              if (voiceElFail) voiceElFail.innerHTML = '<i class="fas fa-microphone"></i> Speech Input';
              ['send', 'clear', 'voice'].forEach(id => { const el = $id(id); if (el) el.disabled = false; });
              const ampElFail = $id("amplitude");
              $hide(ampElFail);
              const spinElFail = $id("monadic-spinner");
              $hide(spinElFail);
              return;
            }
            
            const convLangEl = $id("conversation-language");
            let lang_code = convLangEl ? convLangEl.value : '';
            const sttModelEl = $id("stt-model");
            let stt_model = (sttModelEl ? sttModelEl.value : '')
              || window.providerDefaults?.openai?.audio_transcription?.[0]
              || "gpt-4o-mini-transcribe-2025-12-15";

            // Extract format from the MIME type
            let format = "webm"; // Default fallback
            if (mediaRecorder.mimeType) {
              // Parse the format from the MIME type (e.g., "audio/mp3" -> "mp3")
              const mimeMatch = mediaRecorder.mimeType.match(/audio\/([^;]+)/);
              if (mimeMatch && mimeMatch[1]) {
                format = mimeMatch[1].toLowerCase();
                // Handle special cases for OpenAI API compatibility
                // OpenAI API supports: "mp3", "mp4", "mpeg", "mpga", "m4a", "wav", or "webm"
                if (format === "mpeg") format = "mp3";
                if (format === "mp4a-latm") format = "mp4";
                if (format === "x-wav" || format === "wave") format = "wav";
              }
            }
            const json = JSON.stringify({message: "AUDIO", content: base64, format: format, lang_code: lang_code, stt_model: stt_model});
            reconnect_websocket(ws, function () {
              ws.send(json);
            });
          });
        }

        mediaRecorder.stop();
        // console.log("Status: " + mediaRecorder.state);
        localStream.getTracks().forEach(track => track.stop());

        // Ensure audio context is properly closed
        if (localStream.closeAudioContext) {
          try {
            localStream.closeAudioContext();
            localStream.closeAudioContext = null; // Prevent double closure
          } catch (e) {
            console.warn('Error closing audio context:', e);
          }
        }
        
        // Make sure all audio tracks are properly stopped
        try {
          localStream.getTracks().forEach(track => {
            if (track.readyState === 'live') {
              track.stop();
            }
          });
        } catch (e) {
          console.warn('Error stopping audio tracks:', e);
        }
        
        // Clean up stream reference
        localStream = null;
        
        const asrPValueEl = $id("asr-p-value");
        $show(asrPValueEl);
        const ampElDone = $id("amplitude");
        $hide(ampElDone);
      } catch (e) {
        console.error("Error in mediaRecorder processing:", e);
        ['send', 'clear', 'voice'].forEach(id => { const el = $id(id); if (el) el.disabled = false; });
        const spinElErr = $id("monadic-spinner");
        $hide(spinElErr);
      }
    }

  } else {
    // Restore original placeholder
    const messageElSilence = $id("message");
    const originalPlaceholder = (messageElSilence && messageElSilence.dataset.originalPlaceholder) || (typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messagePlaceholder') : "Type your message or click Speech Input button to use voice . . .");
    if (messageElSilence) messageElSilence.setAttribute("placeholder", originalPlaceholder);

    voiceButton.classList.toggle("btn-info");
    voiceButton.classList.toggle("btn-danger");
    const silenceText = getTranslation('ui.messages.silenceDetected', 'SILENCE DETECTED: Check your microphone settings');
    setAlert(silenceText, "error");
    voiceButton.innerHTML = '<i class="fas fa-microphone"></i> Speech Input';
    ['send', 'clear'].forEach(id => { const el = $id(id); if (el) el.disabled = false; });
    isListening = false;

    // Hide spinner and amplitude chart when silence is detected
    const spinElSilence = $id("monadic-spinner");
    $hide(spinElSilence);
    const ampElSilence = $id("amplitude");
    $hide(ampElSilence);

    mediaRecorder.stop();
    localStream.getTracks().forEach(track => track.stop());

    // Ensure audio context is properly closed
    if (localStream.closeAudioContext) {
      try {
        localStream.closeAudioContext();
        localStream.closeAudioContext = null; // Prevent double closure
      } catch (e) {
        console.warn('Error closing audio context on silence detection:', e);
      }
    }

    // Additional cleanup to ensure all resources are released
    try {
      if (mediaRecorder) {
        mediaRecorder = null;
      }
      localStream = null;
    } catch (e) {
      console.warn('Error cleaning up media resources:', e);
    }

    const ampElSilence2 = $id("amplitude");
    $hide(ampElSilence2);
  }
});

// Enhanced sound processing function that can convert to MP3 when needed
function soundToBase64(blob, callback) {
  // Process audio blob directly without conversion
  const reader = new FileReader();
  reader.onload = function() {
    const dataUrl = reader.result;
    const base64 = dataUrl.split(',')[1];
    callback(base64);
  };
  reader.readAsDataURL(blob);
}

// Export functions to window for browser environment
window.detectSilence = detectSilence;
window.soundToBase64 = soundToBase64;

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    detectSilence,
    soundToBase64
  };
}

// Try to pre-request microphone permissions in Electron environment on page load
document.addEventListener('DOMContentLoaded', function() {
  // Only in Electron environment
  if (window.electronAPI && window.electronAPI.requestMediaPermissions) {
    window.electronAPI.requestMediaPermissions()
      .catch(err => {
        console.error("Error in pre-request media permissions:", err);
      });
  }
});