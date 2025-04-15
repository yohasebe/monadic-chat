// audio context
let audioCtx = null;
let playPromise = null;
let ttsAudio = null;

function audioInit() {
  if (audioCtx === null) {
    audioCtx = new AudioContext();
  }
  if (audioCtx.state === 'suspended') {
    audioCtx.resume();
  }
}

function ttsSpeak(text, stream, callback) {
  // Get settings from UI
  const provider = $("#tts-provider").val();
  const voice = $("#tts-voice").val();
  const elevenlabs_voice = $("#elevenlabs-tts-voice").val();
  const speed = parseFloat($("#tts-speed").val());

  // Determine mode based on streaming flag
  let mode = stream ? "TTS_STREAM" : "TTS";
  let response_format = "mp3";

  // Initialize audio
  audioInit();

  // Early returns for invalid conditions
  if (runningOnFirefox || !text) {
    return false;
  }

  // Prepare voice data for sending
  const voiceData = {
    provider: provider,
    message: mode,
    text: text,
    voice: voice,
    elevenlabs_voice: elevenlabs_voice,
    response_format: response_format
  };

  // Add speed if it is defined and it is not 1.0
  if (speed && speed !== 1.0) {
    voiceData.speed = speed;
  }

  // Send the request to the server
  ws.send(JSON.stringify(voiceData));

  // Create audio element if it doesn't exist
  if (!ttsAudio && window.audio) {
    ttsAudio = window.audio;
  } else if (!ttsAudio) {
    ttsAudio = new Audio();
  }
  
  // Start playback (safely)
  try {
    if (ttsAudio && ttsAudio.play) {
      const playPromise = ttsAudio.play();
      if (playPromise !== undefined) {
        playPromise.catch(() => {});
      }
    }
  } catch (e) {
    // Silently handle errors
  }
  
  // Call the callback if provided
  if (typeof callback === 'function') {
    callback(true);
  }
}

function ttsStop() {
  // Handle both ttsAudio and window.audio with a single function
  const stopAudioElement = (audio) => {
    if (audio) {
      audio.pause();
      audio.src = "";
      audio.load();
    }
  };
  
  // Stop both audio elements
  stopAudioElement(ttsAudio);
  stopAudioElement(window.audio);

  // Reset the audio queue if available
  if (typeof audioDataQueue !== 'undefined') {
    audioDataQueue = [];
  }

  // Clean up MediaSource and SourceBuffer
  try {
    if (typeof sourceBuffer !== 'undefined' && sourceBuffer) {
      if (typeof processAudioDataQueue === 'function') {
        sourceBuffer.removeEventListener('updateend', processAudioDataQueue);
      }
      sourceBuffer = null;
    }

    if (typeof mediaSource !== 'undefined' && mediaSource) {
      mediaSource = null;
      
      // Create a new MediaSource if possible
      if (typeof MediaSource !== 'undefined') {
        mediaSource = new MediaSource();
        mediaSource.addEventListener('sourceopen', () => {
          try {
            sourceBuffer = mediaSource.addSourceBuffer('audio/mpeg');
            if (typeof processAudioDataQueue === 'function') {
              sourceBuffer.addEventListener('updateend', processAudioDataQueue);
            }
          } catch (e) {
            // Silently handle errors
          }
        });

        // Create a new audio element for playback
        ttsAudio = new Audio();
        ttsAudio.src = URL.createObjectURL(mediaSource);
        ttsAudio.load();
      } else {
        // For browsers without MediaSource support (like iOS Safari)
        ttsAudio = new Audio();
      }
    }
  } catch (e) {
    // Fallback
    ttsAudio = new Audio();
  }
}

// Export functions to window for browser environment
window.audioInit = audioInit;
window.ttsSpeak = ttsSpeak;
window.ttsStop = ttsStop;

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    audioInit,
    ttsSpeak,
    ttsStop
  };
}
