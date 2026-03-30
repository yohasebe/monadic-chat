/**
 * ws-auto-speech.js
 *
 * Auto-speech/TTS suppression, spinner control, and visibility helpers
 * extracted from websocket.js.
 */
(function() {
  "use strict";

  // ── Timing constants from ws-audio-constants.js ────────────────────
  const TTS_SPINNER_RECHECK_MS = (window.WsAudioConstants || {}).TTS_SPINNER_RECHECK_MS || 5000;
  const TTS_SPINNER_TIMEOUT_MS = (window.WsAudioConstants || {}).TTS_SPINNER_TIMEOUT_MS || 12000;

  // ── Auto-speech suppression state ──────────────────────────────────
  const autoSpeechSuppressionReasons = new Set();
  let autoSpeechSuppressed = false;

  function resetAutoSpeechSpinner() {
    const spinner = document.getElementById("monadic-spinner");
    if (!spinner) return;
    spinner.style.display = 'none';
    const spanIcon = spinner.querySelector("span i");
    if (spanIcon) {
      spanIcon.classList.remove("fa-headphones");
      spanIcon.classList.add("fa-comment");
    }
    const spanEl = spinner.querySelector("span");
    if (spanEl) spanEl.innerHTML = '<i class="fas fa-comment fa-pulse"></i> Starting';
  }

  // ── TTS Toast notice ───────────────────────────────────────────────

  function showTtsNotice(content) {
    if (typeof $ === 'undefined' || typeof bootstrap === 'undefined') return;

    const toastEl = document.getElementById('tts-toast');
    const toastBody = document.getElementById('tts-toast-body');
    if (!toastEl || !toastBody) return;

    let message = '';
    let details = '';

    if (content.notice_type === 'partial') {
      if (typeof webUIi18n !== 'undefined') {
        message = webUIi18n.t('ui.tts.partialOutput')
          .replace('{{played}}', content.segments_played)
          .replace('{{total}}', content.segments_total);
      } else {
        message = 'Audio output: ' + content.segments_played + '/' + content.segments_total + ' sentences played';
      }
      details = typeof webUIi18n !== 'undefined'
        ? webUIi18n.t('ui.tts.textTooLong')
        : '(Text too long for complete audio output)';
    } else if (content.notice_type === 'skipped') {
      message = typeof webUIi18n !== 'undefined'
        ? webUIi18n.t('ui.tts.skipped')
        : 'Audio output skipped';
      details = typeof webUIi18n !== 'undefined'
        ? webUIi18n.t('ui.tts.textExceedsLimit')
        : '(Text exceeds audio output limit)';
    } else if (content.notice_type === 'manual_play') {
      if (typeof webUIi18n !== 'undefined') {
        message = webUIi18n.t('ui.tts.manualPlay')
          .replace('{{total}}', content.segments_total);
      } else {
        message = 'Playing ' + content.segments_total + ' sentences';
      }
      details = typeof webUIi18n !== 'undefined'
        ? webUIi18n.t('ui.tts.useStopButton')
        : '(Use Stop button to cancel)';
    }

    let html = '<p class="mb-1">' + message + '</p>';
    if (details) {
      html += '<small class="text-muted">' + details + '</small>';
    }
    toastBody.innerHTML = html;

    const toast = new bootstrap.Toast(toastEl);
    toast.show();
  }

  function hideTtsToast() {
    const toastEl = document.getElementById('tts-toast');
    if (!toastEl || typeof bootstrap === 'undefined') return;

    const toast = bootstrap.Toast.getInstance(toastEl);
    if (toast) {
      toast.hide();
    }
  }

  // ── Suppression management ─────────────────────────────────────────

  function updateAutoSpeechSuppressedFlag() {
    autoSpeechSuppressed = autoSpeechSuppressionReasons.size > 0;
    window.autoSpeechSuppressed = autoSpeechSuppressed;
  }

  function setAutoSpeechSuppressed(value, options) {
    options = options || {};
    const reason = options.reason || 'general';
    const wasSuppressed = autoSpeechSuppressed;

    if (value) {
      autoSpeechSuppressionReasons.add(reason);
    } else if (options.reason) {
      autoSpeechSuppressionReasons.delete(reason);
    } else {
      autoSpeechSuppressionReasons.clear();
      if (typeof document !== 'undefined' && document.visibilityState === 'hidden') {
        autoSpeechSuppressionReasons.add('background_tab');
      }
    }

    updateAutoSpeechSuppressedFlag();

    if (autoSpeechSuppressed) {
      if (!wasSuppressed) {
        if (typeof ttsStop === 'function') {
          try {
            ttsStop();
          } catch (e) {
            console.warn('[Auto TTS] Failed to stop playback while suppressing:', e);
          }
        }
        if (typeof window.setTtsPlaybackStarted === 'function') {
          window.setTtsPlaybackStarted(false);
        }
        if (typeof window.autoTTSSpinnerTimeout !== 'undefined' && window.autoTTSSpinnerTimeout) {
          clearTimeout(window.autoTTSSpinnerTimeout);
          window.autoTTSSpinnerTimeout = null;
        }
        resetAutoSpeechSpinner();
        window.autoSpeechActive = false;
        window.autoPlayAudio = false;
      }
    }
  }

  function isAutoSpeechSuppressed() {
    return autoSpeechSuppressed;
  }

  // ── Foreground tab detection ───────────────────────────────────────

  function isForegroundTab() {
    return typeof document !== 'undefined' && document.visibilityState === 'visible';
  }

  // Register visibility-change listener for auto-suppression
  if (typeof document !== 'undefined' && typeof document.addEventListener === 'function') {
    document.addEventListener('visibilitychange', function() {
      if (document.visibilityState === 'visible') {
        setAutoSpeechSuppressed(false, { reason: 'background_tab', log: false });
      } else {
        setAutoSpeechSuppressed(true, { reason: 'background_tab', log: false });
      }
    }, { passive: true });
  }

  // ── Stop-button highlighting ───────────────────────────────────────

  // currentTTSCardId is shared mutable state
  let currentTTSCardId = null;

  function highlightStopButton(cardId) {
    if (cardId) {
      const card = document.getElementById(cardId);
      if (card) {
        const stopButton = card.querySelector('.func-stop');
        if (stopButton) stopButton.classList.add('tts-active');
        currentTTSCardId = cardId;
      }
    }
  }

  function removeStopButtonHighlight(cardId) {
    const targetCardId = cardId || currentTTSCardId;
    if (targetCardId) {
      const card = document.getElementById(targetCardId);
      if (card) {
        const stopButton = card.querySelector('.func-stop');
        if (stopButton) stopButton.classList.remove('tts-active');
      }
    }
    currentTTSCardId = null;
  }

  // ── Spinner helpers ────────────────────────────────────────────────

  function checkAndHideSpinner() {
    const spinnerEl = document.getElementById("monadic-spinner");
    if (!spinnerEl) return;
    const inForeground = typeof window.isForegroundTab === 'function' ? window.isForegroundTab() : true;

    const stillProcessing = window.streamingResponse === true || window.callingFunction === true ||
      (typeof window.isReasoningStreamActive === 'function' && window.isReasoningStreamActive());

    if (!inForeground) {
      if (stillProcessing) {
        return;
      }
      spinnerEl.style.display = 'none';
      return;
    }

    const messageCount = (window.messages && window.messages.length) || 0;
    if (messageCount === 0) {
      spinnerEl.style.display = 'none';
      return;
    }

    const paramsEnabled = window.params && (window.params["auto_speech"] === true || window.params["auto_speech"] === "true");
    const checkAutoSpeech = document.getElementById("check-auto-speech");
    const checkboxEnabled = checkAutoSpeech ? checkAutoSpeech.checked : false;
    const autoSpeechActiveFlag = window.autoSpeechActive === true;
    const autoSpeechEnabled = paramsEnabled || checkboxEnabled || autoSpeechActiveFlag;
    const reasoningActive = typeof window.isReasoningStreamActive === 'function' && window.isReasoningStreamActive();
    const streamingActive = window.streamingResponse === true;

    if (reasoningActive || streamingActive) {
      ensureThinkingSpinnerVisible();
      return;
    }

    if (!autoSpeechEnabled) {
      spinnerEl.style.display = 'none';
      return;
    }

    if (window._textResponseCompleted && window._ttsPlaybackStarted) {
      spinnerEl.style.display = 'none';
      const spanIcon = spinnerEl.querySelector("span i");
      if (spanIcon) {
        spanIcon.classList.remove("fa-headphones");
        spanIcon.classList.add("fa-comment");
      }
      const spanEl = spinnerEl.querySelector("span");
      if (spanEl) spanEl.innerHTML = '<i class="fas fa-comment fa-pulse"></i> Starting';
    }
  }

  // ── isSystemBusy ───────────────────────────────────────────────────

  function isSystemBusy() {
    const spinner = document.getElementById("monadic-spinner");
    const spinnerVisible = spinner ? (spinner.style.display !== 'none' && spinner.offsetParent !== null) : false;
    return spinnerVisible ||
           window.callingFunction ||
           window.streamingResponse;
  }

  // ── Thinking spinner ───────────────────────────────────────────────

  function ensureThinkingSpinnerVisible() {
    const thinkingText = typeof webUIi18n !== 'undefined'
      ? webUIi18n.t('ui.messages.spinnerThinking')
      : 'Thinking...';
    const spinner = document.getElementById("monadic-spinner");
    if (!spinner) return;
    const spanEl = spinner.querySelector("span");
    if (spanEl) spanEl.innerHTML = '<i class="fas fa-brain fa-pulse"></i> ' + thinkingText;
    if (spinner.style.display === 'none' || spinner.offsetParent === null) {
      spinner.style.display = '';
    }
  }

  function scheduleAutoTtsSpinnerTimeout() {
    if (window.autoTTSSpinnerTimeout) {
      clearTimeout(window.autoTTSSpinnerTimeout);
    }
    const evaluateTimeout = function() {
      if ((window.isReasoningStreamActive && window.isReasoningStreamActive()) || window.streamingResponse) {
        window.autoTTSSpinnerTimeout = setTimeout(evaluateTimeout, TTS_SPINNER_RECHECK_MS);
        return;
      }
      const timeoutSpinner = document.getElementById("monadic-spinner");
      if (timeoutSpinner && timeoutSpinner.style.display !== 'none' && timeoutSpinner.offsetParent !== null) {
        console.warn("[Auto TTS] Spinner timeout - forcing hide after delay");
        timeoutSpinner.style.display = 'none';
        const tsIcon = timeoutSpinner.querySelector("span i");
        if (tsIcon) {
          tsIcon.classList.remove("fa-headphones");
          tsIcon.classList.add("fa-comment");
        }
        const tsSpan = timeoutSpinner.querySelector("span");
        if (tsSpan) tsSpan.innerHTML = '<i class="fas fa-comment fa-pulse"></i> Starting';
        window.autoSpeechActive = false;
        window.autoPlayAudio = false;
      }
      window.autoTTSSpinnerTimeout = null;
    };
    window.autoTTSSpinnerTimeout = setTimeout(evaluateTimeout, TTS_SPINNER_TIMEOUT_MS);
  }

  // Deferred initial suppression check
  if (typeof window !== 'undefined' && typeof setTimeout === 'function') {
    setTimeout(function() {
      if (!isForegroundTab()) {
        setAutoSpeechSuppressed(true, { reason: 'background_tab', log: false });
        const deferredSpinner = document.getElementById('monadic-spinner');
        if (deferredSpinner) deferredSpinner.style.display = 'none';
      }
    }, 0);
  }

  // ── Namespace export ───────────────────────────────────────────────
  const ns = {
    resetAutoSpeechSpinner: resetAutoSpeechSpinner,
    showTtsNotice: showTtsNotice,
    hideTtsToast: hideTtsToast,
    setAutoSpeechSuppressed: setAutoSpeechSuppressed,
    isAutoSpeechSuppressed: isAutoSpeechSuppressed,
    isForegroundTab: isForegroundTab,
    highlightStopButton: highlightStopButton,
    removeStopButtonHighlight: removeStopButtonHighlight,
    checkAndHideSpinner: checkAndHideSpinner,
    isSystemBusy: isSystemBusy,
    ensureThinkingSpinnerVisible: ensureThinkingSpinnerVisible,
    scheduleAutoTtsSpinnerTimeout: scheduleAutoTtsSpinnerTimeout
  };

  window.WsAutoSpeech = ns;

  // Backward-compat individual exports
  window.setAutoSpeechSuppressed = setAutoSpeechSuppressed;
  window.isAutoSpeechSuppressed = isAutoSpeechSuppressed;
  window.isForegroundTab = isForegroundTab;
  window.highlightStopButton = highlightStopButton;
  window.removeStopButtonHighlight = removeStopButtonHighlight;
  window.checkAndHideSpinner = checkAndHideSpinner;
  window.hideTtsToast = hideTtsToast;
  window.isSystemBusy = isSystemBusy;
  window.showTtsNotice = showTtsNotice;
  window.ensureThinkingSpinnerVisible = ensureThinkingSpinnerVisible;
  window.scheduleAutoTtsSpinnerTimeout = scheduleAutoTtsSpinnerTimeout;

  // Support for Jest testing environment (CommonJS)
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = ns;
  }
})();
