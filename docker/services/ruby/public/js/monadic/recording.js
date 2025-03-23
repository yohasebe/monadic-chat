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
    const chartWidth = chartCanvas.width;
    const chartHeight = chartCanvas.height;
    const barSpacing = 4;
    const barWidth = (chartWidth - (bufferLength - 1) * barSpacing) / bufferLength;
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

const voiceButton = $("#voice");
let mediaRecorder;
let localStream;
let isListening = false;
let silenceDetected = true;

let workerOptions = {};

workerOptions = {
  OggOpusEncoderWasmPath: "https://cdn.jsdelivr.net/npm/opus-media-recorder@latest/OggOpusEncoder.wasm",
  WebMOpusEncoderWasmPath: "https://cdn.jsdelivr.net/npm/opus-media-recorder@latest/WebMOpusEncoder.wasm"
};
window.MediaRecorder = OpusMediaRecorder;

voiceButton.on("click", function () {
  if (speechSynthesis.speaking) {
    speechSynthesis.cancel();
  }

  // "Start" button is pressed
  if (!isListening) {
    $("#asr-p-value").text("").hide();
    $("#amplitude").show();
    silenceDetected = false;
    voiceButton.toggleClass("btn-warning btn-danger");
    voiceButton.html('<i class="fas fa-microphone"></i> Stop');
    setAlert("<i class='fas fa-microphone'></i> LISTENING . . .", "info");
    $("#send, #clear").prop("disabled", true);
    isListening = true;

    navigator.mediaDevices.getUserMedia({audio: true})
      .then(function (stream) {
        localStream = stream;
        // Check which STT model is selected
        const sttModelSelect = $("#stt-model");
        
        // Choose audio formats based on the selected STT model
        let mimeTypes;
        
        mimeTypes = [
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
        console.log(err);
      });

    // "Stop" button is pressed
  } else if (!silenceDetected) {
    voiceButton.toggleClass("btn-warning btn-danger");
    voiceButton.html('<i class="fas fa-microphone"></i> Speech Input');
    setAlert("<i class='fas fa-cogs'></i> PROCESSING ...", "warning");
    $("#send, #clear, #voice").prop("disabled", true);
    isListening = false;

    if(mediaRecorder){
      try {
        // Set the event listener before stopping the mediaRecorder
        mediaRecorder.ondataavailable = function (event) {
          // Check if the blob size is too small (indicates no sound captured)
          // Increased threshold to 100 bytes to better detect empty recordings
          if (event.data.size <= 100) { // Increased from 44 bytes for better detection
            console.log("No audio data detected or recording too small. Size: " + event.data.size + " bytes");
            setAlert("<i class='fas fa-exclamation-triangle'></i> NO AUDIO DETECTED: Check your microphone settings", "error");
            $("#voice").html('<i class="fas fa-microphone"></i> Speech Input');
            $("#send, #clear, #voice").prop("disabled", false);
            $("#amplitude").hide();
            return; // This prevents further processing
          }
          
          // Only process if we have sufficient audio data
          console.log("Audio data size: " + event.data.size + " bytes - Processing...");
          
          soundToBase64(event.data, function (base64) {
            // Double-check the base64 length to ensure we have actual content
            if (!base64 || base64.length < 100) {
              console.log("Base64 audio data too small. Canceling STT processing.");
              setAlert("<i class='fas fa-exclamation-triangle'></i> AUDIO PROCESSING FAILED", "error");
              $("#voice").html('<i class="fas fa-microphone"></i> Speech Input');
              $("#send, #clear, #voice").prop("disabled", false);
              $("#amplitude").hide();
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
      } 
    }

  } else {
    voiceButton.toggleClass("btn-warning btn-danger");
    setAlert("<i class='fas fa-exclamation-triangle'></i> SILENCE DETECTED: Check your microphone settings", "error");
    voiceButton.html('<i class="fas fa-microphone"></i> Speech Input');
    $("#send, #clear").prop("disabled", false);
    isListening = false;

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
