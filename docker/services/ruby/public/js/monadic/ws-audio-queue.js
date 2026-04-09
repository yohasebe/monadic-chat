/**
 * ws-audio-queue.js
 *
 * Sequential and global audio queue management, sequence tracking,
 * and session state reset — extracted from websocket.js.
 */
(function() {
  "use strict";

  const C = window.WsAudioConstants || {};
  const Playback = window.WsAudioPlayback || {};

  // ── Queue state ────────────────────────────────────────────────────
  let globalAudioQueue = [];
  let isProcessingAudioQueue = false;
  let currentAudioSequenceId = null;
  let currentSegmentAudio = null;
  let currentPCMSource = null;

  // ── Sequence state ─────────────────────────────────────────────────
  let nextExpectedSequence = 1;
  let pendingAudioSegments = {};
  let sequenceCheckTimer = null;
  let sequenceRetryCount = 0;
  const failedSequences = new Set();

  // ── Response / TTS completion tracking ─────────────────────────────
  let textResponseCompleted = false;
  let ttsPlaybackStarted = false;
  let lastAutoTtsMessageId = null;

  // Publish flags to window for ws-auto-speech.js checkAndHideSpinner
  window._textResponseCompleted = textResponseCompleted;
  window._ttsPlaybackStarted = ttsPlaybackStarted;

  // ── parseSequenceNumber ────────────────────────────────────────────
  function parseSequenceNumber(sequenceId) {
    if (!sequenceId || typeof sequenceId !== 'string') return null;
    const match = sequenceId.match(/^seq(\d+)_/);
    if (match && match[1]) return parseInt(match[1], 10);
    return null;
  }

  // ── addToAudioQueue ────────────────────────────────────────────────
  function addToAudioQueue(audioData, sequenceId, mimeType) {
    if (!audioData || (audioData.length !== undefined && audioData.length === 0)) {
      console.warn('[AudioQueue] Ignoring empty audio data, sequenceId:', sequenceId);
      return;
    }

    const sequenceNum = parseSequenceNumber(sequenceId);

    if (sequenceNum !== null) {
      pendingAudioSegments[sequenceNum] = {
        data: audioData,
        sequenceId: sequenceId,
        sequenceNum: sequenceNum,
        timestamp: Date.now(),
        mimeType: mimeType
      };
      try { processSequentialAudio(); } catch (e) {
        console.error('[AudioQueue] Error in processSequentialAudio:', e);
      }
    } else {
      globalAudioQueue.push({
        data: audioData,
        sequenceId: sequenceId,
        sequenceNum: null,
        timestamp: Date.now(),
        mimeType: mimeType
      });
      if (!isProcessingAudioQueue) {
        try { processGlobalAudioQueue(); } catch (e) {
          console.error('[AudioQueue] Error in processGlobalAudioQueue:', e);
          isProcessingAudioQueue = false;
        }
      }
    }
  }

  // ── processSequentialAudio ─────────────────────────────────────────
  function processSequentialAudio() {
    if (pendingAudioSegments[nextExpectedSequence]) {
      const segment = pendingAudioSegments[nextExpectedSequence];
      delete pendingAudioSegments[nextExpectedSequence];

      console.debug('[AudioQueue] Playing segment ' + nextExpectedSequence + ' in order');
      sequenceRetryCount = 0;

      const isFirstSegment = nextExpectedSequence === 1;
      if (isFirstSegment && globalAudioQueue.length === 0 && !isProcessingAudioQueue) {
        setTimeout(function() {
          const allAssistantEls = document.querySelectorAll('.role-assistant');
          const assistantCards = [];
          allAssistantEls.forEach(function(el) {
            const card = el.closest('.card');
            if (card && card.id !== 'temp-card') assistantCards.push(card);
          });
          if (assistantCards.length > 0) {
            const latestCard = assistantCards[assistantCards.length - 1];
            var cardId = latestCard.id;
            if (cardId && typeof window.highlightStopButton === 'function') {
              window.highlightStopButton(cardId);
            }
          }
        }, 50);
      }

      if (sequenceCheckTimer) {
        clearTimeout(sequenceCheckTimer);
        sequenceCheckTimer = null;
      }

      globalAudioQueue.push(segment);
      nextExpectedSequence++;

      if (!isProcessingAudioQueue) processGlobalAudioQueue();
      setTimeout(function() { processSequentialAudio(); }, 0);
    } else {
      if (!sequenceCheckTimer) {
        sequenceCheckTimer = setTimeout(function() {
          const pendingCount = Object.keys(pendingAudioSegments).length;
          sequenceRetryCount++;

          if (pendingCount > 0) {
            const availableSequences = Object.keys(pendingAudioSegments)
              .map(function(k) { return parseInt(k, 10); })
              .sort(function(a, b) { return a - b; });

            console.warn('[AudioQueue] Waiting for seq' + nextExpectedSequence +
              ' (attempt ' + sequenceRetryCount + '/' + C.MAX_SEQUENCE_RETRIES +
              '). Available: [' + availableSequences.join(', ') + ']');

            if (sequenceRetryCount >= C.MAX_SEQUENCE_RETRIES) {
              console.error('[AudioQueue] seq' + nextExpectedSequence +
                ' did not arrive after ' + sequenceRetryCount + ' attempts. Skipping to seq' + availableSequences[0]);
              failedSequences.add(nextExpectedSequence);
              nextExpectedSequence = availableSequences[0];
              sequenceRetryCount = 0;
              sequenceCheckTimer = null;
              processSequentialAudio();
            } else {
              sequenceCheckTimer = null;
              processSequentialAudio();
            }
          } else {
            sequenceCheckTimer = null;
            sequenceRetryCount = 0;
          }
        }, C.SEQUENCE_TIMEOUT_MS);
      }
    }
  }

  // ── processGlobalAudioQueue ────────────────────────────────────────
  function processGlobalAudioQueue() {
    if (globalAudioQueue.length === 0) {
      const pendingCount = Object.keys(pendingAudioSegments).length;
      if (pendingCount > 0) {
        isProcessingAudioQueue = false;
        processSequentialAudio();
        return;
      }

      isProcessingAudioQueue = false;
      currentAudioSequenceId = null;

      if (typeof window.removeStopButtonHighlight === 'function') {
        window.removeStopButtonHighlight();
      }

      if (typeof window.checkAndHideSpinner === 'function') {
        window.setTextResponseCompleted(true);
        window.setTtsPlaybackStarted(true);
        window.checkAndHideSpinner();
      } else {
        var spinner = $id("monadic-spinner");
        $hide(spinner);
      }

      if (typeof window.hideTtsToast === 'function') window.hideTtsToast();

      window.autoSpeechActive = false;
      window.autoPlayAudio = false;
      return;
    }

    isProcessingAudioQueue = true;
    const audioItem = globalAudioQueue.shift();
    currentAudioSequenceId = audioItem.sequenceId;

    if (window.isIOS || window.basicAudioMode) {
      playAudioForIOSFromQueue(audioItem.data);
    } else {
      playAudioFromQueue(audioItem);
    }
  }

  // ── playAudioFromQueue ─────────────────────────────────────────────
  function playAudioFromQueue(audioItem) {
    try {
      const audioData = audioItem.data || audioItem;
      const mimeType = audioItem.mimeType;
      const sequenceNum = audioItem.sequenceNum;

      if (!audioData || (audioData.length !== undefined && audioData.length === 0)) {
        console.warn('[AudioQueue] Skipping empty audio data for seq' + sequenceNum);
        isProcessingAudioQueue = false;
        processGlobalAudioQueue();
        return;
      }

      const handleAudioError = function(errorMsg) {
        console.error(errorMsg);
        if (sequenceNum !== null && sequenceNum !== undefined) {
          failedSequences.add(sequenceNum);
          console.warn('[AudioQueue] Marked seq' + sequenceNum + ' as failed.');
          processSequentialAudio();
        }
        isProcessingAudioQueue = false;
        processGlobalAudioQueue();
      };

      // PCM audio from Gemini
      if (mimeType && mimeType.includes("audio/L16")) {
        const mimeMatch = mimeType.match(/rate=(\d+)/);
        const sampleRate = mimeMatch ? parseInt(mimeMatch[1]) : 24000;
        window.ttsPlaybackCallback = function() {
          isProcessingAudioQueue = false;
          processGlobalAudioQueue();
        };
        if (typeof Playback.playPCMAudio === 'function') {
          Playback.playPCMAudio(audioData, sampleRate);
        }
        return;
      }

      // Standard blob playback
      const blob = new Blob([audioData], { type: mimeType || 'audio/mpeg' });
      const audioUrl = URL.createObjectURL(blob);
      const segmentAudio = new Audio();
      if (typeof Playback.registerAudioElement === 'function') {
        Playback.registerAudioElement(segmentAudio);
      }
      currentSegmentAudio = segmentAudio;
      window._currentSegmentAudio = segmentAudio;

      segmentAudio.onended = function() {
        URL.revokeObjectURL(audioUrl);
        currentSegmentAudio = null;
        window._currentSegmentAudio = null;
        isProcessingAudioQueue = false;
        processGlobalAudioQueue();
      };

      segmentAudio.onerror = function(e) {
        URL.revokeObjectURL(audioUrl);
        currentSegmentAudio = null;
        window._currentSegmentAudio = null;
        if (document.hidden) {
          isProcessingAudioQueue = false;
          processGlobalAudioQueue();
          return;
        }
        const errorDetail = e.target && e.target.error ? e.target.error : e;
        const errorMessage = (errorDetail && (errorDetail.message || errorDetail.code)) || 'Unknown error';
        handleAudioError('Segment audio error for seq' + sequenceNum + ': ' + errorMessage);
      };

      segmentAudio.src = audioUrl;
      segmentAudio.play().then(function() {
        if (typeof window.setTtsPlaybackStarted === 'function') {
          window.setTtsPlaybackStarted(true);
          if (typeof window.checkAndHideSpinner === 'function') window.checkAndHideSpinner();
        }
        if (window.autoTTSSpinnerTimeout) {
          clearTimeout(window.autoTTSSpinnerTimeout);
          window.autoTTSSpinnerTimeout = null;
        }
      }).catch(function(err) {
        if (document.hidden) {
          URL.revokeObjectURL(audioUrl);
          currentSegmentAudio = null;
          window._currentSegmentAudio = null;
          isProcessingAudioQueue = false;
          processGlobalAudioQueue();
          return;
        }
        console.error("[AudioQueue] Playback failed:", err);
        URL.revokeObjectURL(audioUrl);
        currentSegmentAudio = null;
        window._currentSegmentAudio = null;
        handleAudioError('Failed to play segment seq' + sequenceNum + ': ' + err.message);
      });
    } catch (e) {
      console.error("Error in playAudioFromQueue:", e);
      isProcessingAudioQueue = false;
      processGlobalAudioQueue();
    }
  }

  // ── iOS queue playback ─────────────────────────────────────────────
  function playAudioForIOSFromQueue(audioData) {
    try {
      const pb = window.WsAudioPlayback || {};
      const buf = pb.getIosAudioBuffer ? pb.getIosAudioBuffer() : [];
      buf.push(audioData);
      if (pb.setIosAudioBuffer) pb.setIosAudioBuffer(buf);
      if (!(pb.getIsIOSAudioPlaying && pb.getIsIOSAudioPlaying())) {
        processIOSAudioBufferWithQueue();
      }
    } catch (e) {
      setTimeout(function() { processGlobalAudioQueue(); }, C.AUDIO_ERROR_DELAY);
    }
  }

  function processIOSAudioBufferWithQueue() {
    const pb = window.WsAudioPlayback || {};
    const buf = pb.getIosAudioBuffer ? pb.getIosAudioBuffer() : [];
    if (buf.length === 0) {
      if (pb.setIsIOSAudioPlaying) pb.setIsIOSAudioPlaying(false);
      setTimeout(function() { processGlobalAudioQueue(); }, C.AUDIO_QUEUE_DELAY);
      return;
    }
    if (pb.setIsIOSAudioPlaying) pb.setIsIOSAudioPlaying(true);

    try {
      let totalLength = 0;
      buf.forEach(function(chunk) { totalLength += chunk.length; });
      const combinedData = new Uint8Array(totalLength);
      let offset = 0;
      buf.forEach(function(chunk) { combinedData.set(chunk, offset); offset += chunk.length; });
      if (pb.setIosAudioBuffer) pb.setIosAudioBuffer([]);

      const blob = new Blob([combinedData], { type: 'audio/mpeg' });
      const blobUrl = URL.createObjectURL(blob);

      let iosEl = pb.getIosAudioElement ? pb.getIosAudioElement() : null;
      if (!iosEl) {
        iosEl = new Audio();
        if (typeof Playback.registerAudioElement === 'function') {
          Playback.registerAudioElement(iosEl);
        }
      }

      iosEl.onended = function() {
        if (pb.setIsIOSAudioPlaying) pb.setIsIOSAudioPlaying(false);
        URL.revokeObjectURL(blobUrl);
        setTimeout(function() { processGlobalAudioQueue(); }, C.AUDIO_QUEUE_DELAY);
      };
      iosEl.onerror = function() {
        if (pb.setIsIOSAudioPlaying) pb.setIsIOSAudioPlaying(false);
        URL.revokeObjectURL(blobUrl);
        setTimeout(function() { processGlobalAudioQueue(); }, C.AUDIO_QUEUE_DELAY);
      };

      iosEl.src = blobUrl;
      iosEl.play().then(function() {
        console.log("[AudioQueue] iOS playback started successfully");
        if (typeof window.setTtsPlaybackStarted === 'function') {
          window.setTtsPlaybackStarted(true);
          if (typeof window.checkAndHideSpinner === 'function') window.checkAndHideSpinner();
        }
      }).catch(function(err) {
        if (pb.setIsIOSAudioPlaying) pb.setIsIOSAudioPlaying(false);
        URL.revokeObjectURL(blobUrl);
        setTimeout(function() { processGlobalAudioQueue(); }, C.AUDIO_QUEUE_DELAY);
      });
    } catch (e) {
      if (pb.setIsIOSAudioPlaying) pb.setIsIOSAudioPlaying(false);
      setTimeout(function() { processGlobalAudioQueue(); }, C.AUDIO_QUEUE_DELAY);
    }
  }

  // ── clearAudioQueue ────────────────────────────────────────────────
  function clearAudioQueue() {
    if (typeof Playback.stopAllActiveAudio === 'function') {
      Playback.stopAllActiveAudio();
    }

    globalAudioQueue.length = 0;
    isProcessingAudioQueue = false;
    currentAudioSequenceId = null;

    nextExpectedSequence = 1;
    pendingAudioSegments = {};
    sequenceRetryCount = 0;
    failedSequences.clear();

    // Clear duplicate-detection set so replaying the same audio works after queue reset
    if (window.wsHandlers && typeof window.wsHandlers.clearProcessedAudioIds === 'function') {
      window.wsHandlers.clearProcessedAudioIds();
    }
    if (sequenceCheckTimer) {
      clearTimeout(sequenceCheckTimer);
      sequenceCheckTimer = null;
    }

    if (typeof window.setTextResponseCompleted === 'function') window.setTextResponseCompleted(false);
    if (typeof window.setTtsPlaybackStarted === 'function') window.setTtsPlaybackStarted(false);

    if (currentSegmentAudio) {
      try { currentSegmentAudio.pause(); currentSegmentAudio.src = ""; currentSegmentAudio = null; } catch (e) {
        console.warn("Error stopping current segment:", e);
      }
    }
    window._currentSegmentAudio = null;

    if (currentPCMSource) {
      try { currentPCMSource.stop(); currentPCMSource = null; } catch (e) {
        console.warn("Error stopping PCM source:", e);
      }
    }
    window._currentPCMSource = null;

    const pb = window.WsAudioPlayback || {};
    if (pb.setIosAudioBuffer) pb.setIosAudioBuffer([]);
    if (pb.setIsIOSAudioPlaying) pb.setIsIOSAudioPlaying(false);
    if (pb.setAudioDataQueue) pb.setAudioDataQueue([]);
    if (typeof window.firefoxAudioQueue !== 'undefined') window.firefoxAudioQueue = [];

    if (typeof window.hideTtsToast === 'function') window.hideTtsToast();

    window.autoSpeechActive = false;
    window.autoPlayAudio = false;
  }

  // ── resetSequenceTracking (lightweight) ────────────────────────────
  function resetSequenceTracking() {
    nextExpectedSequence = 1;
    pendingAudioSegments = {};
    if (sequenceCheckTimer) {
      clearTimeout(sequenceCheckTimer);
      sequenceCheckTimer = null;
    }
  }

  // ── resetSessionState ──────────────────────────────────────────────
  function resetSessionState() {
    if (window.SessionState && typeof window.SessionState.clearMessages === 'function') {
      window.SessionState.clearMessages();
    }
    if (window.SessionState && typeof window.SessionState.resetAllFlags === 'function') {
      window.SessionState.resetAllFlags();
    }

    if (typeof Playback.resetAudioElements === 'function') {
      Playback.resetAudioElements();
    }

    window.autoSpeechActive = false;
    window.autoPlayAudio = false;
    window.ttsPlaybackStarted = false;

    if (typeof window.autoTTSSpinnerTimeout !== 'undefined' && window.autoTTSSpinnerTimeout) {
      clearTimeout(window.autoTTSSpinnerTimeout);
      window.autoTTSSpinnerTimeout = null;
    }
    if (typeof window.spinnerCheckInterval !== 'undefined' && window.spinnerCheckInterval) {
      clearInterval(window.spinnerCheckInterval);
      window.spinnerCheckInterval = null;
    }
    if (typeof window.streamingResponse !== 'undefined') window.streamingResponse = false;
    if (typeof window.ttsPlaybackCallback !== 'undefined') window.ttsPlaybackCallback = null;

    if (typeof window.setAutoSpeechSuppressed === 'function') {
      window.setAutoSpeechSuppressed(false, { reason: 'clear' });
    }
  }

  // ── Completion flag setters ────────────────────────────────────────
  function setTextResponseCompletedFn(value) {
    textResponseCompleted = value;
    window._textResponseCompleted = value;
  }

  function setTtsPlaybackStartedFn(value) {
    ttsPlaybackStarted = value;
    window._ttsPlaybackStarted = value;
  }

  // ── Namespace export ───────────────────────────────────────────────
  const ns = {
    addToAudioQueue: addToAudioQueue,
    processSequentialAudio: processSequentialAudio,
    processGlobalAudioQueue: processGlobalAudioQueue,
    clearAudioQueue: clearAudioQueue,
    playAudioFromQueue: playAudioFromQueue,
    playAudioForIOSFromQueue: playAudioForIOSFromQueue,
    processIOSAudioBufferWithQueue: processIOSAudioBufferWithQueue,
    resetSessionState: resetSessionState,
    resetSequenceTracking: resetSequenceTracking,
    parseSequenceNumber: parseSequenceNumber,
    setTextResponseCompleted: setTextResponseCompletedFn,
    setTtsPlaybackStarted: setTtsPlaybackStartedFn,
    getGlobalAudioQueue: function() { return globalAudioQueue; },
    getIsProcessingAudioQueue: function() { return isProcessingAudioQueue; },
    getCurrentSegmentAudio: function() { return currentSegmentAudio; },
    getSequenceRetryCount: function() { return sequenceRetryCount; },
    setSequenceRetryCount: function(v) { sequenceRetryCount = v; },
    getLastAutoTtsMessageId: function() { return lastAutoTtsMessageId; },
    setLastAutoTtsMessageId: function(v) { lastAutoTtsMessageId = v; }
  };

  window.WsAudioQueue = ns;

  // Backward-compat individual exports
  window.globalAudioQueue = globalAudioQueue;
  window.getIsProcessingAudioQueue = function() { return isProcessingAudioQueue; };
  window.addToAudioQueue = addToAudioQueue;
  window.clearAudioQueue = clearAudioQueue;
  window.resetSessionState = resetSessionState;
  window.resetSequenceTracking = resetSequenceTracking;
  window.setTextResponseCompleted = setTextResponseCompletedFn;
  window.setTtsPlaybackStarted = setTtsPlaybackStartedFn;

  // addToGlobalAudioQueue alias
  window.addToGlobalAudioQueue = function(audioItem) {
    globalAudioQueue.push(audioItem);
    if (!isProcessingAudioQueue) {
      try { processGlobalAudioQueue(); } catch (e) {
        console.error('[AudioQueue] Error in processGlobalAudioQueue:', e);
        isProcessingAudioQueue = false;
      }
    }
  };

  // Support for Jest testing environment (CommonJS)
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = ns;
  }
})();
