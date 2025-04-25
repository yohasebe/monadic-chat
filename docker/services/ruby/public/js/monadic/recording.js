//////////////////////////////
// Detect silence
//////////////////////////////

function detectSilence(stream, onSilenceCallback, silenceDuration, silenceThreshold = 16) {
  const audioContext = new (window.AudioContext || window.webkitAudioContext)();
  const analyser = audioContext.createAnalyser();
  const streamNode = audioContext.createMediaStreamSource(stream);
  streamNode.connect(analyser);
  analyser.fftSize = 2048;
  const bufferLength = 32;
  const dataArray = new Uint8Array(bufferLength);

  let silenceStart = performance.now();
  let triggered = false;
  let animationFrameId;

  function checkSilence() {
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

    // Request the next frame
    animationFrameId = requestAnimationFrame(checkSilence);
  }

  checkSilence();

  // Return a function to close the audio context and cancel animation frame
  return function () {
    if (animationFrameId) {
      cancelAnimationFrame(animationFrameId);
    }
    audioContext.close();
  };
}

//////////////////////////////
// Set up audio recording
//////////////////////////////

// Detect iOS/iPadOS
const isIOSDevice = /iPad|iPhone|iPod/.test(navigator.userAgent) || 
                  (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);

// Hide voice button on iOS/iPadOS devices on document ready
$(document).ready(function() {
  if (isIOSDevice) {
    // Hide the voice button completely on iOS/iPadOS
    $("#voice").hide();
    console.log("Speech Input button hidden on iOS/iPadOS device");
  }
});

const voiceButton = $("#voice");
let mediaRecorder;
let localStream;
let isListening = false;
let silenceDetected = true;

let workerOptions = {};

// Worker内でWASMファイルを正しく読み込むために完全なURLを構築
const protocol = window.location.protocol;
const host = window.location.host;
const baseUrl = `${protocol}//${host}`;

workerOptions = {
  OggOpusEncoderWasmPath: `${baseUrl}/vendor/js/OggOpusEncoder.wasm`,
  WebMOpusEncoderWasmPath: `${baseUrl}/vendor/js/WebMOpusEncoder.wasm`
};
window.MediaRecorder = OpusMediaRecorder;

// Function to start audio capture
function startAudioCapture() {
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
  
  console.log("Starting audio capture with constraints:", JSON.stringify(constraints));
  
  navigator.mediaDevices.getUserMedia(constraints)
    .then(function (stream) {
      console.log("Audio stream obtained successfully");
      // Log information about the audio tracks
      const audioTracks = stream.getAudioTracks();
      console.log("Audio tracks:", audioTracks.length, audioTracks.map(t => t.label + " (enabled: " + t.enabled + ")"));
      
      localStream = stream;
      // Check which STT model is selected
      const sttModelSelect = $("#stt-model");
      
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
          console.log("Using MIME type:", mimeType);
          break;
        }
      }
      
      mediaRecorder = new window.MediaRecorder(stream, options, workerOptions);

      mediaRecorder.start();

      // Detect silence and stop recording if silence lasts more than the specified duration
      const silenceDuration = 5000; // 5000 milliseconds (5 seconds)
      const closeAudioContext = detectSilence(stream, function () {
        if (isListening) {
          silenceDetected = true;
          voiceButton.trigger("click");
        }
      }, silenceDuration);

      // Add this line to store the closeAudioContext function in the localStream object
      localStream.closeAudioContext = closeAudioContext;

    }).catch(function (err) {
      console.error("Error accessing microphone:", err);
      setAlert("MICROPHONE ACCESS ERROR: " + err.message, "error");
      
      // Restore button state on error
      voiceButton.toggleClass("btn-info btn-danger");
      voiceButton.html('<i class="fas fa-microphone"></i> Speech Input');
      $("#send, #clear").prop("disabled", false);
      isListening = false;
      $("#monadic-spinner").hide();
      $("#amplitude").hide();
    });
}

