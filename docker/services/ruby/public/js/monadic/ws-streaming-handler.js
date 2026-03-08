/**
 * WebSocket Streaming Handler for Monadic Chat
 *
 * Handles streaming lifecycle messages:
 * - streaming_complete: Reset streaming state, hide spinner, show ready status
 *
 * Extracted from websocket.js to reduce the size of connect_websocket().
 */

const BUSY_CHECK_INTERVAL_MS = (typeof window !== 'undefined' && window.WsAudioConstants || {}).BUSY_CHECK_INTERVAL_MS || 500;
const BUSY_CHECK_MAX_WAIT_MS = (typeof window !== 'undefined' && window.WsAudioConstants || {}).BUSY_CHECK_MAX_WAIT_MS || 10000;

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
    const checkboxEnabled = typeof $ !== 'undefined' && $("#check-auto-speech").is(":checked");
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
        $("#monadic-spinner").hide();
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

    // Always ensure UI elements are enabled
    $("#message").prop("disabled", false);
    $("#send, #clear, #image-file, #voice, #doc, #url, #pdf-import").prop("disabled", false);
    $("#select-role").prop("disabled", false);

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
      $("#monadic-spinner span").html(`<i class="fa-solid fa-circle-nodes fa-pulse"></i> ${receivingResponseText}`);
      $("#monadic-spinner").show();
    }

    // Use the dedicated fragment handler
    if (typeof window.handleFragmentMessage === 'function') {
      window.handleFragmentMessage(data);
    }

    $("#indicator").show();
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
      const receivingResponseText = typeof webUIi18n !== 'undefined' ?
        webUIi18n.t('ui.messages.spinnerReceivingResponse') : 'Receiving response';
      $("#monadic-spinner span").html(`<i class="fa-solid fa-circle-nodes fa-pulse"></i> ${receivingResponseText}`);
      $("#monadic-spinner").show();
    }
    $("#indicator").show();
    if (content !== undefined) {
      content = content.replace(/^\n+/, "");
      $("#chat").html($("#chat").html() + content.replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\n/g, "<br>"));
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
  const userTurnNumber = $('#discourse .card:not(#temp-card) .role-assistant').length + 1;
  if (typeof window.appendCard === 'function') {
    window.appendCard("user", "<span class='text-secondary'><i class='fas fa-face-smile'></i></span> <span class='fw-bold fs-6 user-color'>User</span>", "<p>" + content_text + "</p>", data["content"]["lang"], data["content"]["mid"], true, images, userTurnNumber);
  }

  // Scroll down immediately after showing user message
  const mainPanel = window.mainPanel;
  if (mainPanel && typeof isElementInViewport === 'function' && !isElementInViewport(mainPanel)) {
    mainPanel.scrollIntoView(false);
  }

  // Show loading indicators and clear any previous card content
  if ($("#temp-card").length) {
    $("#temp-card .card-text").empty();
    $("#temp-card").show();
    window._lastProcessedIndex = -1;
    window._lastProcessedSequence = -1;

    const tempCard = $("#temp-card");
    tempCard.detach();
    $("#discourse").append(tempCard);
  } else {
    const tempCard = $(`
      <div id="temp-card" class="card mt-3 streaming-card">
        <div class="card-header p-2 ps-3 d-flex justify-content-between align-items-center">
          <div class="fs-5 card-title mb-0">
            <span><i class="fas fa-robot" style="color: #DC4C64;"></i></span> <span class="fw-bold fs-6" style="color: #DC4C64;">Assistant</span>
          </div>
        </div>
        <div class="card-body role-assistant">
          <div class="card-text"></div>
        </div>
      </div>
    `);
    $("#discourse").append(tempCard);
    window._lastProcessedIndex = -1;
    window._lastProcessedSequence = -1;
  }

  $("#temp-card .status").hide();
  $("#indicator").show();
  $("#message").prop("disabled", true);
  $("#send, #clear, #image-file, #voice, #doc, #url").prop("disabled", true);
  $("#select-role").prop("disabled", true);
  document.getElementById('cancel_query').style.setProperty('display', 'flex', 'important');

  // Show spinner
  const processingRequestText = typeof webUIi18n !== 'undefined' ?
    webUIi18n.t('ui.messages.spinnerProcessingRequest') : 'Processing request';
  $("#monadic-spinner span").html(`<i class="fas fa-brain fa-pulse"></i> ${processingRequestText}...`);
  $("#monadic-spinner").show();

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
    if (window.streamingResponse && !window.responseStarted && !$("#monadic-spinner").is(":visible")) {
      const txt = typeof webUIi18n !== 'undefined' ?
        webUIi18n.t('ui.messages.spinnerProcessingRequest') : 'Processing request';
      $("#monadic-spinner span").html(`<i class="fas fa-brain fa-pulse"></i> ${txt}...`);
      $("#monadic-spinner").show();
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
