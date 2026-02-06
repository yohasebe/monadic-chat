/**
 * ws-audio-constants.js
 *
 * Browser/feature detection and audio-related constants extracted from websocket.js.
 * Loaded before all other ws-* modules so constants are available globally.
 */
(function() {
  "use strict";

  // ── Browser detection ──────────────────────────────────────────────
  var isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent);
  var isIPad = /iPad/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  var isMobileIOS = isIOS && !isIPad;
  var isChrome = /Chrome/.test(navigator.userAgent) && !/Edge/.test(navigator.userAgent);
  var isSafari = /Safari/.test(navigator.userAgent) && !/Chrome/.test(navigator.userAgent);
  var isFirefox = /Firefox/.test(navigator.userAgent);

  // ── Feature detection ──────────────────────────────────────────────
  var hasMediaSourceSupport = typeof MediaSource !== 'undefined';
  var hasAudioContextSupport = typeof (window.AudioContext || window.webkitAudioContext) !== 'undefined';

  // ── Audio queue constants ──────────────────────────────────────────
  var AUDIO_QUEUE_DELAY = window.AUDIO_QUEUE_DELAY || 20;
  var AUDIO_ERROR_DELAY = window.AUDIO_ERROR_DELAY || 50;
  var MAX_AUDIO_QUEUE_SIZE = 50;

  // ── Sequence-based ordering constants ──────────────────────────────
  var SEQUENCE_TIMEOUT_MS = 3000;
  var MAX_SEQUENCE_RETRIES = 10;

  // ── Reconnect constants ────────────────────────────────────────────
  var maxReconnectAttempts = 5;
  var baseReconnectDelay = 1000;

  // ── WebSocket timing constants ────────────────────────────────────
  var PING_INTERVAL_MS = 30000;
  var TOKEN_VERIFY_TIMEOUT_MS = 30000;
  var VERIFY_CHECK_INTERVAL_MS = 1000;
  var RESPONSE_TIMEOUT_MS = 30000;
  var RESPONSE_TIMEOUT_SLOW_MS = 60000;
  var BUSY_CHECK_INTERVAL_MS = 500;
  var BUSY_CHECK_MAX_WAIT_MS = 10000;

  // ── Auto-speech timing constants ──────────────────────────────────
  var TTS_SPINNER_RECHECK_MS = 5000;
  var TTS_SPINNER_TIMEOUT_MS = 12000;

  // ── Namespace export ───────────────────────────────────────────────
  var ns = {
    isIOS: isIOS,
    isIPad: isIPad,
    isMobileIOS: isMobileIOS,
    isChrome: isChrome,
    isSafari: isSafari,
    isFirefox: isFirefox,
    hasMediaSourceSupport: hasMediaSourceSupport,
    hasAudioContextSupport: hasAudioContextSupport,
    AUDIO_QUEUE_DELAY: AUDIO_QUEUE_DELAY,
    AUDIO_ERROR_DELAY: AUDIO_ERROR_DELAY,
    MAX_AUDIO_QUEUE_SIZE: MAX_AUDIO_QUEUE_SIZE,
    SEQUENCE_TIMEOUT_MS: SEQUENCE_TIMEOUT_MS,
    MAX_SEQUENCE_RETRIES: MAX_SEQUENCE_RETRIES,
    maxReconnectAttempts: maxReconnectAttempts,
    baseReconnectDelay: baseReconnectDelay,
    PING_INTERVAL_MS: PING_INTERVAL_MS,
    TOKEN_VERIFY_TIMEOUT_MS: TOKEN_VERIFY_TIMEOUT_MS,
    VERIFY_CHECK_INTERVAL_MS: VERIFY_CHECK_INTERVAL_MS,
    RESPONSE_TIMEOUT_MS: RESPONSE_TIMEOUT_MS,
    RESPONSE_TIMEOUT_SLOW_MS: RESPONSE_TIMEOUT_SLOW_MS,
    BUSY_CHECK_INTERVAL_MS: BUSY_CHECK_INTERVAL_MS,
    BUSY_CHECK_MAX_WAIT_MS: BUSY_CHECK_MAX_WAIT_MS,
    TTS_SPINNER_RECHECK_MS: TTS_SPINNER_RECHECK_MS,
    TTS_SPINNER_TIMEOUT_MS: TTS_SPINNER_TIMEOUT_MS
  };

  window.WsAudioConstants = ns;

  // Backward-compat individual exports
  window.isIOS = isIOS;
  window.isIPad = isIPad;
  window.isMobileIOS = isMobileIOS;
  window.isChrome = isChrome;
  window.isSafari = isSafari;
  window.isFirefox = isFirefox;

  // Support for Jest testing environment (CommonJS)
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = ns;
  }
})();
