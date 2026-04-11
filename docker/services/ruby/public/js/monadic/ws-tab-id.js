/**
 * ws-tab-id.js
 *
 * Per-browser-tab identifier generation and persistence.
 * Extracted from websocket.js for modularity.
 *
 * Uses sessionStorage so the ID survives reloads of the same tab
 * but differs between tabs (unlike localStorage which would share).
 * Falls back to a time+random seed if sessionStorage/crypto is
 * unavailable. The ID is exported as window.monadicTabId and via
 * the getter window.getMonadicTabId for consumers that need to
 * re-resolve it after sessionStorage changes.
 */
(function() {
  'use strict';

  function ensureMonadicTabId() {
    try {
      if (typeof sessionStorage !== 'undefined') {
        var tabId = sessionStorage.getItem('monadicTabId');
        if (!tabId) {
          tabId = (typeof crypto !== 'undefined' && crypto.randomUUID) ?
            crypto.randomUUID() :
            'tab-' + Date.now() + '-' + Math.random().toString(36).slice(2);
          sessionStorage.setItem('monadicTabId', tabId);
        }
        window.monadicTabId = tabId;
        return tabId;
      }
    } catch (e) {
      console.warn('[Session] Unable to access sessionStorage for tab ID:', e);
    }
    if (!window.monadicTabId) {
      window.monadicTabId = 'tab-' + Date.now() + '-' + Math.random().toString(36).slice(2);
    }
    return window.monadicTabId;
  }

  // Back-compat export: websocket.js and other modules call this as a
  // function to re-resolve the ID on demand.
  window.getMonadicTabId = ensureMonadicTabId;

  window.WsTabId = {
    ensure: ensureMonadicTabId
  };

  // Support for Jest testing environment (CommonJS)
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = window.WsTabId;
  }
})();
