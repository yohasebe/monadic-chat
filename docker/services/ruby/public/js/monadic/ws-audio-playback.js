/**
 * ws-audio-playback.js
 *
 * All audio playback logic extracted from websocket.js:
 * MediaSource, iOS, PCM, WAV, active-element tracking.
 */
(function() {
  "use strict";

  const C = window.WsAudioConstants || {};

  // ── iOS audio state ────────────────────────────────────────────────
  let iosAudioBuffer = [];
  let isIOSAudioPlaying = false;
  let iosAudioQueue = [];
  let iosAudioElement = null;

  // ── Handler references for cleanup ─────────────────────────────────
  let mediaSourceOpenHandler = null;
  let sourceBufferUpdateEndHandler = null;
  let audioCanPlayHandler = null;

  // ── MediaSource / Audio elements ───────────────────────────────────
  let audioContext = null;
  let mediaSource = null;
  let audio = null;
  let sourceBuffer = null;
  let audioDataQueue = [];

  // Create AudioContext for iOS fallback
  if (!C.hasMediaSourceSupport && C.hasAudioContextSupport && C.isIOS) {
    try {
      const AudioContextClass = window.AudioContext || window.webkitAudioContext;
      audioContext = new AudioContextClass();
    } catch (e) {
      console.error("[Audio] Failed to create AudioContext:", e);
    }
  }

  // ── Active audio element registry ──────────────────────────────────
  const activeAudioElements = new Set();

  function registerAudioElement(el) {
    if (!el) return;
    activeAudioElements.add(el);
    const cleanup = function() { activeAudioElements.delete(el); };
    el.addEventListener('ended', cleanup, { once: true });
    el.addEventListener('error', cleanup, { once: true });
  }

  function stopAllActiveAudio() {
    activeAudioElements.forEach(function(el) {
      try {
        el.pause();
        el.src = "";
        el.onended = null;
        el.onerror = null;
        el.oncanplay = null;
        el.onplay = null;
      } catch (e) { /* ignore */ }
    });
    activeAudioElements.clear();

    if (iosAudioElement) {
      try {
        iosAudioElement.pause();
        iosAudioElement.src = "";
        iosAudioElement.onended = null;
        iosAudioElement.onerror = null;
      } catch (e) { /* ignore */ }
    }
  }

  // ── initializeMediaSourceForAudio ──────────────────────────────────

  function initializeMediaSourceForAudio() {
    if ('MediaSource' in window && !window.basicAudioMode) {
      try {
        if (mediaSource && mediaSourceOpenHandler) {
          try { mediaSource.removeEventListener('sourceopen', mediaSourceOpenHandler); } catch (e) { console.warn("[Audio] removeEventListener sourceopen failed:", e); }
        }
        if (sourceBuffer && sourceBufferUpdateEndHandler) {
          try { sourceBuffer.removeEventListener('updateend', sourceBufferUpdateEndHandler); } catch (e) { console.warn("[Audio] removeEventListener updateend failed:", e); }
        }

        mediaSource = new MediaSource();

        mediaSourceOpenHandler = function() {
          if (!sourceBuffer && mediaSource.readyState === 'open') {
            try {
              if (navigator.userAgent.toLowerCase().indexOf('firefox') > -1) {
                window.firefoxAudioMode = true;
                window.firefoxAudioQueue = [];
              } else {
                sourceBuffer = mediaSource.addSourceBuffer('audio/mpeg');
                sourceBufferUpdateEndHandler = processAudioDataQueue;
                sourceBuffer.addEventListener('updateend', sourceBufferUpdateEndHandler);
              }
            } catch (e) {
              console.error("Error setting up MediaSource: ", e);
              window.basicAudioMode = true;
            }
          }
        };

        mediaSource.addEventListener('sourceopen', mediaSourceOpenHandler);

        if (!audio) {
          audio = new Audio();
          registerAudioElement(audio);
          audio.src = URL.createObjectURL(mediaSource);
          window.audio = audio;

          audioCanPlayHandler = function() {
            const isQueueActive = (window.getIsProcessingAudioQueue && window.getIsProcessingAudioQueue()) ||
                                  (window.globalAudioQueue && window.globalAudioQueue.length > 0) ||
                                  window._currentSegmentAudio;
            if (isQueueActive) return;

            if (window.autoSpeechActive || window.autoPlayAudio) {
              const playPromise = audio.play();
              if (playPromise !== undefined) {
                playPromise.then(function() {
                  if (window.autoSpeechActive || window.autoPlayAudio) {
                    var sp = $id("monadic-spinner");
                    if (sp) {
                      $hide(sp);
                      var spIcon = sp.querySelector("span i");
                      if (spIcon) { spIcon.classList.remove("fa-headphones"); spIcon.classList.add("fa-comment"); }
                      var spSpan = sp.querySelector("span");
                      if (spSpan) spSpan.innerHTML = '<i class="fas fa-comment fa-pulse"></i> Starting';
                    }
                    if (window.autoTTSSpinnerTimeout) {
                      clearTimeout(window.autoTTSSpinnerTimeout);
                      window.autoTTSSpinnerTimeout = null;
                    }
                    window.autoSpeechActive = false;
                    window.autoPlayAudio = false;
                  }
                }).catch(function(err) {
                  var sp2 = $id("monadic-spinner");
                  if (sp2) {
                    $hide(sp2);
                    var sp2Icon = sp2.querySelector("span i");
                    if (sp2Icon) { sp2Icon.classList.remove("fa-headphones"); sp2Icon.classList.add("fa-comment"); }
                    var sp2Span = sp2.querySelector("span");
                    if (sp2Span) sp2Span.innerHTML = '<i class="fas fa-comment fa-pulse"></i> Starting';
                  }
                  if (window.autoTTSSpinnerTimeout) {
                    clearTimeout(window.autoTTSSpinnerTimeout);
                    window.autoTTSSpinnerTimeout = null;
                  }
                  window.autoSpeechActive = false;
                  window.autoPlayAudio = false;

                  if (err.name === 'NotAllowedError') {
                    const enableAudio = function() {
                      audio.play().then(function() {
                        document.removeEventListener('click', enableAudio);
                      }).catch(function(e) {
                        console.error("[Audio] Failed to start playback:", e);
                      });
                    };
                    document.addEventListener('click', enableAudio);
                    const clickAudioText = typeof getTranslation === 'function'
                      ? getTranslation('ui.messages.clickToEnableAudio', 'Click anywhere to enable audio')
                      : 'Click anywhere to enable audio';
                    if (typeof setAlert === 'function') {
                      setAlert('<i class="fas fa-volume-up"></i> ' + clickAudioText, 'info');
                    }
                  }
                });
              }
            }
          };

          audio.addEventListener('canplay', audioCanPlayHandler);
        }

      } catch (e) {
        console.error("Error creating MediaSource: ", e);
        window.basicAudioMode = true;
      }
    } else {
      window.basicAudioMode = true;
    }
  }

  // ── resetAudioElements ─────────────────────────────────────────────

  function resetAudioElements() {
    try {
      if (audio && audioCanPlayHandler) {
        try { audio.removeEventListener('canplay', audioCanPlayHandler); } catch (e) {
          console.warn('[resetAudioElements] Error removing canplay listener:', e);
        }
      }
      if (sourceBuffer && sourceBufferUpdateEndHandler) {
        try { sourceBuffer.removeEventListener('updateend', sourceBufferUpdateEndHandler); } catch (e) {
          console.warn('[resetAudioElements] Error removing updateend listener:', e);
        }
      }
      if (mediaSource && mediaSourceOpenHandler) {
        try { mediaSource.removeEventListener('sourceopen', mediaSourceOpenHandler); } catch (e) {
          console.warn('[resetAudioElements] Error removing sourceopen listener:', e);
        }
      }

      audioCanPlayHandler = null;
      sourceBufferUpdateEndHandler = null;
      mediaSourceOpenHandler = null;

      if (audio) {
        if (!audio.paused) audio.pause();
        audio.currentTime = 0;
        if (audio.src) {
          const srcToRevoke = audio.src;
          setTimeout(function() { URL.revokeObjectURL(srcToRevoke); }, 100);
          audio.src = '';
        }
        audio.load();
        audio = null;
      }

      if (mediaSource) {
        if (sourceBuffer && mediaSource.readyState === 'open') {
          try {
            sourceBuffer.abort();
            mediaSource.removeSourceBuffer(sourceBuffer);
          } catch (e) { console.warn("[Audio] SourceBuffer cleanup failed:", e); }
        }
        if (mediaSource.readyState === 'open') {
          try { mediaSource.endOfStream(); } catch (e) { console.warn("[Audio] MediaSource.endOfStream failed:", e); }
        }
      }

      mediaSource = null;
      sourceBuffer = null;
      audioDataQueue = [];

      window.basicAudioMode = false;
      window.firefoxAudioMode = false;
      window.firefoxAudioQueue = [];

      iosAudioBuffer = [];
      isIOSAudioPlaying = false;
      iosAudioQueue = [];
      if (iosAudioElement) {
        iosAudioElement.pause();
        iosAudioElement = null;
      }
    } catch (e) {
      // Variables not yet initialized (TDZ), skip
    }
  }

  // ── playAudioDirectly ──────────────────────────────────────────────

  function playAudioDirectly(audioData) {
    try {
      if (C.isIOS) {
        playWithAudioElement(audioData);
        return;
      }

      if (audioContext && C.hasAudioContextSupport) {
        if (audioContext.state === 'suspended') audioContext.resume();

        const uint8Data = (audioData instanceof Uint8Array) ? audioData : new Uint8Array(audioData);
        const arrayBuffer = uint8Data.buffer.slice(uint8Data.byteOffset, uint8Data.byteOffset + uint8Data.byteLength);

        audioContext.decodeAudioData(arrayBuffer)
          .then(function(buffer) {
            const source = audioContext.createBufferSource();
            source.buffer = buffer;
            source.connect(audioContext.destination);
            source.start(0);
          })
          .catch(function() { playWithAudioElement(audioData); });

        setTimeout(function() {
          if (audioContext.state === 'running') playWithAudioElement(audioData);
        }, 3000);
      } else {
        playWithAudioElement(audioData);
      }
    } catch (e) {
      playWithAudioElement(audioData);
    }
  }

  // ── playWithAudioElement ───────────────────────────────────────────

  function playWithAudioElement(audioData) {
    if (C.isIOS) {
      playAudioForIOS(audioData);
      return;
    }

    try {
      const mimeTypes = ['audio/mpeg', 'audio/mp3', 'audio/aac', 'audio/ogg'];
      let blob = null;
      for (let i = 0; i < mimeTypes.length; i++) {
        try { blob = new Blob([audioData], { type: mimeTypes[i] }); break; } catch (e) { console.warn("[Audio] Blob creation failed:", e); }
      }
      if (!blob) blob = new Blob([audioData], { type: 'audio/mpeg' });

      const audioUrl = URL.createObjectURL(blob);
      const audioElement = new Audio();
      registerAudioElement(audioElement);
      audioElement.onended = function() { URL.revokeObjectURL(audioUrl); };
      audioElement.onerror = function() { URL.revokeObjectURL(audioUrl); };
      audioElement.src = audioUrl;
      audioElement.play().catch(function() { URL.revokeObjectURL(audioUrl); });
    } catch (e) { /* Silent fail */ }
  }

  // ── iOS playback (legacy) ──────────────────────────────────────────

  function playAudioForIOS(audioData) {
    try {
      iosAudioBuffer.push(audioData);
      if (isIOSAudioPlaying) return;
      processIOSAudioBuffer();
    } catch (e) { console.warn("[Audio] iOS audio buffer processing failed:", e); }
  }

  function processIOSAudioBuffer() {
    if (iosAudioBuffer.length === 0) {
      isIOSAudioPlaying = false;
      return;
    }
    isIOSAudioPlaying = true;

    try {
      let totalLength = 0;
      iosAudioBuffer.forEach(function(chunk) { totalLength += chunk.length; });
      const combinedData = new Uint8Array(totalLength);
      let offset = 0;
      iosAudioBuffer.forEach(function(chunk) { combinedData.set(chunk, offset); offset += chunk.length; });
      iosAudioBuffer = [];

      const mimeTypes = ['audio/mpeg', 'audio/mp3', 'audio/aac', 'audio/mp4'];
      let blob = null;
      for (let i = 0; i < mimeTypes.length; i++) {
        try { blob = new Blob([combinedData], { type: mimeTypes[i] }); break; } catch (e) { console.warn("[Audio] Combined Blob creation failed:", e); }
      }
      if (!blob) blob = new Blob([combinedData], { type: 'audio/mpeg' });
      const blobUrl = URL.createObjectURL(blob);

      if (!iosAudioElement) {
        iosAudioElement = new Audio();
        registerAudioElement(iosAudioElement);
        iosAudioElement.onended = function() {
          isIOSAudioPlaying = false;
          if (iosAudioBuffer.length > 0) setTimeout(processIOSAudioBuffer, C.AUDIO_QUEUE_DELAY);
          if (iosAudioElement.src) URL.revokeObjectURL(iosAudioElement.src);
        };
        iosAudioElement.onerror = function() {
          isIOSAudioPlaying = false;
          if (iosAudioElement.src) URL.revokeObjectURL(iosAudioElement.src);
          if (iosAudioBuffer.length > 0) setTimeout(processIOSAudioBuffer, C.AUDIO_QUEUE_DELAY);
        };
      } else if (iosAudioElement.src) {
        URL.revokeObjectURL(iosAudioElement.src);
      }

      iosAudioElement.controls = false;
      iosAudioElement.playsinline = true;
      iosAudioElement.muted = false;
      iosAudioElement.autoplay = false;
      iosAudioElement.src = blobUrl;
      iosAudioElement.load();

      iosAudioElement.play()
        .then(function() {})
        .catch(function(err) {
          isIOSAudioPlaying = false;
          URL.revokeObjectURL(blobUrl);
          if (err.name === 'NotAllowedError') {
            const tapAudioText = typeof getTranslation === 'function'
              ? getTranslation('ui.messages.tapToEnableIOSAudio', 'Tap to enable iOS audio')
              : 'Tap to enable iOS audio';
            if (typeof setAlert === 'function') {
              setAlert('<i class="fas fa-volume-up"></i> ' + tapAudioText, 'info');
            }
          }
        });
    } catch (e) {
      isIOSAudioPlaying = false;
      if (iosAudioBuffer.length > 0) setTimeout(processIOSAudioBuffer, C.AUDIO_QUEUE_DELAY);
    }
  }

  // ── PCM / WAV playback ─────────────────────────────────────────────

  function playPCMAudio(pcmData, sampleRate) {
    const doPlayPCM = function() {
      try {
        const numSamples = pcmData.length / 2;
        const audioBuffer = window.audioCtx.createBuffer(1, numSamples, sampleRate);
        const channelData = audioBuffer.getChannelData(0);
        for (let i = 0; i < numSamples; i++) {
          const sample = (pcmData[i * 2] | (pcmData[i * 2 + 1] << 8));
          const signedSample = sample < 0x8000 ? sample : sample - 0x10000;
          channelData[i] = signedSample / 32768.0;
        }
        const source = window.audioCtx.createBufferSource();
        source.buffer = audioBuffer;
        source.connect(window.audioCtx.destination);
        window._currentPCMSource = source;
        source.onended = function() {
          window._currentPCMSource = null;
          if (window.ttsPlaybackCallback) window.ttsPlaybackCallback(true);
        };
        source.start(0);
        if (typeof window.setTtsPlaybackStarted === 'function') {
          window.setTtsPlaybackStarted(true);
          if (typeof window.checkAndHideSpinner === 'function') window.checkAndHideSpinner();
        }
        if (window.autoTTSSpinnerTimeout) {
          clearTimeout(window.autoTTSSpinnerTimeout);
          window.autoTTSSpinnerTimeout = null;
        }
      } catch (innerError) {
        console.error("[AudioQueue] Error in doPlayPCM:", innerError);
        if (window.ttsPlaybackCallback) window.ttsPlaybackCallback(false);
      }
    };

    try {
      if (typeof audioInit === 'function') audioInit();
      if (!window.audioCtx) {
        window.audioCtx = new (window.AudioContext || window.webkitAudioContext)();
      }
      if (window.audioCtx.state === 'suspended') {
        window.audioCtx.resume().then(function() { doPlayPCM(); }).catch(function(err) {
          console.error("[AudioQueue] Failed to resume AudioContext:", err);
          if (window.ttsPlaybackCallback) window.ttsPlaybackCallback(false);
        });
      } else {
        doPlayPCM();
      }
    } catch (error) {
      console.error("[AudioQueue] Error playing PCM audio:", error);
      if (typeof window.setTextResponseCompleted === 'function') window.setTextResponseCompleted(true);
      if (typeof window.setTtsPlaybackStarted === 'function') window.setTtsPlaybackStarted(true);
      if (typeof window.checkAndHideSpinner === 'function') window.checkAndHideSpinner();
      else { $hide($id("monadic-spinner")); }

      try {
        const wavBlob = createWAVFromPCM(pcmData, sampleRate);
        const blobUrl = URL.createObjectURL(wavBlob);
        const fallbackAudio = new Audio(blobUrl);
        registerAudioElement(fallbackAudio);
        fallbackAudio.onended = function() {
          URL.revokeObjectURL(blobUrl);
          if (window.ttsPlaybackCallback) window.ttsPlaybackCallback(true);
        };
        fallbackAudio.play().catch(function(err) {
          console.error("[AudioQueue] Fallback audio playback failed:", err);
          if (typeof window.setTextResponseCompleted === 'function') window.setTextResponseCompleted(true);
          if (typeof window.setTtsPlaybackStarted === 'function') window.setTtsPlaybackStarted(true);
          if (typeof window.checkAndHideSpinner === 'function') window.checkAndHideSpinner();
          else { $hide($id("monadic-spinner")); }
          window.autoSpeechActive = false;
          window.autoPlayAudio = false;
        });
      } catch (fallbackError) {
        console.error("WAV fallback also failed:", fallbackError);
        if (typeof window.setTextResponseCompleted === 'function') window.setTextResponseCompleted(true);
        if (typeof window.setTtsPlaybackStarted === 'function') window.setTtsPlaybackStarted(true);
        if (typeof window.checkAndHideSpinner === 'function') window.checkAndHideSpinner();
        else { $hide($id("monadic-spinner")); }
      }
    }
  }

  function createWAVFromPCM(pcmData, sampleRate) {
    const numChannels = 1;
    const bitsPerSample = 16;
    const byteRate = sampleRate * numChannels * bitsPerSample / 8;
    const blockAlign = numChannels * bitsPerSample / 8;
    const dataSize = pcmData.length;

    const buffer = new ArrayBuffer(44 + dataSize);
    const view = new DataView(buffer);

    const writeString = function(offset, string) {
      for (let i = 0; i < string.length; i++) {
        view.setUint8(offset + i, string.charCodeAt(i));
      }
    };

    writeString(0, 'RIFF');
    view.setUint32(4, 36 + dataSize, true);
    writeString(8, 'WAVE');
    writeString(12, 'fmt ');
    view.setUint32(16, 16, true);
    view.setUint16(20, 1, true);
    view.setUint16(22, numChannels, true);
    view.setUint32(24, sampleRate, true);
    view.setUint32(28, byteRate, true);
    view.setUint16(32, blockAlign, true);
    view.setUint16(34, bitsPerSample, true);
    writeString(36, 'data');
    view.setUint32(40, dataSize, true);

    const dataArray = new Uint8Array(buffer, 44);
    dataArray.set(pcmData);

    return new Blob([buffer], { type: 'audio/wav' });
  }

  // ── processAudioDataQueue (MediaSource buffer feeding) ─────────────

  function processAudioDataQueue() {
    if (window.basicAudioMode) return;
    if (!mediaSource || !sourceBuffer) return;

    if (mediaSource.readyState === 'open' && audioDataQueue.length > 0 && !sourceBuffer.updating) {
      const data = audioDataQueue.shift();
      try {
        sourceBuffer.appendBuffer(data);
        const isQueueActive = (window.getIsProcessingAudioQueue && window.getIsProcessingAudioQueue()) ||
                              (window.globalAudioQueue && window.globalAudioQueue.length > 0) ||
                              window._currentSegmentAudio;
        if (audio && audio.paused && audio.readyState >= 2 && !isQueueActive) {
          audio.play().catch(function() {});
        }
      } catch (e) {
        console.error('Error appending buffer:', e);
        if (e.name === 'QuotaExceededError') {
          if (sourceBuffer.buffered.length > 0) sourceBuffer.remove(0, sourceBuffer.buffered.end(0));
          audioDataQueue = [];
        }
      }
    }
  }

  // ── processAudio (main entry point) ────────────────────────────────

  function processAudio(audioData) {
    try {
      if (!audioDataQueue) audioDataQueue = [];
      if (!mediaSource && 'MediaSource' in window && !window.basicAudioMode) {
        initializeMediaSourceForAudio();
      }

      if (window.firefoxAudioMode) {
        if (!window.firefoxAudioQueue) window.firefoxAudioQueue = [];
        window.firefoxAudioQueue.push(audioData);
        processAudioDataQueue();
      } else if (window.basicAudioMode || window.isIOS) {
        playAudioDirectly(audioData);
      } else {
        audioDataQueue.push(audioData);
        processAudioDataQueue();
        const isQueueActive = (window.getIsProcessingAudioQueue && window.getIsProcessingAudioQueue()) ||
                              (window.globalAudioQueue && window.globalAudioQueue.length > 0) ||
                              window._currentSegmentAudio;
        if (audio && audio.paused && !isQueueActive) {
          audio.play().catch(function(err) {
            if (err.name === 'NotAllowedError') {
              const clickAudioText = typeof getTranslation === 'function'
                ? getTranslation('ui.messages.clickToEnableAudioSimple', 'Click to enable audio')
                : 'Click to enable audio';
              if (typeof setAlert === 'function') {
                setAlert('<i class="fas fa-volume-up"></i> ' + clickAudioText, 'info');
              }
            }
          });
        }
      }
    } catch (e) {
      console.error("Error in audio processing:", e);
    }
  }

  // ── Namespace export ───────────────────────────────────────────────
  const ns = {
    registerAudioElement: registerAudioElement,
    stopAllActiveAudio: stopAllActiveAudio,
    initializeMediaSourceForAudio: initializeMediaSourceForAudio,
    resetAudioElements: resetAudioElements,
    playAudioDirectly: playAudioDirectly,
    playWithAudioElement: playWithAudioElement,
    playAudioForIOS: playAudioForIOS,
    processIOSAudioBuffer: processIOSAudioBuffer,
    playPCMAudio: playPCMAudio,
    createWAVFromPCM: createWAVFromPCM,
    processAudioDataQueue: processAudioDataQueue,
    processAudio: processAudio,
    // State accessors
    getIosAudioBuffer: function() { return iosAudioBuffer; },
    setIosAudioBuffer: function(v) { iosAudioBuffer = v; },
    getIsIOSAudioPlaying: function() { return isIOSAudioPlaying; },
    setIsIOSAudioPlaying: function(v) { isIOSAudioPlaying = v; },
    getIosAudioElement: function() { return iosAudioElement; },
    getMediaSource: function() { return mediaSource; },
    getAudio: function() { return audio; },
    getSourceBuffer: function() { return sourceBuffer; },
    getAudioDataQueue: function() { return audioDataQueue; },
    setAudioDataQueue: function(v) { audioDataQueue = v; },
    getAudioContext: function() { return audioContext; }
  };

  window.WsAudioPlayback = ns;

  // Backward-compat individual exports
  window.stopAllActiveAudio = stopAllActiveAudio;
  window.resetAudioElements = resetAudioElements;
  window.initializeMediaSourceForAudio = initializeMediaSourceForAudio;
  window.playAudioDirectly = playAudioDirectly;
  window.playWithAudioElement = playWithAudioElement;
  window.playAudioForIOS = playAudioForIOS;
  window.processIOSAudioBuffer = processIOSAudioBuffer;
  window.processAudio = processAudio;
  window.mediaSource = mediaSource;
  window.audio = audio;

  // Support for Jest testing environment (CommonJS)
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = ns;
  }
})();
