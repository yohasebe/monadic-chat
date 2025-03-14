// audio context
let audioCtx = null;
let playPromise = null;

function audioInit() {
  try {
    // Properly clean up before reinitializing
    ttsStop();
    
    // Create new audio context with error handling
    try {
      audioCtx = new AudioContext();
      if (audioCtx.state === 'suspended') {
        audioCtx.resume().catch(e => console.error("Error resuming audio context:", e));
      }
    } catch (e) {
      console.error("Error creating AudioContext:", e);
      // Try to recover by recreating everything
      audioCtx = null;
      
      // Wait a moment and try again
      setTimeout(() => {
        try {
          audioCtx = new AudioContext();
        } catch (retryError) {
          console.error("Failed to create AudioContext on retry:", retryError);
        }
      }, 500);
    }

    // Handle play promise with proper error catching
    try {
      playPromise = audio.play();
      if (playPromise !== undefined) {
        playPromise.then(_ => {
          // Playback started successfully
        }).catch(_error => {
          // Auto-play was prevented or other error
          // console.error("Audio play error:", error);
          // Don't show error to user, just log it
        });
      }
    } catch (e) {
      console.error("Error during audio play:", e);
    }
  } catch (e) {
    console.error("Critical error in audioInit:", e);
  }
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

  audioInit();

  if (runningOnFirefox) {
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

  audio.play();
}

function ttsStop() {
  try {
    if (audio) {
      audio.pause();
      audio.src = "";
    }
    audio = new Audio();

    audioDataQueue = [];

    if (sourceBuffer) {
      try {
        sourceBuffer.removeEventListener('updateend', processAudioDataQueue);
      } catch (e) {
        console.error("Error removing event listener:", e);
      }
      sourceBuffer = null;
    }

    if (audioCtx) {
      try {
        audioCtx.close();
      } catch (e) {
        console.error("Error closing AudioContext:", e);
      }
      audioCtx = null;
    }

    if (mediaSource) {
      mediaSource = null;
    }

    mediaSource = new MediaSource();
    mediaSource.addEventListener('sourceopen', () => {
      try {
        // Though TTS on FireFox is not supported, the following is needed to prevent an error
        if (runningOnFirefox) {
          sourceBuffer = mediaSource.addSourceBuffer('audio/mp4; codecs="mp3"');
        } else {
          sourceBuffer = mediaSource.addSourceBuffer('audio/mpeg');
        }
        sourceBuffer.addEventListener('updateend', processAudioDataQueue);
      } catch (e) {
        console.error("Error in sourceopen handler:", e);
      }
    });

    audio.src = URL.createObjectURL(mediaSource);
    audio.load();
  } catch (e) {
    console.error("Error in ttsStop:", e);
    // Try to recover by reinitializing
    try {
      audio = new Audio();
      mediaSource = new MediaSource();
      audioDataQueue = [];
      audio.src = URL.createObjectURL(mediaSource);
      audio.load();
    } catch (recoverError) {
      console.error("Failed to recover audio state:", recoverError);
    }
  }
}
