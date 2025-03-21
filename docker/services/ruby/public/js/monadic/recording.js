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
        const currentSttModel = sttModelSelect.length ? sttModelSelect.val() : "gpt-4o-mini-transcribe";
        
        // Choose audio formats based on the selected STT model
        let mimeTypes;
        
        if (currentSttModel === "whisper-1") {
          // WebM works well with whisper-1 and has good compression
          mimeTypes = [
            "audio/webm;codecs=opus", // Excellent compression, works with whisper-1
            "audio/webm",             // Good compression, works with whisper-1
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
        } else {
          // For gpt-4o models, ONLY use MP3 as maximum compatibility option
          mimeTypes = [
            "audio/mp3",           // Highly compatible, good compression
            "audio/mpeg",          // Same as mp3
            "audio/mpga"           // Same as mp3
          ];
        }
        
        let options;
        for (const mimeType of mimeTypes) {
          if (MediaRecorder.isTypeSupported(mimeType)) {
            options = {mimeType: mimeType};
            break;
          }
        }
        
        // If no supported type was found, use appropriate fallback
        if (!options) {
          const currentSttModel = $("#stt-model").val() || "gpt-4o-mini-transcribe";
          
          if (currentSttModel === "whisper-1") {
            // For whisper-1, try WebM first, then WAV
            if (MediaRecorder.isTypeSupported("audio/webm")) {
              options = {mimeType: "audio/webm"};
            } else if (MediaRecorder.isTypeSupported("audio/wav")) {
              options = {mimeType: "audio/wav"};
            } else {
              // Absolute fallback
              options = {};
            }
          } else {
            // For gpt-4o models, use default format
            options = {};
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
          soundToBase64(event.data, function (base64) {
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
    // console.log("Status: " + mediaRecorder.state);
    localStream.getTracks().forEach(track => track.stop());

    // Add this line to close the audio context
    localStream.closeAudioContext();
    $("#amplitude").hide();
  }
});

// Enhanced sound processing function that can convert to MP3 when needed
function soundToBase64(blob, callback) {
  // Get current STT model to determine if MP3 conversion would be beneficial
  const sttModelSelect = $("#stt-model");
  const currentSttModel = sttModelSelect.length ? sttModelSelect.val() : "gpt-4o-mini-transcribe";
  
  
  // If blob is already in a compressed format (MP3, WebM) or we're using whisper-1 with WebM, use as-is
  if (blob.type.includes('mp3') || 
      blob.type.includes('mpeg') || 
      (blob.type.includes('webm') && currentSttModel === "whisper-1")) {
    const reader = new FileReader();
    reader.onload = function() {
      const dataUrl = reader.result;
      const base64 = dataUrl.split(',')[1];
      callback(base64);
    };
    reader.readAsDataURL(blob);
    return;
  }
  
  // For WAV formats or any other format with gpt-4o models, convert to MP3
  // Only attempt conversion if lamejs is available (loaded from CDN)
  
  if (typeof lamejs !== 'undefined' && (blob.type.includes('wav') || currentSttModel.includes('gpt-4o'))) {
    convertToMP3(blob, function(mp3Blob) {
      const reader = new FileReader();
      reader.onload = function() {
        const dataUrl = reader.result;
        const base64 = dataUrl.split(',')[1];
        callback(base64);
      };
      reader.readAsDataURL(mp3Blob);
    });
    return;
  }
  
  // Default handling for when MP3 conversion is not available
  const reader = new FileReader();
  reader.onload = function() {
    const dataUrl = reader.result;
    const base64 = dataUrl.split(',')[1];
    callback(base64);
  };
  
  reader.readAsDataURL(blob);
}

