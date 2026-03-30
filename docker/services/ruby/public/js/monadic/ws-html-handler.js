/**
 * WebSocket HTML Message Handler for Monadic Chat
 *
 * Handles "html" WebSocket messages — the final rendered message from the server.
 * Processes assistant, user, and system roles with:
 * - Thinking/reasoning block rendering
 * - moreComing (tool call continuation) logic
 * - Auto Speech TTS triggering
 * - Spinner and UI state management
 *
 * Extracted from websocket.js to reduce the size of connect_websocket().
 */
(function() {
'use strict';

/**
 * Handle "html" WebSocket message.
 * This is the main message rendering handler that creates cards for assistant,
 * user, and system messages. Manages streaming state transitions and Auto Speech.
 * @param {Object} data - Message data with content (role, html, text, mid, lang, etc.)
 */
function handleHtml(data) {
  window.responseStarted = false;

  // Reset completion tracking flags at start of new response
  window.setTextResponseCompleted(false);
  window.setTtsPlaybackStarted(false);

  // Reset sequence retry count for new response
  if (window.WsAudioQueue && window.WsAudioQueue.setSequenceRetryCount) {
    window.WsAudioQueue.setSequenceRetryCount(0);
  }

  // Note: We no longer reset callingFunction here as it was premature.
  // The flag will be properly reset in streaming_complete handler with appropriate delays.
  // This prevents "Ready for input" from appearing while function calls are still ongoing.

  // Check if more content is coming (tool calls in progress)
  const moreComing = data["more_coming"] === true;

  // Note: temp-card is now removed AFTER card creation in handleHtmlMessage
  // This ensures streaming content stays visible until the final card replaces it

  // Remove temp-reasoning-card as we're about to show the final HTML
  const tempReasoningCard = document.getElementById("temp-reasoning-card");
  if (tempReasoningCard) tempReasoningCard.remove();
  if (typeof window.setReasoningStreamActive === 'function') {
    window.setReasoningStreamActive(false);
  }

  // Always add message to SessionState for persistence, regardless of which handler processes it
  window.SessionState.addMessage(data["content"]);

  // Use the handler if available, otherwise use inline code
  const wsHandlers = window.wsHandlers;
  let handled = false;
  if (wsHandlers && typeof wsHandlers.handleHtmlMessage === 'function') {
    handled = wsHandlers.handleHtmlMessage(data, window.appendCard);
    if (handled) {
      // moreComing handling is now done inside handleHtmlMessage
      // so cancel_query visibility is controlled there
      if (!data["more_coming"]) {
        document.getElementById('cancel_query').style.setProperty('display', 'none', 'important');
      }
    }
  }

  // Update AI User button state
  if (typeof window.updateAIUserButtonState === 'function') {
    window.updateAIUserButtonState(window.messages);
  }

  if (!handled) {
    // Fallback to inline handling
    // Note: SessionState.addMessage already called above

    // Phase 2: Use MarkdownRenderer if html field is missing
    let html;
    if (data["content"]["html"]) {
      html = data["content"]["html"];
    } else if (data["content"]["text"]) {
      // Client-side rendering with MarkdownRenderer
      html = window.MarkdownRenderer ?
        window.MarkdownRenderer.render(data["content"]["text"], { appName: data["content"]["app_name"] }) :
        data["content"]["text"];
    } else {
      console.error("Message has neither html nor text field:", data["content"]);
      html = "";
    }

    if (data["content"]["thinking"]) {
      // Use the unified thinking block renderer if available
      if (typeof renderThinkingBlock === 'function') {
        const thinkingTitle = typeof webUIi18n !== 'undefined' ?
          webUIi18n.t('ui.messages.thinkingProcess') : "Thinking Process";
        html = renderThinkingBlock(data["content"]["thinking"], thinkingTitle) + html;
      } else {
        // Fallback to old style if function not available
        html = "<div data-title='Thinking Block' class='toggle'><div class='toggle-open'>" + data["content"]["thinking"] + "</div></div>" + html;
      }
    } else if(data["content"]["reasoning_content"]) {
      // Use the unified thinking block renderer if available
      if (typeof renderThinkingBlock === 'function') {
        const reasoningTitle = typeof webUIi18n !== 'undefined' ?
          webUIi18n.t('ui.messages.reasoningProcess') : "Reasoning Process";
        html = renderThinkingBlock(data["content"]["reasoning_content"], reasoningTitle) + html;
      } else {
        // Fallback to old style if function not available
        html = "<div data-title='Thinking Block' class='toggle'><div class='toggle-open'>" + data["content"]["reasoning_content"] + "</div></div>" + html;
      }
    }

    if (data["content"]["role"] === "assistant") {
      _handleAssistantRole(data, html, moreComing);
    } else if (data["content"]["role"] === "user") {
      _handleUserRole(data);
    } else if (data["content"]["role"] === "system") {
      _handleSystemRole(data);
    } else {
      // Non-assistant messages: show "Ready for input" only if system is not busy
      document.getElementById('cancel_query').style.setProperty('display', 'none', 'important');
      if (!isSystemBusy()) {
        const readyText = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.readyForInput') : 'Ready for input';
        setAlert(`<i class='fa-solid fa-circle-check'></i> ${readyText}`, "success");
      }
    }

    // Common cleanup for all roles
    const chatEl = document.getElementById("chat");
    if (chatEl) chatEl.innerHTML = "";
    if (typeof clearToolStatus === 'function') {
      clearToolStatus();
    }
    const tempCard = document.getElementById("temp-card");
    if (tempCard) tempCard.style.display = 'none';
    const indicator = document.getElementById("indicator");
    if (indicator) indicator.style.display = 'none';
    const userPanel = document.getElementById("user-panel");
    if (userPanel) userPanel.style.display = '';

    // Make sure message input is enabled
    const messageInput = document.getElementById("message");
    if (messageInput) messageInput.disabled = false;

    const mainPanel = window.mainPanel;
    if (mainPanel && typeof isElementInViewport === 'function' && !isElementInViewport(mainPanel)) {
      mainPanel.scrollIntoView(false);
    }

    if (typeof setInputFocus === 'function') {
      setInputFocus();
    }
  }
}

/**
 * Handle assistant role within the html message.
 * Manages moreComing (tool continuation) vs final message logic,
 * including Auto Speech TTS triggering.
 * @param {Object} data - Full message data
 * @param {string} html - Rendered HTML content
 * @param {boolean} moreComing - Whether more tool calls are expected
 * @private
 */
function _handleAssistantRole(data, html, moreComing) {
  // Calculate turn number based on existing assistant cards + 1 (excluding temp-card)
  const discourseEl = document.getElementById('discourse');
  const turnNumber = discourseEl ? discourseEl.querySelectorAll('.card:not(#temp-card) .role-assistant').length + 1 : 1;
  window.appendCard("assistant", "<span class='text-secondary'><i class='fas fa-robot'></i></span> <span class='fw-bold fs-6 assistant-color'>Assistant</span>", html, data["content"]["lang"], data["content"]["mid"], true, [], turnNumber);

  if (moreComing) {
    // Keep input disabled and streaming state active
    window.callingFunction = true;
    window.streamingResponse = true;
    window.responseStarted = false; // Reset for next streaming
    if (window.UIState) {
      window.UIState.set('streamingResponse', true);
      window.UIState.set('isStreaming', true);
    }

    // Re-show and reset temp-card for next streaming
    // Reset sequence tracking for new streaming session
    // This is critical - without this, fragments may be skipped as duplicates
    window._lastProcessedSequence = -1;
    window._lastProcessedIndex = -1;

    let tempCardEl = document.getElementById("temp-card");
    const discEl = document.getElementById("discourse");
    if (!tempCardEl) {
      // Create new temp-card if it doesn't exist
      tempCardEl = document.createElement('div');
      tempCardEl.id = 'temp-card';
      tempCardEl.className = 'card mt-3 streaming-card';
      tempCardEl.innerHTML = `
          <div class="card-header p-2 ps-3 d-flex justify-content-between align-items-center">
            <div class="fs-5 card-title mb-0">
              <span><i class="fas fa-robot" style="color: #DC4C64;"></i></span> <span class="fw-bold fs-6" style="color: #DC4C64;">Assistant</span>
            </div>
          </div>
          <div class="card-body role-assistant">
            <div class="card-text"></div>
          </div>`;
      if (discEl) discEl.appendChild(tempCardEl);
    } else {
      // Reset existing temp-card
      const cardText = tempCardEl.querySelector(".card-text");
      if (cardText) cardText.innerHTML = '';
      if (tempCardEl.parentNode) tempCardEl.parentNode.removeChild(tempCardEl);
      if (discEl) discEl.appendChild(tempCardEl);
    }
    tempCardEl.style.display = '';

    // Show spinner with "Processing tools" message
    const processingToolsText = typeof webUIi18n !== 'undefined' ?
      webUIi18n.t('ui.messages.spinnerProcessingTools') : 'Processing tools';
    const spinnerEl = document.getElementById("monadic-spinner");
    if (spinnerEl) {
      const spanEl = spinnerEl.querySelector("span");
      if (spanEl) spanEl.innerHTML = `<i class="fas fa-cogs fa-pulse"></i> ${processingToolsText}`;
      spinnerEl.style.display = '';
    }

    // Keep cancel button visible
    document.getElementById('cancel_query').style.setProperty('display', 'flex', 'important');
  } else {
    // Final message - normal completion flow
    _handleFinalAssistantMessage(data);
  }
}

/**
 * Handle the final assistant message (no more tool calls coming).
 * Manages spinner, streaming state reset, Auto Speech TTS, and UI restoration.
 * @param {Object} data - Full message data
 * @private
 */
function _handleFinalAssistantMessage(data) {
  // Show message input and hide spinner
  const msgEl = document.getElementById("message");
  if (msgEl) {
    msgEl.style.display = '';
    msgEl.value = ""; // Clear the message after successful response
    msgEl.disabled = false;
  }
  // Re-enable all input controls
  ["send", "clear", "image-file", "voice", "doc", "url", "pdf-import", "select-role"].forEach(function(id) {
    const el = document.getElementById(id);
    if (el) el.disabled = false;
  });

  // Reset streaming flag as response is done
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
  // Note: We check callingFunction and streamingResponse directly here,
  // not isSystemBusy(), to avoid circular dependency with spinner visibility
  if (!window.callingFunction && !window.streamingResponse) {
    // Mark text response as completed
    window.setTextResponseCompleted(true);
    // Check if we can hide spinner (depends on Auto Speech mode)
    if (typeof checkAndHideSpinner === 'function') {
      checkAndHideSpinner();
    }
  }

  // If this is the first assistant message (from initiate_from_assistant), show user panel
  const finalUserPanel = document.getElementById("user-panel");
  const finalTempCard = document.getElementById("temp-card");
  if (finalUserPanel && finalUserPanel.style.display === 'none' && finalTempCard && finalTempCard.style.display !== 'none') {
    finalUserPanel.style.display = '';
    if (typeof setInputFocus === 'function') {
      setInputFocus();
    }
  }

  document.getElementById('cancel_query').style.setProperty('display', 'none', 'important');

  // For assistant messages, don't show "Ready to start" immediately
  // Wait for streaming to complete
  const receivedText = typeof webUIi18n !== 'undefined' ?
    webUIi18n.t('ui.messages.responseReceived') : 'Response received';
  setAlert(`<i class='fa-solid fa-circle-check'></i> ${receivedText}`, "success");

  // Handle auto_speech for TTS auto-playback
  _handleAutoSpeech(data);
}

/**
 * Handle Auto Speech TTS logic after assistant message is received.
 * Manages foreground/background tab detection, suppression state,
 * and server-side TTS triggering.
 * @param {Object} data - Full message data (used for mid-based dedup)
 * @private
 */
function _handleAutoSpeech(data) {
  // Support both boolean and string values for backward compatibility
  const autoSpeechEnabled = window.params && (window.params["auto_speech"] === true || window.params["auto_speech"] === "true");
  const suppressionActive = typeof isAutoSpeechSuppressed === 'function' && isAutoSpeechSuppressed();
  const inForeground = typeof window.isForegroundTab === 'function' ? window.isForegroundTab() : !(typeof document !== 'undefined' && document.hidden);

  if (!inForeground) {
    if (typeof setAutoSpeechSuppressed === 'function') {
      setAutoSpeechSuppressed(true, { reason: 'background_tab', log: false });
    }
    window.autoSpeechActive = false;
    window.autoPlayAudio = false;
  } else if (suppressionActive) {
    window.autoSpeechActive = false;
    window.autoPlayAudio = false;
    if (typeof window.setTtsPlaybackStarted === 'function') {
      window.setTtsPlaybackStarted(true);
    }
    if (typeof checkAndHideSpinner === 'function') {
      checkAndHideSpinner();
    } else if (typeof resetAutoSpeechSpinner === 'function') {
      resetAutoSpeechSpinner();
    }
    if (typeof window.autoTTSSpinnerTimeout !== 'undefined' && window.autoTTSSpinnerTimeout) {
      clearTimeout(window.autoTTSSpinnerTimeout);
      window.autoTTSSpinnerTimeout = null;
    }
  } else if (window.autoSpeechActive || autoSpeechEnabled) {
    // Message ID check: prevent duplicate TTS for the same message (e.g., on sleep/wake reconnection)
    const currentMid = data["content"]["mid"];
    if (currentMid && window.WsAudioQueue && currentMid === window.WsAudioQueue.getLastAutoTtsMessageId()) {
      console.debug('[Auto TTS] Skipped - already played for message:', currentMid);
      // Mark TTS as "completed" (skipped) so spinner hides properly
      window.autoSpeechActive = false;
      window.autoPlayAudio = false;
      if (typeof window.setTtsPlaybackStarted === 'function') {
        window.setTtsPlaybackStarted(true);
      }
      // Hide spinner since we're skipping TTS
      if (typeof checkAndHideSpinner === 'function') {
        checkAndHideSpinner();
      }
    } else {
      // Record message ID before triggering TTS
      if (currentMid && window.WsAudioQueue && window.WsAudioQueue.setLastAutoTtsMessageId) {
        window.WsAudioQueue.setLastAutoTtsMessageId(currentMid);
      }

      // For Auto TTS, the SERVER automatically triggers TTS after streaming completes.
      // We do NOT click the Play button here to avoid duplicate audio.
      // The server will send audio messages which the client will receive and play.
      //
      // We just need to:
      // 1. Highlight the Stop button for visual feedback
      // 2. Set a timeout to hide spinner if audio doesn't arrive
      setTimeout(() => {
        const discourseCards = document.querySelectorAll("#discourse div.card");
        const lastCard = discourseCards.length > 0 ? discourseCards[discourseCards.length - 1] : null;
        if (lastCard) {
          // Early highlight for Auto TTS: provides immediate visual feedback
          const cardId = lastCard.id;
          if (cardId && typeof window.highlightStopButton === 'function') {
            window.highlightStopButton(cardId);
          }
        }

        // Set timeout to force hide spinner if audio doesn't start playing
        if (typeof scheduleAutoTtsSpinnerTimeout === 'function') {
          scheduleAutoTtsSpinnerTimeout();
        }

        // Note: window.autoSpeechActive will be reset when audio starts playing
        // See audio.play() promise handler where spinner is hidden
      }, 100);
    }
  }
}

/**
 * Handle user role within the html message (import/past messages rendering).
 * @param {Object} data - Full message data
 * @private
 */
function _handleUserRole(data) {
  let content_text = data["content"]["text"].trim().replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\n/g, "<br>").replace(/\s/g, " ");
  let images;
  if (data["content"]["images"] !== undefined) {
    images = data["content"]["images"];
  }
  // Use the appendCard helper function
  // User turn number is existing assistant cards + 1 (excluding temp-card)
  const userDiscourse = document.getElementById('discourse');
  const userTurnNumber = userDiscourse ? userDiscourse.querySelectorAll('.card:not(#temp-card) .role-assistant').length + 1 : 1;
  window.appendCard("user", "<span class='text-secondary'><i class='fas fa-face-smile'></i></span> <span class='fw-bold fs-6 user-color'>User</span>", "<p>" + content_text + "</p>", data["content"]["lang"], data["content"]["mid"], true, images, userTurnNumber);
  const userMsgEl = document.getElementById("message");
  if (userMsgEl) {
    userMsgEl.style.display = '';
    userMsgEl.disabled = false;
  }

  _resetStreamingAndShowReady();
}

/**
 * Handle system role within the html message.
 * @param {Object} data - Full message data
 * @private
 */
function _handleSystemRole(data) {
  // Use the appendCard helper function
  window.appendCard("system", "<span class='text-secondary'><i class='fas fa-bars'></i></span> <span class='fw-bold fs-6 system-color'>System</span>", data["content"]["html"], data["content"]["lang"], data["content"]["mid"], true);
  const sysMsgEl = document.getElementById("message");
  if (sysMsgEl) {
    sysMsgEl.style.display = '';
    sysMsgEl.disabled = false;
  }

  _resetStreamingAndShowReady();
}

/**
 * Common streaming state reset and "Ready for input" display.
 * Used by user and system role handlers.
 * @private
 */
function _resetStreamingAndShowReady() {
  // Reset streaming flag as response is done
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
    window.setTextResponseCompleted(true);
    if (typeof checkAndHideSpinner === 'function') {
      checkAndHideSpinner();
    }
  }
  document.getElementById('cancel_query').style.setProperty('display', 'none', 'important');
  // Only show "Ready for input" if system is not busy
  if (!isSystemBusy()) {
    const readyText = typeof webUIi18n !== 'undefined' ?
      webUIi18n.t('ui.messages.readyForInput') : 'Ready for input';
    setAlert(`<i class='fa-solid fa-circle-check'></i> ${readyText}`, "success");
  }
}

// Export for browser environment
window.WsHtmlHandler = {
  handleHtml
};

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = window.WsHtmlHandler;
}
})();
