/**
 * Cookie Management Utilities for Monadic Chat
 *
 * Persist UI preferences (TTS provider, voice, ASR language) across sessions.
 * Falls back to sessionStorage when cookie access is restricted.
 *
 * Extracted from utilities.js for modularity.
 */
(function() {
'use strict';

/**
 * Set a cookie with optional expiry.
 * Falls back to sessionStorage on failure.
 * @param {string} name - Cookie name
 * @param {string} value - Cookie value
 * @param {number} days - Expiry in days
 */
function setCookie(name, value, days) {
  try {
    var date = new Date();
    date.setTime(date.getTime() + (days * 24 * 60 * 60 * 1000));
    var expires = "; expires=" + date.toUTCString();
    document.cookie = name + "=" + (value || "") + expires + "; path=/";
  } catch (err) {
    console.warn('Failed to set cookie "' + name + '":', err.message);
    if (typeof sessionStorage !== 'undefined') {
      try {
        sessionStorage.setItem("cookie_" + name, value || "");
      } catch (storageErr) {
        console.warn('Failed to set sessionStorage fallback for "' + name + '":', storageErr.message);
      }
    }
  }
}

/**
 * Get a cookie value by name.
 * Falls back to sessionStorage on failure.
 * @param {string} name - Cookie name
 * @returns {string|null} Cookie value or null
 */
function getCookie(name) {
  try {
    var nameEQ = name + "=";
    var ca = document.cookie.split(';');
    for (var i = 0; i < ca.length; i++) {
      var c = ca[i];
      while (c.charAt(0) == ' ') c = c.substring(1, c.length);
      if (c.indexOf(nameEQ) == 0) return c.substring(nameEQ.length, c.length);
    }
    return null;
  } catch (err) {
    console.warn('Failed to get cookie "' + name + '":', err.message);
    if (typeof sessionStorage !== 'undefined') {
      try {
        return sessionStorage.getItem("cookie_" + name);
      } catch (storageErr) {
        console.warn('Failed to get sessionStorage fallback for "' + name + '":', storageErr.message);
      }
    }
    return null;
  }
}

/**
 * Load cookie values and apply them to form elements.
 * Handles TTS provider, voice, speed, and ASR language settings.
 */
function setCookieValues() {
  var properties = ["tts-provider", "tts-voice", "elevenlabs-tts-voice", "mistral-tts-voice", "webspeech-voice", "tts-speed", "asr-lang"];
  properties.forEach(function(property) {
    var value = getCookie(property);
    var el = $id(property);
    if (value) {
      if (el && el.querySelector('option[value="' + value + '"]')) {
        el.value = value;
        $dispatch(el, "change");
      } else if (property === "elevenlabs-tts-voice") {
        // Handle when voices load later
      } else if (property === "webspeech-voice") {
        window.savedWebspeechVoice = value;
      }
    } else if (property === "tts-provider") {
      if (el) {
        el.value = "openai-tts-4o";
        $dispatch(el, "change");
      }
    }
  });
}

// Export for browser environment
window.setCookie = setCookie;
window.getCookie = getCookie;
window.setCookieValues = setCookieValues;

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { setCookie, getCookie, setCookieValues };
}
})();
