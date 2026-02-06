/**
 * ws-auto-speech.js
 *
 * Auto-speech/TTS suppression, spinner control, and visibility helpers
 * extracted from websocket.js.
 */
(function() {
  "use strict";

  // ── Auto-speech suppression state ──────────────────────────────────
  var autoSpeechSuppressionReasons = new Set();
  var autoSpeechSuppressed = false;

  function resetAutoSpeechSpinner() {
    if (typeof $ === 'undefined') return;
    var $spinner = $("#monadic-spinner");
    $spinner.hide();
    $spinner.find("span i")
      .removeClass("fa-headphones")
      .addClass("fa-comment");
    $spinner.find("span")
      .html('<i class="fas fa-comment fa-pulse"></i> Starting');
  }

  // ── TTS Toast notice ───────────────────────────────────────────────

  function showTtsNotice(content) {
    if (typeof $ === 'undefined' || typeof bootstrap === 'undefined') return;

    var toastEl = document.getElementById('tts-toast');
    var toastBody = document.getElementById('tts-toast-body');
    if (!toastEl || !toastBody) return;

    var message = '';
    var details = '';

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

    var html = '<p class="mb-1">' + message + '</p>';
    if (details) {
      html += '<small class="text-muted">' + details + '</small>';
    }
    toastBody.innerHTML = html;

    var toast = new bootstrap.Toast(toastEl);
    toast.show();
  }

  function hideTtsToast() {
    var toastEl = document.getElementById('tts-toast');
    if (!toastEl || typeof bootstrap === 'undefined') return;

    var toast = bootstrap.Toast.getInstance(toastEl);
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
    var reason = options.reason || 'general';
    var wasSuppressed = autoSpeechSuppressed;

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
  var currentTTSCardId = null;

  function highlightStopButton(cardId) {
    if (cardId) {
      var $card = $('#' + cardId);
      if ($card.length) {
        var $stopButton = $card.find('.func-stop');
        $stopButton.addClass('tts-active');
        currentTTSCardId = cardId;
      }
    }
  }

  function removeStopButtonHighlight(cardId) {
    var targetCardId = cardId || currentTTSCardId;
    if (targetCardId) {
      var $card = $('#' + targetCardId);
      if ($card.length) {
        var $stopButton = $card.find('.func-stop');
        $stopButton.removeClass('tts-active');
      }
    }
    currentTTSCardId = null;
  }

  // ── Spinner helpers ────────────────────────────────────────────────

  function checkAndHideSpinner() {
    var inForeground = typeof window.isForegroundTab === 'function' ? window.isForegroundTab() : true;

    var stillProcessing = window.streamingResponse === true || window.callingFunction === true ||
      (typeof window.isReasoningStreamActive === 'function' && window.isReasoningStreamActive());

    if (!inForeground) {
      if (stillProcessing) {
        return;
      }
      $("#monadic-spinner").hide();
      return;
    }

    var messageCount = (window.messages && window.messages.length) || 0;
    if (messageCount === 0) {
      $("#monadic-spinner").hide();
      return;
    }

    var paramsEnabled = window.params && (window.params["auto_speech"] === true || window.params["auto_speech"] === "true");
    var checkboxEnabled = $("#check-auto-speech").is(":checked");
    var autoSpeechActiveFlag = window.autoSpeechActive === true;
    var autoSpeechEnabled = paramsEnabled || checkboxEnabled || autoSpeechActiveFlag;
    var reasoningActive = typeof window.isReasoningStreamActive === 'function' && window.isReasoningStreamActive();
    var streamingActive = window.streamingResponse === true;

    if (reasoningActive || streamingActive) {
      ensureThinkingSpinnerVisible();
      return;
    }

    if (!autoSpeechEnabled) {
      $("#monadic-spinner").hide();
      return;
    }

    if (window._textResponseCompleted && window._ttsPlaybackStarted) {
      $("#monadic-spinner").hide();
      $("#monadic-spinner")
        .find("span i")
        .removeClass("fa-headphones")
        .addClass("fa-comment");
      $("#monadic-spinner")
        .find("span")
        .html('<i class="fas fa-comment fa-pulse"></i> Starting');
    }
  }

  // ── isSystemBusy ───────────────────────────────────────────────────

  function isSystemBusy() {
    return $("#monadic-spinner").is(":visible") ||
           window.callingFunction ||
           window.streamingResponse;
  }

  // ── Thinking spinner ───────────────────────────────────────────────

  function ensureThinkingSpinnerVisible() {
    var thinkingText = typeof webUIi18n !== 'undefined'
      ? webUIi18n.t('ui.messages.spinnerThinking')
      : 'Thinking...';
    $("#monadic-spinner")
      .find("span")
      .html('<i class="fas fa-brain fa-pulse"></i> ' + thinkingText);
    if (!$("#monadic-spinner").is(":visible")) {
      $("#monadic-spinner").show();
    }
  }

  function scheduleAutoTtsSpinnerTimeout() {
    if (window.autoTTSSpinnerTimeout) {
      clearTimeout(window.autoTTSSpinnerTimeout);
    }
    var evaluateTimeout = function() {
      if ((window.isReasoningStreamActive && window.isReasoningStreamActive()) || window.streamingResponse) {
        window.autoTTSSpinnerTimeout = setTimeout(evaluateTimeout, 5000);
        return;
      }
      if ($("#monadic-spinner").is(":visible")) {
        console.warn("[Auto TTS] Spinner timeout - forcing hide after delay");
        $("#monadic-spinner").hide();
        $("#monadic-spinner")
          .find("span i")
          .removeClass("fa-headphones")
          .addClass("fa-comment");
        $("#monadic-spinner")
          .find("span")
          .html('<i class="fas fa-comment fa-pulse"></i> Starting');
        window.autoSpeechActive = false;
        window.autoPlayAudio = false;
      }
      window.autoTTSSpinnerTimeout = null;
    };
    window.autoTTSSpinnerTimeout = setTimeout(evaluateTimeout, 12000);
  }

  // Deferred initial suppression check
  if (typeof window !== 'undefined' && typeof setTimeout === 'function') {
    setTimeout(function() {
      if (!isForegroundTab()) {
        setAutoSpeechSuppressed(true, { reason: 'background_tab', log: false });
        if (typeof $ === 'function') {
          $('#monadic-spinner').hide();
        }
      }
    }, 0);
  }

  // ── Namespace export ───────────────────────────────────────────────
  var ns = {
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
