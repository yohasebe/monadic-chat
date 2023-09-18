let speakQueue = [];
let voicesLoaded;

if (runningOnChrome) {
  voicesLoaded = false;
  // Move the event listener registration outside of the processSpeakQueue function
  speechSynthesis.addEventListener('voiceschanged', function () {
    voicesLoaded = true;
  });
} else {
  voicesLoaded = true;
}

let lang_selections = {};

function setupLanguages(refresh, default_lang) {

  const userLang = getCookie("userLang");
  default_lang = userLang || default_lang;

  const userVoice = getCookie("userVoice");
  default_voice = userVoice || null;

  let userRate = getCookie("userRate");
  default_rate = userRate ? parseFloat(userRate).toFixed(1) : 1.0;
  $("#speech-rate").val(default_rate || 1.0);
  $("#speech-rate-value").text(default_rate);


  const voices = window.speechSynthesis.getVoices();
  if (voices.length === 0) {
    return false;
  }
  for (const i in voices) {
    if (voices[i].localService && voices[i].name.indexOf("Siri") >= 0) {
      continue;
    }
    const vlang = voices[i].lang;
    const vname = voices[i].name;
    if (lang_selections[vlang]) {
      lang_selections[vlang][vname] = voices[i];
    } else {
      lang_selections[vlang] = {};
      lang_selections[vlang][vname] = voices[i];
    }
  }

  let vlangs = Object.keys(lang_selections);
  vlangs = vlangs.sort().filter(function (x, i, self) {
    return self.indexOf(x) === i;
  });

  const default_lang_index = vlangs.indexOf(default_lang);
  const f = vlangs.splice(default_lang_index, 1)[0];
  vlangs.splice(0, 0, f);

  if ($('#speech-lang option').length === 0) {
    const lctagsUrl = "http://localhost:4567/lctags"

    fetch(lctagsUrl)
      .then((response) => {
        if (!response.ok) {
          throw new Error("Network response was not ok");
        }
        return response.json();
      })
      .then((data) => {
        for (const i in vlangs) {
          const key = vlangs[i];
          const lctag = key.toUpperCase().split('-');
          let ctstr = "";
          if (data && lctag.length > 0) {
            const language = data["languages"][lctag[0]];
            const country = data["countries"][lctag[1]];
            if (language) {
              ctstr += language;
              if (country) {
                ctstr += (' (' + country + ')');
              } else {
                ctstr += ' [' + key + ']';
              }
            } else {
              ctstr = key;
            }
          } else {
            ctstr = key;
          }
          $("#speech-lang").append('<option value="' + key + '">' + ctstr + '</option>');
        }
      })
      .catch(() => {
        for (const i in vlangs) {
          const key = vlangs[i];
          const ctstr = key;
          $("#speech-lang").append('<option value="' + key + '">' + ctstr + '</option>');
        }
      })
      .finally(() => {
        if (vlangs.length > 0) {
          const default_lang = vlangs[0];
          $("#speech-lang").val(default_lang);
          setupVoices(refresh, default_voice);
          return true;
        } else {
          return false;
        }
      });
  }
}

function processSpeakQueue(callback) {
  if (speakQueue.length === 0) {
    if (callback){
      callback();
    }
    return;
  }

  const { text, lang } = speakQueue.shift();
  const read = function () {
    const utterance = new SpeechSynthesisUtterance(text);

    if ($("#auto-lang").prop("checked")) {
      switch (lang) {
        case "ja":
          utterance.lang = "ja-JP";
          // utterance.voice = speechSynthesis.getVoices().filter((voice) => voice.name === "Google 日本語")[0];
          break;
        case "en":
          utterance.lang = "en-US";
          utterance.voice = speechSynthesis.getVoices().filter((voice) => voice.name === "Google US English")[0];
          break;
        default:
          utterance.lang = lang;
          break;
      }
    } else if (params["speech_lang"]) {
      utterance.lang = params["speech_lang"];
      if (params["speech_voice"]) {
        utterance.voice = speechSynthesis.getVoices().filter((voice) => voice.name === params["speech_voice"])[0];
      }
    } else {
      utterance.lang = lang;
    }

    if (params["speech_rate"]) {
      utterance.rate = params["speech_rate"];
    }


    utterance.onend = function () {
      processSpeakQueue(callback);
    };

    speechSynthesis.speak(utterance);
  };

  if (!voicesLoaded) {
    // Wait for the voiceschanged event to fire before calling read()
    const waitForVoices = setInterval(() => {
      if (voicesLoaded) {
        clearInterval(waitForVoices);
        read();
      }
    }, 200);
  } else {
    read();
  }
}

function speak(text, lang, callback) {
  speakQueue.push({ text, lang });
  processSpeakQueue(callback);
}

function setupVoices(refresh, voice){
  const lang_selected = $('#speech-lang option:selected').val();
  const voices = lang_selections[lang_selected];
  if(refresh || $('#speech-voice option').length == 0){
    $("#speech-voice").empty();
    let set_voice_selected = false;
    for (let i in voices){
      if (voice && voice == voices[i].name) {
        $('#speech-voice').append('<option value="' + voices[i].name + '" selected>' + voices[i].name + '</option>');
        set_voice_selected = true;
      } else if(!set_voice_selected && (voices[i].name.includes("Google") || voices[i].name.includes("Natural"))){
        $('#speech-voice').append('<option value="' + voices[i].name +'" selected>' + voices[i].name +'</option>');
        set_voice_selected = true;
      } else if(!set_voice_selected && !runningOnChrome && voices[i].name.includes("Samantha")){
        $('#speech-voice').append('<option value="' + voices[i].name +'" selected>' + voices[i].name +'</option>');
        set_voice_selected = true;
      } else {
        $('#speech-voice').append('<option value="' + voices[i].name +'">' + voices[i].name +'</option>');
      }
    }
  }
}
