/**
 * WebSocket Session Handler for Monadic Chat
 *
 * Handles session-level WebSocket messages that don't involve
 * streaming state or audio playback:
 * - language_updated: Conversation language changes with RTL support
 * - processing_status / system_info: System message display
 * - stt: Speech-to-text completion
 * - change_status: Message active/inactive status toggle
 * - success: Generic success notifications
 * - sample_success: Sample message addition confirmation
 *
 * Extracted from websocket.js to reduce the size of connect_websocket().
 */
(function() {
'use strict';

/**
 * Handle "language_updated" WebSocket message.
 * Updates language selector and toggles RTL/LTR body class.
 * @param {Object} data - Message data with language, language_name, text_direction
 */
function handleLanguageUpdated(data) {
  const languageName = data.language_name || data.language;
  const languageChangedText = typeof webUIi18n !== 'undefined' ?
    webUIi18n.t('ui.messages.languageChanged') : 'Language changed to';
  setAlert(`<i class='fa-solid fa-globe'></i> ${languageChangedText} ${languageName}`, "success");

  var langSelect = $id('conversation-language');
  if (data.language && langSelect && langSelect.value !== data.language) {
    langSelect.value = data.language;
  }

  if (data.text_direction) {
    if (data.text_direction === "rtl") {
      document.body.classList.add("rtl-messages");
      if (window.debugWebSocket) console.log("RTL messages enabled for:", data.language);
    } else {
      document.body.classList.remove("rtl-messages");
      if (window.debugWebSocket) console.log("LTR messages enabled for:", data.language);
    }
  }
}

/**
 * Handle "processing_status" WebSocket message.
 * Displays a processing status alert and system message card.
 * @param {Object} data - Message data with content string
 */
function handleProcessingStatus(data) {
  setAlert(`<i class='fas fa-hourglass-half'></i> ${data.content}`, "info");

  var spinner = $id('monadic-spinner');
  if (spinner && spinner.style.display === 'none') {
    $show(spinner);
  }

  var systemDiv = document.createElement('div');
  systemDiv.className = 'system-info-message';
  systemDiv.innerHTML = '<i class="fas fa-hourglass-half"></i> ';
  var contentText = typeof data.content === 'object' ? JSON.stringify(data.content) : data.content;
  var span = document.createElement('span');
  span.textContent = contentText;
  systemDiv.appendChild(span);

  var systemElement = createCard("system",
    "<span class='text-success'><i class='fas fa-database'></i></span> <span class='fw-bold fs-6 text-success'>System</span>",
    systemDiv.outerHTML,
    "en",
    null,
    true,
    []
  );
  var discourse = $id('discourse');
  var sysEl = systemElement[0] || systemElement;
  if (discourse && sysEl) discourse.appendChild(sysEl);
  if (window.MarkdownRenderer) {
    window.MarkdownRenderer.applyRenderers(sysEl);
  }

  if (window.autoScroll) {
    const chatBottom = $id('chat-bottom');
    if (chatBottom && !isElementInViewport(chatBottom)) {
      chatBottom.scrollIntoView(false);
    }
  }
}

/**
 * Handle "system_info" WebSocket message.
 * Displays system information as a card in the conversation.
 * @param {Object} data - Message data with content string or object
 */
function handleSystemInfo(data) {
  var systemDiv = document.createElement('div');
  systemDiv.className = 'system-info-message';
  systemDiv.innerHTML = '<i class="fas fa-info-circle"></i> ';
  var contentText = typeof data.content === 'object' ? JSON.stringify(data.content) : data.content;
  var span = document.createElement('span');
  span.textContent = contentText;
  systemDiv.appendChild(span);

  var systemElement = createCard("system",
    "<span class='text-success'><i class='fas fa-database'></i></span> <span class='fw-bold fs-6 text-success'>System</span>",
    systemDiv.outerHTML,
    "en",
    null,
    true,
    []
  );
  var discourse = $id('discourse');
  var sysEl = systemElement[0] || systemElement;
  if (discourse && sysEl) discourse.appendChild(sysEl);
  if (window.MarkdownRenderer) {
    window.MarkdownRenderer.applyRenderers(sysEl);
  }

  if (window.autoScroll) {
    const chatBottom = $id('chat-bottom');
    if (chatBottom && !isElementInViewport(chatBottom)) {
      chatBottom.scrollIntoView(false);
    }
  }
}

// Scroll sync between #message and the partial overlay.
//
// Partial-update sync alone (the `overlay.scrollTop = messageEl.scrollTop`
// line at the end of handleSTTPartial) only catches deltas — if the user
// manually scrolls the textarea between deltas (or during a long pause),
// the overlay falls out of sync until the next partial arrives. With
// resize handles enlarging #message to a scrollable height the symptom
// becomes visible. Attaching a 'scroll' listener while the overlay is
// active keeps them in lockstep. Detached when the overlay clears so we
// don't pay listener overhead during normal typing.
let sttScrollSyncAttached = false;

function syncOverlayScrollTopFromMessage() {
  const messageEl = $id('message');
  const overlay = $id('message-partial-overlay');
  if (messageEl && overlay) overlay.scrollTop = messageEl.scrollTop;
}

function attachSTTScrollSync() {
  if (sttScrollSyncAttached) return;
  const messageEl = $id('message');
  if (!messageEl) return;
  messageEl.addEventListener('scroll', syncOverlayScrollTopFromMessage);
  sttScrollSyncAttached = true;
}

function detachSTTScrollSync() {
  if (!sttScrollSyncAttached) return;
  const messageEl = $id('message');
  if (messageEl) messageEl.removeEventListener('scroll', syncOverlayScrollTopFromMessage);
  sttScrollSyncAttached = false;
}

/**
 * Handle "stt_partial" WebSocket message (Realtime streaming STT).
 * Renders the cumulative provisional transcript into the ghost-text
 * overlay sibling of #message — does NOT touch messageEl.value, so the
 * user can keep typing in the textarea while partials stream in.
 * @param {Object} data - { content: "<accumulated partial transcript>" }
 */
function handleSTTPartial(data) {
  const messageEl = $id('message');
  const overlay = $id('message-partial-overlay');
  if (!messageEl || !overlay) return;
  const partial = (data && typeof data.content === 'string') ? data.content : '';

  const existing = messageEl.value;
  const sep = (existing.length > 0 && !/\s$/.test(existing)) ? ' ' : '';

  overlay.replaceChildren();
  const mirror = document.createElement('span');
  mirror.className = 'stt-mirror';
  mirror.textContent = existing + sep;
  const partialSpan = document.createElement('span');
  partialSpan.className = 'stt-partial';
  partialSpan.textContent = partial;
  overlay.appendChild(mirror);
  overlay.appendChild(partialSpan);
  overlay.classList.add('is-active');
  // Mirror to wrapper for browsers without :has() support — the CSS rule
  // that hides the placeholder is :has()-based for modern engines and
  // .has-partial-overlay-class-based for fallback. See monadic.css.
  const wrapper = overlay.closest('.message-input-wrapper');
  if (wrapper) wrapper.classList.add('has-partial-overlay');
  overlay.scrollTop = messageEl.scrollTop;
  attachSTTScrollSync();
}

/**
 * Clear the realtime STT overlay. Called from the recording lifecycle
 * (start / commit / abort / silence). Exposed via window for use by
 * non-bundled callers.
 */
function clearSTTPartialOverlay() {
  detachSTTScrollSync();
  const overlay = $id('message-partial-overlay');
  if (!overlay) return;
  overlay.replaceChildren();
  overlay.classList.remove('is-active');
  const wrapper = overlay.closest('.message-input-wrapper');
  if (wrapper) wrapper.classList.remove('has-partial-overlay');
}

/**
 * Handle "stt" WebSocket message.
 * Processes speech-to-text completion with optional auto-submit.
 * @param {Object} data - Message data with content string and logprob
 */
function handleSTT(data) {
  // Realtime streaming committed: append the final transcript to
  // messageEl.value (preserving any text the user typed during the
  // partial stream) and tear down the overlay. The overlay being
  // active is what tells us streaming was in progress.
  let partialConsumed = false;
  const messageElRT = $id('message');
  const overlayRT = $id('message-partial-overlay');
  if (messageElRT && overlayRT && overlayRT.classList.contains('is-active')) {
    // In a speech-to-speech session the transcript is display feedback, not
    // input: the server has already taken the turn, so the text must not
    // land in the textarea (it would invite a duplicate submission through
    // the ordinary pipeline). partialConsumed is still set so the delegate
    // does not append it either.
    const stsModeRT = !!(window.SttGate && typeof window.SttGate.isStsModelSelected === 'function'
      && window.SttGate.isStsModelSelected());
    if (!stsModeRT) {
      const finalText = (data && typeof data.content === 'string') ? data.content : '';
      const existing = messageElRT.value;
      const sep = (existing.length > 0 && !/\s$/.test(existing)) ? ' ' : '';
      messageElRT.value = existing + sep + finalText;
    }
    partialConsumed = true;
    clearSTTPartialOverlay();
  }

  // Use the handler if available, otherwise use inline code.
  // When the realtime path already appended the final transcript to
  // the textarea above, signal that via `_alreadyAppended` so the
  // delegate skips its own append (otherwise the message ends up in
  // the value twice). The delegate still does the rest of its work
  // — re-enable buttons, hide spinner, easy-submit, etc.
  let handled = false;
  if (typeof wsHandlers !== 'undefined' && wsHandlers && typeof wsHandlers.handleSTTMessage === 'function') {
    const dataForHandler = partialConsumed
      ? Object.assign({}, data, { _alreadyAppended: true })
      : data;
    handled = wsHandlers.handleSTTMessage(dataForHandler);
  }

  if (!handled) {
    var messageEl = $id('message');
    if (messageEl && !partialConsumed) messageEl.value = messageEl.value + " " + data["content"];

    var asrEl = $id('asr-p-value');
    if (data["logprob"] != null) {
      if (asrEl) { asrEl.textContent = "Last Speech-to-Text p-value: " + data["logprob"]; $show(asrEl); }
    } else {
      if (asrEl) { asrEl.textContent = ""; $hide(asrEl); }
    }

    ['send', 'clear', 'voice'].forEach(function(id) {
      var el = $id(id);
      if (el) el.disabled = false;
    });

    if (messageEl) {
      var origPlaceholder = messageEl.dataset.originalPlaceholder || (typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messagePlaceholder') : "Type your message or click Speech Input button to use voice . . .");
      messageEl.setAttribute("placeholder", origPlaceholder);
    }

    var amplitudeEl = $id('amplitude');
    $hide(amplitudeEl);

    var easySubmit = $id('check-easy-submit');
    if (easySubmit && easySubmit.checked) {
      if (typeof window.isForegroundTab === 'function' && !window.isForegroundTab()) {
        if (window.debugWebSocket) console.log('[Send] Ignoring auto-submit: tab is not foreground');
      } else {
        var sendBtn = $id('send');
        if (sendBtn) sendBtn.click();
      }
    }
    const voiceFinishedText = getTranslation('ui.messages.voiceRecognitionFinished', 'Voice recognition finished');
    setAlert(`<i class='fa-solid fa-circle-check'></i> ${voiceFinishedText}`, "secondary");
    setInputFocus();
  }
}

/**
 * Handle "change_status" WebSocket message.
 * Toggles active/inactive class on message cards.
 * @param {Object} data - Message data with content array of {mid, active} objects
 */
function handleChangeStatus(data) {
  data["content"].forEach((msg) => {
    const card = $id(msg["mid"]);
    if (card) {
      var statusEl = card.querySelector(".status");
      if (statusEl) {
        if (msg["active"]) {
          statusEl.classList.add("active");
        } else {
          statusEl.classList.remove("active");
        }
      }
    }
  });
}

/**
 * Handle "success" WebSocket message.
 * Displays a generic success alert.
 * @param {Object} data - Message data with content string
 */
function handleSuccess(data) {
  setAlert(`<i class='fa-solid fa-circle-check'></i> ${data.content}`, "success");
}

/**
 * Handle "sample_success" WebSocket message.
 * Confirms sample message addition with UI cleanup.
 * @param {Object} data - Message data with role string
 */
function handleSampleSuccess(data) {
  // Use the handler if available, otherwise use inline code
  let handled = false;
  if (typeof wsHandlers !== 'undefined' && wsHandlers && typeof wsHandlers.handleSampleSuccess === 'function') {
    handled = wsHandlers.handleSampleSuccess(data);
  }

  if (!handled) {
    if (window.currentSampleTimeout) {
      clearTimeout(window.currentSampleTimeout);
      window.currentSampleTimeout = null;
    }

    var spinner = $id('monadic-spinner');
    $hide(spinner);
    $id('cancel_query').style.setProperty('display', 'none', 'important');

    const sampleAddedText = getTranslation('ui.messages.sampleMessageAdded', 'Sample message added');
    setAlert(`<i class='fas fa-check-circle'></i> ${sampleAddedText}`, "success");
  }
}

// Export for browser environment
window.WsSessionHandler = {
  handleLanguageUpdated,
  handleProcessingStatus,
  handleSystemInfo,
  handleSTT,
  handleSTTPartial,
  clearSTTPartialOverlay,
  handleChangeStatus,
  handleSuccess,
  handleSampleSuccess
};

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = window.WsSessionHandler;
}
})();
