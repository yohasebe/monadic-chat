function ttsSpeak(text, stream, callback) {

  let mode = "TTS"
  if(stream){
    mode = "TTS_STREAM"
  }
  console.log("start: " + text);
  if (!text) {
    return;
  }

  ttsStop();

  console.log("speaking started");
  let playPromise = audio.play();
  if (playPromise !== undefined) {
    playPromise.then(_ => {}).catch(error => {});
  }

  const quality = $("#tts-quality").is(":checked");
  const voice = $("#tts-voice").val();
  const speed = parseFloat($("#tts-speed").val());

  model = "tts-1"
  if (quality) {
    model = "tts-1-hd"
  }
  response_format = "mp3"

  reconnect_websocket(ws, function (ws) {
    ws.send(JSON.stringify({
      message: mode,
      text: text,
      voice: voice,
      speed: speed,
      model: model
    }));
  });
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
    sourceBuffer = mediaSource.addSourceBuffer('audio/mpeg');
    sourceBuffer.addEventListener('updateend', processAudioDataQueue);
  });

  audio = new Audio();
  audio.src = URL.createObjectURL(mediaSource);
}
