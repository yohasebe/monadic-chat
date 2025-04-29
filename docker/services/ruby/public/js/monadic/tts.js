// audio context
let audioCtx = null;
let playPromise = null;
let ttsAudio = null;

// Create a lazy initializer for audioContext to prevent unnecessary contexts
function audioInit() {
  if (audioCtx === null) {
    // Create a new AudioContext only when needed
    audioCtx = new AudioContext();
    
    // For macOS specifically, add an event listener to close context when inactive
    const isMac = /Mac/.test(navigator.platform);
    if (isMac) {
      // Close audio context when window loses focus (important for macOS)
      window.addEventListener('blur', function() {
        if (audioCtx && audioCtx.state !== 'closed') {
          // Just suspend (don't close) in case we need it again soon
          audioCtx.suspend().catch(err => console.warn('Error suspending AudioContext:', err));
        }
      }, { passive: true });
    }
  }
  
  if (audioCtx.state === 'suspended') {
    audioCtx.resume().catch(err => console.warn('Error resuming AudioContext:', err));
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
      try {
        audio.pause();
        
        // Cancel any queued audio tasks
        if (audio.srcObject) {
          audio.srcObject = null;
        }
        
        // Remove all event listeners
        audio.oncanplay = null;
        audio.onplay = null;
        audio.onended = null;
        audio.onerror = null;
        
        // Clear source and reload to free resources
        audio.src = "";
        audio.load();
      } catch (e) {
        console.warn('Error stopping audio element:', e);
      }
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
      // Properly close MediaSource if possible
      if (mediaSource.readyState === 'open') {
        try {
          mediaSource.endOfStream();
        } catch (e) {
          console.warn('Error ending media source stream:', e);
        }
      }
      
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
            console.warn('Error creating source buffer:', e);
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
    
    // For macOS specifically, properly manage AudioContext
    const isMac = /Mac/.test(navigator.platform);
    if (isMac && audioCtx && audioCtx.state !== 'closed') {
      // Suspend but don't close - we might need it again soon
      audioCtx.suspend().catch(err => console.warn('Error suspending AudioContext:', err));
    }
    
  } catch (e) {
    console.warn('Error in ttsStop:', e);
    // Fallback
    ttsAudio = new Audio();
  }
  
  // Clear any pending audio promises
  playPromise = null;
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
