/**
 * WebSocket AI User Handler for Monadic Chat
 *
 * Handles the AI User feature lifecycle:
 * - ai_user_started: Disable UI, show generating spinner
 * - ai_user: Stream AI-generated text into message field
 * - ai_user_finished: Re-enable UI with completed response
 *
 * Extracted from websocket.js to reduce the size of connect_websocket().
 */
(function() {
'use strict';

/**
 * Handle "ai_user_started" WebSocket message.
 * Disables all input elements and shows a generating spinner.
 * @param {Object} _data - Message data (unused)
 */
function handleAIUserStarted(_data) {
  const generatingText = getTranslation('ui.messages.generatingAIUserResponse', 'Generating AI user response...');
  setAlert(`<i class='fas fa-spinner fa-spin'></i> ${generatingText}`, "warning");

  // Show the cancel button
  document.getElementById('cancel_query').style.setProperty('display', 'flex', 'important');

  // Show spinner and update its message with robot animation
  const spinnerEl = document.getElementById("monadic-spinner");
  if (spinnerEl) {
    spinnerEl.style.display = "block";
    const spanEl = spinnerEl.querySelector("span");
    const aiUserText = typeof webUIi18n !== 'undefined' && webUIi18n.initialized ?
      webUIi18n.t('ui.messages.spinnerGeneratingAIUser') : 'Generating AI user response';
    if (spanEl) spanEl.innerHTML = `<i class="fas fa-robot fa-pulse"></i> ${aiUserText}`;
  }

  // Disable the input elements
  const disableIds = ["message", "send", "clear", "image-file", "voice", "doc", "url", "ai_user", "select-role"];
  disableIds.forEach(function(id) {
    const el = document.getElementById(id);
    if (el) el.disabled = true;
  });
}

/**
 * Handle "ai_user" WebSocket message.
 * Appends streamed AI-generated text to the message input field.
 * @param {Object} data - Message data with content string
 */
function handleAIUser(data) {
  // Append AI user content to the message field
  const messageEl = document.getElementById("message");
  if (messageEl) messageEl.value = messageEl.value + data["content"].replace(/\\n/g, "\n");

  // Make sure the message panel is visible
  if (window.autoScroll && mainPanel && !isElementInViewport(mainPanel)) {
    mainPanel.scrollIntoView(false);
  }
}

/**
 * Handle "ai_user_finished" WebSocket message.
 * Sets final trimmed content, re-enables UI, and shows success alert.
 * @param {Object} data - Message data with final content string
 */
function handleAIUserFinished(data) {
  // Trim extra whitespace from the final message
  const trimmedContent = data["content"].trim();

  // Set the message content
  const finishedMessageEl = document.getElementById("message");
  if (finishedMessageEl) finishedMessageEl.value = trimmedContent;

  // Hide cancel button and spinner
  document.getElementById('cancel_query').style.setProperty('display', 'none', 'important');
  const finishedSpinner = document.getElementById("monadic-spinner");
  if (finishedSpinner) finishedSpinner.style.display = "none";

  // Re-enable all input elements individually
  const enableIds = ["message", "send", "clear", "image-file", "voice", "doc", "url", "pdf-import", "ai_user", "select-role"];
  enableIds.forEach(function(id) {
    const el = document.getElementById(id);
    if (el) el.disabled = false;
  });

  // Update alert message to success state
  const generatedText = getTranslation('ui.messages.aiUserResponseGenerated', 'AI user response generated');
  setAlert(`<i class='fa-solid fa-circle-check'></i> ${generatedText}`, "success");

  // Ensure the panel is visible
  if (mainPanel && !isElementInViewport(mainPanel)) {
    mainPanel.scrollIntoView(false);
  }

  // Focus on the input field
  setInputFocus();
}

// Export for browser environment
window.WsAIUserHandler = {
  handleAIUserStarted,
  handleAIUser,
  handleAIUserFinished
};

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = window.WsAIUserHandler;
}
})();
