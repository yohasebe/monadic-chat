/**
 * WebSocket Streaming Handler for Monadic Chat
 *
 * Handles streaming lifecycle messages:
 * - streaming_complete: Reset streaming state, hide spinner, show ready status
 *
 * Extracted from websocket.js to reduce the size of connect_websocket().
 */
(function() {
'use strict';

var BUSY_CHECK_INTERVAL_MS = (typeof window !== 'undefined' && window.WsAudioConstants || {}).BUSY_CHECK_INTERVAL_MS || 500;
var BUSY_CHECK_MAX_WAIT_MS = (typeof window !== 'undefined' && window.WsAudioConstants || {}).BUSY_CHECK_MAX_WAIT_MS || 10000;

/**
 * Handle "streaming_complete" WebSocket message.
 * Resets streaming state, manages spinner visibility based on Auto Speech,
 * and shows "Ready for input" status with busy-check retry logic.
 * @param {Object} _data - Message data (unused)
 */
function handleStreamingComplete(_data) {
  // Reset streaming state
  window.streamingResponse = false;
  if (window.UIState) {
    window.UIState.set('streamingResponse', false);
    window.UIState.set('isStreaming', false);
  }

  // Clear any pending spinner check interval
  if (window.spinnerCheckInterval) {
    clearInterval(window.spinnerCheckInterval);
    window.spinnerCheckInterval = null;
  }

  // Hide spinner unless we're calling functions or streaming
  if (!window.callingFunction && !window.streamingResponse) {
    // Mark text response as completed
    if (typeof window.setTextResponseCompleted === 'function') {
      window.setTextResponseCompleted(true);
    }

    // Check foreground state
    const inForeground = typeof window.isForegroundTab === 'function' ? window.isForegroundTab() : true;

    // Check Auto Speech from multiple sources
    const paramsEnabled = window.params && (window.params["auto_speech"] === true || window.params["auto_speech"] === "true");
    const checkAutoSpeechEl = $id("check-auto-speech");
    const checkboxEnabled = checkAutoSpeechEl ? checkAutoSpeechEl.checked : false;
    const autoSpeechActive = window.autoSpeechActive === true;
    const autoSpeechEnabled = paramsEnabled || checkboxEnabled || autoSpeechActive;

    if (autoSpeechEnabled && !window.ttsPlaybackStarted && inForeground) {
      // Auto Speech enabled, TTS not started yet, and tab is foreground
      // Server will send audio directly
      if (window.debugWebSocket) console.log('[streaming_complete] Auto Speech enabled - server will send audio');
    } else {
      // Check if we can hide spinner
      if (typeof window.checkAndHideSpinner === 'function') {
        window.checkAndHideSpinner();
      } else {
        const scFallbackSpinner = $id("monadic-spinner");
        $hide(scFallbackSpinner);
      }
    }
  }

  // Check if system is busy before showing "Ready for input"
  setTimeout(function() {
    if (!isSystemBusy()) {
      const readyText = typeof webUIi18n !== 'undefined' ?
        webUIi18n.t('ui.messages.readyForInput') : 'Ready for input';
      setAlert(`<i class='fa-solid fa-circle-check'></i> ${readyText}`, "success");
    } else {
      // If system is still busy, wait and check again
      let checkInterval = setInterval(function() {
        if (!isSystemBusy()) {
          clearInterval(checkInterval);
          const readyText = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.readyForInput') : 'Ready for input';
          setAlert(`<i class='fa-solid fa-circle-check'></i> ${readyText}`, "success");
        }
      }, BUSY_CHECK_INTERVAL_MS);

      // Safety timeout to prevent infinite checking
      setTimeout(function() {
        clearInterval(checkInterval);
        const readyText = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.readyForInput') : 'Ready for input';
        setAlert(`<i class='fa-solid fa-circle-check'></i> ${readyText}`, "success");
      }, BUSY_CHECK_MAX_WAIT_MS);
    }

    // Always ensure UI elements are enabled and visible (user-panel may be hidden during initiate_from_assistant)
    const scUserPanel = $id("user-panel");
    $show(scUserPanel);
    ["message", "send", "clear", "image-file", "voice", "doc", "url", "pdf-import", "select-role"].forEach(function(id) {
      const el = $id(id);
      if (el) el.disabled = false;
    });

    // Focus on the message input
    setInputFocus();

    // Reset sequence tracking for next message (realtime TTS)
    if (typeof window.resetSequenceTracking === 'function') {
      window.resetSequenceTracking();
    }
  }, 250);
}

/**
 * Handle default/fragment WebSocket messages.
 * Processes both structured "fragment" type messages and legacy untyped messages.
 * Updates streaming state, manages spinner, and delegates to fragment handler.
 * @param {Object} data - Message data with type and content
 */
function handleDefaultMessage(data) {
  if (data.type === "fragment") {
    // Handle fragment messages from all vendors
    if (!window.responseStarted) {
      const respondingText = typeof webUIi18n !== 'undefined' ?
        webUIi18n.t('ui.messages.responding') : 'RESPONDING';
      setAlert(`<i class='fas fa-pencil-alt'></i> ${respondingText}`, "warning");
      window.responseStarted = true;
      window.streamingResponse = true;
      if (window.UIState) {
        window.UIState.set('streamingResponse', true);
        window.UIState.set('isStreaming', true);
      }
      if (typeof WorkflowViewer !== 'undefined' && WorkflowViewer.setStage) {
        WorkflowViewer.setStage('response');
      }
    }

    // Always update spinner for fragments
    if (window.streamingResponse) {
      const receivingResponseText = typeof webUIi18n !== 'undefined' ?
        webUIi18n.t('ui.messages.spinnerReceivingResponse') : 'Receiving response';
      const fragSpinner = $id("monadic-spinner");
      if (fragSpinner) {
        const fragSpan = fragSpinner.querySelector("span");
        if (fragSpan) fragSpan.innerHTML = `<i class="fa-solid fa-circle-nodes fa-pulse"></i> ${receivingResponseText}`;
        $show(fragSpinner);
      }
    }

    // Use the dedicated fragment handler
    if (typeof window.handleFragmentMessage === 'function') {
      window.handleFragmentMessage(data);
    }

    const fragIndicator = $id("indicator");
    $show(fragIndicator);
    if (window.autoScroll && window.chatBottom && typeof isElementInViewport === 'function' && !isElementInViewport(window.chatBottom)) {
      window.chatBottom.scrollIntoView(false);
    }
  } else {
    // Handle other default messages (backward compatibility)
    let content = data["content"];
    if (!window.responseStarted || window.callingFunction) {
      const respondingText = typeof webUIi18n !== 'undefined' ?
        webUIi18n.t('ui.messages.responding') : 'RESPONDING';
      setAlert(`<i class='fas fa-pencil-alt'></i> ${respondingText}`, "warning");
      window.callingFunction = false;
      window.responseStarted = true;
      window.streamingResponse = true;
      if (window.UIState) {
        window.UIState.set('streamingResponse', true);
        window.UIState.set('isStreaming', true);
      }
      const receivingResponseText2 = typeof webUIi18n !== 'undefined' ?
        webUIi18n.t('ui.messages.spinnerReceivingResponse') : 'Receiving response';
      const legacySpinner = $id("monadic-spinner");
      if (legacySpinner) {
        const legacySpan = legacySpinner.querySelector("span");
        if (legacySpan) legacySpan.innerHTML = `<i class="fa-solid fa-circle-nodes fa-pulse"></i> ${receivingResponseText2}`;
        $show(legacySpinner);
      }
    }
    const legacyIndicator = $id("indicator");
    $show(legacyIndicator);
    if (content !== undefined) {
      content = content.replace(/^\n+/, "");
      const chatEl = $id("chat");
      if (chatEl) chatEl.innerHTML = chatEl.innerHTML + content.replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\n/g, "<br>");
    }
    if (window.autoScroll && window.chatBottom && typeof isElementInViewport === 'function' && !isElementInViewport(window.chatBottom)) {
      window.chatBottom.scrollIntoView(false);
    }
  }
}

/**
 * Handle "user" WebSocket message.
 * Creates the user message card, sets up temp card for assistant response,
 * and initializes streaming state for the upcoming response.
 * @param {Object} data - Message data with content (text, html, mid, images, lang)
 */
function handleUser(data) {
  const messages = window.messages || [];
  const importInProgress = (typeof window !== 'undefined') && window.isImporting;

  if (typeof isAutoSpeechSuppressed === 'function' && isAutoSpeechSuppressed() && !importInProgress) {
    if (typeof setAutoSpeechSuppressed === 'function') {
      setAutoSpeechSuppressed(false, { log: false });
    }
  }
  if (typeof window !== 'undefined') {
    window.skipAssistantInitiation = false;
    window.isProcessingImport = false;
  }

  // Check if we have a temporary message to remove first
  const tempMessageIndex = messages.findIndex(msg => msg.temp === true);
  if (tempMessageIndex !== -1) {
    window.SessionState.removeMessage(tempMessageIndex);
  }

  // Create the proper message object
  let message_obj = { "role": "user", "text": data["content"]["text"], "html": data["content"]["html"], "mid": data["content"]["mid"] };
  if (data["content"]["images"] !== undefined) {
    message_obj.images = data["content"]["images"];
  }
  window.SessionState.addMessage(message_obj);

  // Format content for display
  let content_text = (data["content"]["text"] || "").trim().replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\n/g, "<br>").replace(/\s/g, " ");
  let images;
  if (data["content"]["images"] !== undefined) {
    images = data["content"]["images"];
  }

  // Use appendCard helper to show the user message
  const userDiscourse = $id('discourse');
  const userTurnNumber = userDiscourse ? userDiscourse.querySelectorAll('.card:not(#temp-card) .role-assistant').length + 1 : 1;
  if (typeof window.appendCard === 'function') {
    window.appendCard("user", "<span class='text-secondary'><i class='fas fa-face-smile'></i></span> <span class='fw-bold fs-6 user-color'>User</span>", "<p>" + content_text + "</p>", data["content"]["lang"], data["content"]["mid"], true, images, userTurnNumber);
  }

  // Scroll down immediately after showing user message
  const mainPanel = window.mainPanel;
  if (mainPanel && typeof isElementInViewport === 'function' && !isElementInViewport(mainPanel)) {
    mainPanel.scrollIntoView(false);
  }

  // Show loading indicators and clear any previous card content
  const handleUserDiscourse = $id("discourse");
  let handleUserTempCard = $id("temp-card");
  if (handleUserTempCard) {
    const cardText = handleUserTempCard.querySelector(".card-text");
    if (cardText) cardText.innerHTML = '';
    $show(handleUserTempCard);
    window._lastProcessedIndex = -1;
    window._lastProcessedSequence = -1;

    if (handleUserTempCard.parentNode) handleUserTempCard.parentNode.removeChild(handleUserTempCard);
    if (handleUserDiscourse) handleUserDiscourse.appendChild(handleUserTempCard);
  } else {
    handleUserTempCard = document.createElement('div');
    handleUserTempCard.id = 'temp-card';
    handleUserTempCard.className = 'card mt-3 streaming-card';
    handleUserTempCard.innerHTML = `
        <div class="card-header p-2 ps-3 d-flex justify-content-between align-items-center">
          <div class="fs-5 card-title mb-0">
            <span><i class="fas fa-robot" style="color: #DC4C64;"></i></span> <span class="fw-bold fs-6" style="color: #DC4C64;">Assistant</span>
          </div>
        </div>
        <div class="card-body role-assistant">
          <div class="card-text"></div>
        </div>`;
    if (handleUserDiscourse) handleUserDiscourse.appendChild(handleUserTempCard);
    window._lastProcessedIndex = -1;
    window._lastProcessedSequence = -1;
  }

  const handleUserTempStatus = handleUserTempCard.querySelector(".status");
  $hide(handleUserTempStatus);
  const handleUserIndicator = $id("indicator");
  $show(handleUserIndicator);
  ["message", "send", "clear", "image-file", "voice", "doc", "url", "select-role"].forEach(function(id) {
    const el = $id(id);
    if (el) el.disabled = true;
  });
  $id('cancel_query').style.setProperty('display', 'flex', 'important');

  // Show spinner
  const processingRequestText = typeof webUIi18n !== 'undefined' ?
    webUIi18n.t('ui.messages.spinnerProcessingRequest') : 'Processing request';
  const handleUserSpinner = $id("monadic-spinner");
  if (handleUserSpinner) {
    const handleUserSpan = handleUserSpinner.querySelector("span");
    if (handleUserSpan) handleUserSpan.innerHTML = `<i class="fas fa-brain fa-pulse"></i> ${processingRequestText}...`;
    $show(handleUserSpinner);
  }

  // Mark streaming state
  window.streamingResponse = true;
  if (window.UIState) {
    window.UIState.set('streamingResponse', true);
    window.UIState.set('isStreaming', true);
  }
  window.responseStarted = false;

  // Clear any existing spinner check interval
  if (window.spinnerCheckInterval) {
    clearInterval(window.spinnerCheckInterval);
    window.spinnerCheckInterval = null;
  }

  // Keep spinner visible during initial gap
  let checkCount = 0;
  window.spinnerCheckInterval = setInterval(() => {
    checkCount++;
    if (checkCount > 30 || window.responseStarted || !window.streamingResponse) {
      clearInterval(window.spinnerCheckInterval);
      window.spinnerCheckInterval = null;
      return;
    }
    const intervalSpinner = $id("monadic-spinner");
    if (window.streamingResponse && !window.responseStarted && intervalSpinner && (intervalSpinner.style.display === 'none' || intervalSpinner.offsetParent === null)) {
      const txt = typeof webUIi18n !== 'undefined' ?
        webUIi18n.t('ui.messages.spinnerProcessingRequest') : 'Processing request';
      const intervalSpan = intervalSpinner.querySelector("span");
      if (intervalSpan) intervalSpan.innerHTML = `<i class="fas fa-brain fa-pulse"></i> ${txt}...`;
      $show(intervalSpinner);
    }
  }, 100);
}

// Export for browser environment
window.WsStreamingHandler = {
  handleStreamingComplete,
  handleDefaultMessage,
  handleUser
};

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = window.WsStreamingHandler;
}
})();
