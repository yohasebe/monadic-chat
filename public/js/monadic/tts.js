function ttsSpeak(text, stream, callback) {

  const quality = $("#tts-quality").is(":checked");
  const voice = $("#tts-voice").val();
  const speed = parseFloat($("#tts-speed").val());

  let mode = "TTS"
  if(stream){
    mode = "TTS_STREAM"
  }

  let model = "tts-1"
  if (quality) {
    model = "tts-1-hd"
  }

  let response_format = "mp3"
  if(runningOnFirefox){
    response_format = "aac"
  }

  let playPromise = audio.play();
  if (playPromise !== undefined) {
    playPromise.then(_ => {}).catch(error => {});
  }

  if (runningOnFirefox) {
    return false;
  }

  if (!text) {
    return;
  }

  ws.send(JSON.stringify({
    message: mode,
    text: text,
    voice: voice,
    speed: speed,
    model: model,
    response_format: response_format
  }));
}

function ttsStop() {

  if (audio) {
    audio.pause();
    audio = null;
  }

  // sourceBuffer = null;
  audioDataQueue = [];

  mediaSource = new MediaSource();
  mediaSource.addEventListener('sourceopen', () => {
    console.log('MediaSource opened');
    if (runningOnFirefox) {
      sourceBuffer = mediaSource.addSourceBuffer('audio/mp4; codecs="mp4a.40.2"');
    } else {
      sourceBuffer = mediaSource.addSourceBuffer('audio/mpeg');
    }
    sourceBuffer.addEventListener('updateend', processAudioDataQueue);
  });

  audio = new Audio();
  audio.src = URL.createObjectURL(mediaSource);
  audio.load();
}
