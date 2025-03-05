// audio context
let audioCtx = null;
let playPromise = null;

// We use the global audio variable from websocket.js

function audioInit() {
  // Don't immediately call ttsStop as it creates race conditions
  // with play/pause operations
  
  // Ensure audio context exists
  if (!audioCtx) {
    audioCtx = new AudioContext();
  } else if (audioCtx.state === 'suspended') {
    audioCtx.resume();
  }
  
  // We'll handle play() in ttsSpeak after the audio source is properly set up
}

function ttsSpeak(text, stream, callback) {

  const provider = $("#tts-provider").val();
  const voice = $("#tts-voice").val();
  const elevenlabs_voice = $("#elevenlabs-tts-voice").val();
  const speed = parseFloat($("#tts-speed").val());

  let mode = "TTS"

  if(stream){
    mode = "TTS_STREAM"
  }

  let response_format = "mp3"

  // First, properly stop any existing audio
  ttsStop();
  
  // Then initialize audio context
  audioInit();

  if (runningOnFirefox) {
    // Show a notification to the user instead of silently failing
    setAlert("<i class='fa-solid fa-circle-exclamation'></i> Text-to-speech is not supported in Firefox", "warning");
    return false;
  }

  if (!text) {
    return;
  }

  ws.send(JSON.stringify({
    provider: provider,
    message: mode,
    text: text,
    voice: voice,
    elevenlabs_voice: elevenlabs_voice,
    speed: speed,
    // model: model,
    response_format: response_format
  }));
  
  if (audio) {
    // Prepare audio playback
    audio.oncanplay = () => {
      // Play only when ready
      playPromise = audio.play();
      if (playPromise !== undefined) {
        playPromise.then(_ => {
          console.log("Audio playback started successfully");
        }).catch(error => {
          console.error("Error playing audio:", error);
          setAlert("<i class='fa-solid fa-circle-exclamation'></i> Error starting audio playback", "warning");
        });
      }
    };
  }
}

function ttsStop() {
  if (audio) {
    audio.pause();
    audio.src = "";
  }
  audio = new Audio();

  audioDataQueue = [];

  if (sourceBuffer) {
    sourceBuffer.removeEventListener('updateend', processAudioDataQueue);
    sourceBuffer = null;
  }

  if (audioCtx) {
    audioCtx.close();
    audioCtx = null;
  }

  if (mediaSource) {
    mediaSource = null;
  }

  try {
    mediaSource = new MediaSource();
    mediaSource.addEventListener('sourceopen', () => {
      try {
        // Use consistent MIME type for Firefox
        const mimeType = runningOnFirefox ? 'audio/mp4; codecs="mp3"' : 'audio/mpeg';
        
        if (MediaSource.isTypeSupported(mimeType)) {
          sourceBuffer = mediaSource.addSourceBuffer(mimeType);
          sourceBuffer.addEventListener('updateend', processAudioDataQueue);
        } else {
          console.error(`MIME type ${mimeType} is not supported in this browser`);
          setAlert("<i class='fa-solid fa-circle-exclamation'></i> Audio format not supported in this browser", "warning");
        }
      } catch (err) {
        console.error("Error adding source buffer:", err);
        setAlert("<i class='fa-solid fa-circle-exclamation'></i> Error initializing audio", "warning");
      }
    });

    mediaSource.addEventListener('error', (e) => {
      console.error("MediaSource error:", e);
      setAlert("<i class='fa-solid fa-circle-exclamation'></i> Audio playback error", "warning");
    });

    // Setup error handling before setting the source
    audio.onerror = (e) => {
      // Only show error if not during initialization
      if (audio.readyState > 0) {
        console.error("Audio element error:", e);
        setAlert("<i class='fa-solid fa-circle-exclamation'></i> Audio playback failed", "warning");
      }
    };
    
    // Then set the source and load
    audio.src = URL.createObjectURL(mediaSource);
    audio.load();
  } catch (err) {
    console.error("MediaSource initialization error:", err);
    setAlert("<i class='fa-solid fa-circle-exclamation'></i> Audio system initialization failed", "warning");
  }
}

