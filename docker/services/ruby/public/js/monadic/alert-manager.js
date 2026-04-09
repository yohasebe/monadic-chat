/**
 * Alert & Status Message Manager for Monadic Chat
 *
 * Manages UI status messages, error notifications, and error card lifecycle.
 * - setAlertClass: Apply Bootstrap alert color classes
 * - setAlert: Display status/error messages with cards for errors
 * - setStats: Update token stats display
 * - clearStatusMessage: Clear status text and classes
 * - clearErrorCards: Remove all error cards from discourse
 * - deleteMessage: Delete a message by ID and notify server
 *
 * Dependencies (runtime, via window.*):
 *   createCard, detachEventListeners (cards.js)
 *   ws, mids (websocket.js / cards.js)
 *   getTranslation (utilities.js)
 *   SessionState (session_state.js)
 *
 * Extracted from utilities.js for modularity.
 */
(function() {
'use strict';

/**
 * Apply Bootstrap alert color class to #status-message.
 * Maps "error" to "danger" for Bootstrap consistency.
 * @param {string} alertType - Alert type (success, warning, error, info, etc.)
 */
// Status message color map (must override Bootstrap @layer !important)
var STATUS_COLORS = {
  success:   '#1a8a4a',
  warning:   '#c47a00',
  danger:    '#c62828',
  info:      '#1565c0',
  secondary: '#546e7a'
};
var STATUS_COLORS_DARK = {
  success:   '#7fd89f',
  warning:   '#f59e0b',
  danger:    '#ef5350',
  info:      '#60a5fa',
  secondary: '#d0d0d0'
};

function setAlertClass(alertType) {
  if (alertType === undefined) alertType = "error";

  var el = $id('status-message');
  if (!el) return;

  // Remove all existing text-* classes
  var classes = el.className.match(/\btext-\S+/g);
  if (classes) {
    classes.forEach(function(cls) { el.classList.remove(cls); });
  }

  // Map error to danger for consistency with Bootstrap
  if (alertType === "error") {
    alertType = "danger";
  }

  // Validate status type if StatusConfig is available
  if (typeof window.StatusConfig !== 'undefined' && !window.StatusConfig.isValidStatusType(alertType)) {
    console.warn('[setAlertClass] Invalid status type: "' + alertType + '".');
    alertType = 'secondary';
  }

  el.classList.add("text-" + alertType);

  // Apply color via inline style with !important to override Bootstrap @layer
  var isDark = document.documentElement.classList.contains('dark-theme');
  var palette = isDark ? STATUS_COLORS_DARK : STATUS_COLORS;
  var color = palette[alertType] || palette.secondary;
  el.style.setProperty('color', color, 'important');
}

/**
 * Display a status message or create an error card.
 * For error type: creates a card with delete button.
 * For other types: updates #status-message with translated text.
 * @param {string|Object} text - Message text or object with content property
 * @param {string} alertType - Alert type (success, warning, error, info)
 */
function setAlert(text, alertType) {
  if (text === undefined) text = "";
  if (alertType === undefined) alertType = "success";

  if (alertType === "error") {
    var spinner = $id('monadic-spinner');
    $hide(spinner);

    var msg = text;
    if (text["content"]) {
      msg = text["content"];
    } else if (msg === "") {
      msg = "Something went wrong.";
    }

    // Create error card with system styling
    var errorCard = createCard("system",
      "<span class='text text-warning'><i class='fa-solid fa-bars'></i></span> <span class='fw-bold fs-6 system-color'>System</span>",
      msg);

    var errorCardEl = errorCard[0] || errorCard;
    if (errorCardEl && errorCardEl.classList) {
      errorCardEl.classList.add("error-message-card");
    }

    // Add delete button handler
    var deleteBtn = errorCardEl ? errorCardEl.querySelector(".func-delete") : null;
    if (deleteBtn) {
      deleteBtn.onclick = function(e) {
        e.stopPropagation();
        var tip = bootstrap.Tooltip.getInstance(this);
        if (tip) tip.hide();
        document.querySelectorAll('.tooltip').forEach(function(t) { t.remove(); });

        var card = this.closest(".card");
        var mid = card ? card.getAttribute("id") : null;

        if (card && typeof detachEventListeners === 'function') {
          detachEventListeners(card);
        }
        if (card) card.remove();

        if (mid) {
          ws.send(JSON.stringify({ "message": "DELETE", "mid": mid }));
          mids.delete(mid);
        }

        var statusMsg = $id('status-message');
        if (statusMsg) statusMsg.innerHTML = "<i class='fas fa-circle-check'></i> Error message removed";
        setAlertClass("success");
        return false;
      };
    }

    var editBtn = errorCardEl ? errorCardEl.querySelector(".func-edit") : null;
    if (editBtn) {
      editBtn.disabled = true;
      editBtn.style.opacity = "0.5";
    }

    var discourse = $id('discourse');
    if (discourse && errorCardEl) discourse.appendChild(errorCardEl);
  } else {
    // Translate known status messages
    var displayText = text;

    if (typeof text === 'string') {
      if (text.includes("CALLING FUNCTIONS")) {
        displayText = "<i class='fas fa-cogs'></i> " + getTranslation('ui.messages.spinnerCallingFunctions', 'Calling functions');
      } else if (text.includes("FUNCTION CALLS COMPLETE") || text.includes("FUNCTIONS COMPLETE")) {
        displayText = "<i class='fas fa-check'></i> " + getTranslation('ui.messages.functionsComplete', 'Functions complete');
      } else if (text.includes("SEARCHING WEB")) {
        displayText = "<i class='fas fa-search'></i> " + getTranslation('ui.messages.spinnerSearchingWeb', 'Searching web');
      } else if (text.includes("SEARCHING FILES")) {
        displayText = "<i class='fas fa-file-search'></i> " + getTranslation('ui.messages.spinnerSearchingFiles', 'Searching files');
      } else if (text.includes("GENERATING IMAGE")) {
        displayText = "<i class='fas fa-image'></i> " + getTranslation('ui.messages.spinnerGeneratingImage', 'Generating image');
      } else if (text.includes("CALLING MCP TOOL")) {
        displayText = "<i class='fas fa-plug'></i> " + getTranslation('ui.messages.spinnerCallingMCP', 'Calling MCP tool');
      } else if (text.includes("PROCESSING")) {
        displayText = "<i class='fas fa-spinner'></i> " + getTranslation('ui.messages.spinnerProcessing', 'Processing');
      } else if (text.includes("THINKING")) {
        displayText = "<i class='fas fa-brain'></i> " + getTranslation('ui.messages.spinnerThinking', 'Thinking');
      } else if (text === text.toUpperCase() && text.length > 10) {
        displayText = text.charAt(0) + text.slice(1).toLowerCase();
      }
    }

    var statusEl = $id('status-message');
    if (statusEl) statusEl.innerHTML = displayText;
    setAlertClass(alertType);

    // Bootstrap tooltip with full text
    var plainText = displayText.replace(/<[^>]*>/g, '');
    if (typeof bootstrap !== 'undefined' && bootstrap.Tooltip) {
      try {
        var existingTip = bootstrap.Tooltip.getInstance(statusEl);
        if (existingTip) existingTip.dispose();
        if (statusEl) statusEl.removeAttribute('title');
        new bootstrap.Tooltip(statusEl, {
          placement: 'bottom',
          trigger: 'hover',
          delay: { show: 500, hide: 100 },
          title: plainText
        });
      } catch (e) {
        if (statusEl) statusEl.removeAttribute('title');
        try {
          new bootstrap.Tooltip(statusEl, {
            placement: 'bottom',
            trigger: 'hover',
            delay: { show: 500, hide: 100 },
            title: plainText
          });
        } catch (e2) { /* ignore */ }
      }
    }
  }
}

/**
 * Update the stats message display.
 * @param {string} text - Stats HTML content
 */
function setStats(text) {
  if (text === undefined) text = "";
  var el = $id('stats-message');
  if (el) el.innerHTML = text;
}

/**
 * Clear status message text and remove all status type classes.
 */
function clearStatusMessage() {
  var el = $id('status-message');
  if (!el) return;
  el.innerHTML = "";
  var classes = el.className.match(/\btext-\S+/g);
  if (classes) {
    classes.forEach(function(cls) { el.classList.remove(cls); });
  }
}

/**
 * Remove all error cards from the discourse area.
 * Cleans up event listeners and notifies server.
 */
function clearErrorCards() {
  document.querySelectorAll(".error-message-card").forEach(function(card) {
    var mid = card.getAttribute("id");
    if (typeof detachEventListeners === 'function') {
      detachEventListeners(card);
    }
    if (mid) {
      ws.send(JSON.stringify({ "message": "DELETE", "mid": mid }));
      mids.delete(mid);
    }
    card.remove();
  });
}

/**
 * Delete a message by ID, clean up DOM, and notify server.
 * @param {string} mid - Message ID
 */
function deleteMessage(mid) {
  var card = $id(mid);
  if (card && typeof detachEventListeners === 'function') {
    detachEventListeners(card);
  }
  if (card) card.remove();
  var index = messages.findIndex(function(m) { return m.mid === mid; });

  if (index !== -1) {
    window.SessionState.removeMessage(index);
    ws.send(JSON.stringify({ "message": "DELETE", "mid": mid }));
    mids.delete(mid);
  }
}

// Export for browser environment
window.setAlert = setAlert;
window.setStats = setStats;
window.clearStatusMessage = clearStatusMessage;
window.clearErrorCards = clearErrorCards;
window.deleteMessage = deleteMessage;

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    setAlertClass,
    setAlert,
    setStats,
    clearStatusMessage,
    clearErrorCards,
    deleteMessage
  };
}
})();
