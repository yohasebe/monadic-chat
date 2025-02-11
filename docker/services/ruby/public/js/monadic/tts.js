// audio context
let audioCtx = null;
let playPromise = null;

function audioInit() {
  ttsStop();
  audioCtx = new AudioContext();

  if (audioCtx.state === 'suspended') {
    audioCtx.resume();
  }

  playPromise = audio.play();
  if (!playPromise || playPromise !== undefined) {
    playPromise.then(_ => {}).catch(_error => {});
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

  mediaSource = new MediaSource();
  mediaSource.addEventListener('sourceopen', () => {
    // if (runningOnFirefox) {
    //   sourceBuffer = mediaSource.addSourceBuffer('audio/mp4; codecs="mp3"');
    // } else {
      sourceBuffer = mediaSource.addSourceBuffer('audio/mpeg');
    // }
    sourceBuffer.addEventListener('updateend', processAudioDataQueue);
  });

  audio.src = URL.createObjectURL(mediaSource);
  audio.load();
}