voiceButton.on("click", function () {
  if (speechSynthesis.speaking) {
    speechSynthesis.cancel();
  }

  // "Start" button is pressed
  if (!isListening) {
    // Save original placeholder text to restore later
    const originalPlaceholder = $("#message").attr("placeholder");
    // Store it as a data attribute on the message element
    $("#message").data("original-placeholder", originalPlaceholder);
    // Set new placeholder for recording state
    $("#message").attr("placeholder", "Listening to your voice input...");
    
    $("#asr-p-value").text("").hide();
    // Show amplitude chart when voice recording starts
    $("#amplitude").show().css("display", "inline-flex"); // Ensure proper display mode
    silenceDetected = false;
    voiceButton.toggleClass("btn-info btn-danger");
    voiceButton.html('<i class="fas fa-microphone"></i> Stop');
    setAlert("<i class='fas fa-microphone'></i> LISTENING . . .", "info");
    $("#send, #clear").prop("disabled", true);
    $("#monadic-spinner").show();
    $("#monadic-spinner span").html('<i class="fas fa-microphone fa-pulse"></i> Listening...');
    isListening = true;

    // For Electron environment, try to explicitly request permissions via bridge API
    if (window.electronAPI && window.electronAPI.requestMediaPermissions) {
      console.log("Detected Electron environment, requesting permissions via bridge API");
      // Try to enumerate devices first to trigger permission dialogs if needed
      navigator.mediaDevices.enumerateDevices()
        .then(devices => {
          console.log("Available devices:", devices.length);
          devices.forEach(device => {
            if (device.kind === 'audioinput') {
              console.log(`Audio input device: ${device.label || 'unlabeled device'} (${device.deviceId})`);
            }
          });
          
          // Now request permissions explicitly through the bridge
          return window.electronAPI.requestMediaPermissions();
        })
        .then(success => {
          if (success) {
            console.log("Media permissions granted via Electron bridge");
          } else {
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
      // Standard browser environment
      console.log("Using standard browser media API (non-Electron environment)");
      startAudioCapture();
    }

  // "Stop" button is pressed
  } else if (!silenceDetected) {
    // Restore original placeholder
    const originalPlaceholder = $("#message").data("original-placeholder") || "Type your message or click Speech Input button to use voice . . .";
    $("#message").attr("placeholder", originalPlaceholder);
    
    voiceButton.toggleClass("btn-info btn-danger");
    voiceButton.html('<i class="fas fa-microphone"></i> Speech Input');
    setAlert("<i class='fas fa-cogs'></i> PROCESSING ...", "warning");
    $("#send, #clear, #voice").prop("disabled", true);
    // Update spinner to show processing state
    $("#monadic-spinner span").html('<i class="fas fa-cogs fa-pulse"></i> Processing speech...');
    // Hide amplitude display immediately when processing starts
    $("#amplitude").hide();
    isListening = false;

    if(mediaRecorder){
      try {
        // Set the event listener before stopping the mediaRecorder
        mediaRecorder.ondataavailable = function (event) {
          // Check if the blob size is too small (indicates no sound captured)
          // Increased threshold to 100 bytes to better detect empty recordings
          if (event.data.size <= 100) { // Increased from 44 bytes for better detection
            console.log("No audio data detected or recording too small. Size: " + event.data.size + " bytes");
            setAlert("NO AUDIO DETECTED: Check your microphone settings", "error");
            // Restore original placeholder
            const origPlaceholder = $("#message").data("original-placeholder") || "Type your message or click Speech Input button to use voice . . .";
            $("#message").attr("placeholder", origPlaceholder);
            
            $("#voice").html('<i class="fas fa-microphone"></i> Speech Input');
            $("#send, #clear, #voice").prop("disabled", false);
            $("#amplitude").hide();
            $("#monadic-spinner").hide();
            return; // This prevents further processing
          }
          
          // Only process if we have sufficient audio data
          console.log("Audio data size: " + event.data.size + " bytes - Processing...");
          
          soundToBase64(event.data, function (base64) {
            // Double-check the base64 length to ensure we have actual content
            if (!base64 || base64.length < 100) {
              console.log("Base64 audio data too small. Canceling STT processing.");
              setAlert("AUDIO PROCESSING FAILED", "error");
              // Restore original placeholder
              const origPlaceholder = $("#message").data("original-placeholder") || "Type your message or click Speech Input button to use voice . . .";
              $("#message").attr("placeholder", origPlaceholder);
              
              $("#voice").html('<i class="fas fa-microphone"></i> Speech Input');
              $("#send, #clear, #voice").prop("disabled", false);
              $("#amplitude").hide();
              $("#monadic-spinner").hide();
              return;
            }
            
            let lang_code = $("#asr-lang").val();
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
              console.log("Using audio format for STT: " + format);
            }
            const json = JSON.stringify({message: "AUDIO", content: base64, format: format, lang_code: lang_code});
            reconnect_websocket(ws, function () {
              ws.send(json);
            });
          });
        }

        mediaRecorder.stop();
        // console.log("Status: " + mediaRecorder.state);
        localStream.getTracks().forEach(track => track.stop());

        // Add this line to close the audio context
        localStream.closeAudioContext();
        $("#asr-p-value").show();
        $("#amplitude").hide();
      } catch (e) {
        console.log(e);
        $("#send, #clear, #voice").prop("disabled", false);
        $("#monadic-spinner").hide();
      } 
    }

  } else {
    // Restore original placeholder
    const originalPlaceholder = $("#message").data("original-placeholder") || "Type your message or click Speech Input button to use voice . . .";
    $("#message").attr("placeholder", originalPlaceholder);
    
    voiceButton.toggleClass("btn-info btn-danger");
    setAlert("SILENCE DETECTED: Check your microphone settings", "error");
    voiceButton.html('<i class="fas fa-microphone"></i> Speech Input');
    $("#send, #clear").prop("disabled", false);
    isListening = false;
    
    // Hide spinner and amplitude chart when silence is detected
    $("#monadic-spinner").hide();
    $("#amplitude").hide();

    mediaRecorder.stop();
    localStream.getTracks().forEach(track => track.stop());

    // Add this line to close the audio context
    localStream.closeAudioContext();
    $("#amplitude").hide();
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
$(document).ready(function() {
  // Only in Electron environment
  if (window.electronAPI && window.electronAPI.requestMediaPermissions) {
    console.log("Pre-requesting media permissions in Electron environment");
    window.electronAPI.requestMediaPermissions()
      .then(result => {
        console.log("Pre-request media permissions result:", result);
      })
      .catch(err => {
        console.error("Error in pre-request media permissions:", err);
      });
  }
});