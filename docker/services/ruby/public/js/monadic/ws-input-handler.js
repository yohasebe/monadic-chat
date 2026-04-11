/**
 * ws-input-handler.js
 *
 * Message-box IME tracking and Easy Submit keyboard shortcuts.
 * Extracted from websocket.js for modularity.
 *
 * Registers listeners on window load so the #message element is
 * guaranteed to exist. Handles:
 *   - compositionstart / compositionend to flag IME state on #message
 *   - Right Arrow to activate voice input when Easy Submit is on
 *   - Enter to submit when focus is outside the textarea and IME is idle
 */
(function() {
  'use strict';

  function init() {
    var message = $id('message');
    if (!message) return;

    message.addEventListener('compositionstart', function() {
      message.dataset.ime = 'true';
    });

    message.addEventListener('compositionend', function() {
      message.dataset.ime = 'false';
    });

    document.addEventListener('keydown', function(event) {
      var easySubmitEl = $id('check-easy-submit');
      var messageEl = $id('message');
      var easySubmitChecked = easySubmitEl && easySubmitEl.checked;
      var messageHasFocus = document.activeElement === messageEl;

      // Right Arrow — activate voice input while the session is running
      if (easySubmitChecked && !messageHasFocus && event.key === 'ArrowRight') {
        event.preventDefault();
        var voiceEl = $id('voice');
        var mainPanelEl = $id('main-panel');
        if (voiceEl && !voiceEl.disabled && mainPanelEl && mainPanelEl.style.display !== 'none') {
          voiceEl.click();
        }
      }

      // Enter — submit message when focus is not in the textarea
      if (easySubmitChecked && !messageHasFocus && event.key === 'Enter' && message.dataset.ime !== 'true') {
        if (message.value.trim() !== '') {
          event.preventDefault();
          if (typeof window.isForegroundTab === 'function' && !window.isForegroundTab()) {
            // Ignore auto-submit when tab is not in foreground
          } else {
            var sendEl = $id('send');
            if (sendEl) sendEl.click();
          }
        }
      }
    });
  }

  // Initialize after DOM is ready. websocket.js runs after DOMContentLoaded
  // via the bundle, but the load event is late enough that calling init()
  // synchronously inside the IIFE is safe here because $id('message')
  // exists by the time the bundle executes (scripts are at the bottom of
  // index.erb). Use a defensive DOM-ready fallback for safety.
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  window.WsInputHandler = {
    init: init
  };

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = window.WsInputHandler;
  }
})();
