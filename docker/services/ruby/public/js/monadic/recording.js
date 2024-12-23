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
    requestAnimationFrame(checkSilence);
  }

  checkSilence();

  // Return a function to close the audio context
  return function () {
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
        const options = {mimeType: "audio/webm;codecs=opus"};
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
    voiceButton.html('<i class="fas fa-microphone"></i> Voice Input');
    setAlert("<i class='fas fa-cogs'></i> PROCESSING ...", "warning");
    $("#send, #clear, #voice").prop("disabled", true);
    isListening = false;

    if(mediaRecorder){
      try {
        // Set the event listener before stopping the mediaRecorder
        mediaRecorder.ondataavailable = function (event) {
          soundToBase64(event.data, function (base64) {
            let lang_code = $("#asr-lang").val();
            let format = "webm";
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
    setAlert("<i class='fas fa-exclamation-triangle'></i> SILENCE DETECTED: Please check your microphone settings and try again", "error");
    voiceButton.html('<i class="fas fa-microphone"></i> Voice Input');
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

function soundToBase64(blob, callback) {
  const reader = new FileReader();
  reader.onload = function () {
    const dataUrl = reader.result;
    const base64 = dataUrl.split(',')[1];
    callback(base64);
  };
  reader.readAsDataURL(blob);
}

