// audio context
let audioCtx = null;
let playPromise = null;

function audioInit() {
  // Simple initialization of audio context
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
  let mode = "TTS";
  if(stream) {
    mode = "TTS_STREAM";
  }

  let response_format = "mp3";

  // Initialize audio
  audioInit();

  // Early returns for invalid conditions
  if (runningOnFirefox) {
    return false;
  }

  if (!text) {
    return;
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

  // Start playback
  audio.play();
  
  // Call the callback if provided
  if (typeof callback === 'function') {
    callback(true);
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

  if (mediaSource) {
    mediaSource = null;
  }

  mediaSource = new MediaSource();
  mediaSource.addEventListener('sourceopen', () => {
    // Though TTS on FireFox is not supported, the following is needed to prevent an error
    if (runningOnFirefox) {
      sourceBuffer = mediaSource.addSourceBuffer('audio/mp4; codecs="mp3"');
    } else {
      sourceBuffer = mediaSource.addSourceBuffer('audio/mpeg');
    }
    sourceBuffer.addEventListener('updateend', processAudioDataQueue);
  });

  audio.src = URL.createObjectURL(mediaSource);
  audio.load();
}
