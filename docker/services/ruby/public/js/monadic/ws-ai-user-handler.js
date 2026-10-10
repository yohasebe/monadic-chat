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

// The suggestion the page is waiting for. Each request carries an id that
// the server repeats on every notice; a notice for any other request (one
// given up at Reset or app switch) is ignored, so it can neither fill the
// input box nor unlock the controls.
let currentRequest = null;
// Whether the controls are locked for the current request.
let inProgress = false;

// Called by the AI User button: the page is locked from here until the
// suggestion is finished, fails, or is given up.
function beginRequest() {
  currentRequest = 'aiu_' + Date.now().toString(36) + '_' + Math.random().toString(36).slice(2, 10);
  inProgress = true;
  return currentRequest;
}

function isWaiting() {
  return currentRequest !== null;
}

function isCurrent(data) {
  return !!(data && currentRequest && data.request_id === currentRequest);
}

const LOCKED_IDS = ["message", "send", "clear", "image-file", "voice", "doc", "url", "ai_user", "select-role"];
// Also locked by the AI User button itself when it sends the request.
const CLICK_LOCKED_IDS = ["audio-upload", "pdf-import"];

function unlockControls() {
  $id('cancel_query').style.setProperty('display', 'none', 'important');
  $hide($id("monadic-spinner"));
  LOCKED_IDS.concat(CLICK_LOCKED_IDS).forEach(function(id) {
    const el = $id(id);
    if (el) el.disabled = false;
  });
}

/**
 * Handle "ai_user_started" WebSocket message.
 * Disables all input elements and shows a generating spinner.
 * @param {Object} _data - Message data (unused)
 */
function handleAIUserStarted(data) {
  if (!isCurrent(data)) return;
  inProgress = true;
  const generatingText = getTranslation('ui.messages.generatingAIUserResponse', 'Generating AI user response...');
  setAlert(`<i class='fas fa-spinner fa-spin'></i> ${generatingText}`, "warning");

  // Show the cancel button
  $id('cancel_query').style.setProperty('display', 'flex', 'important');

  // Show spinner and update its message with robot animation
  const spinnerEl = $id("monadic-spinner");
  if (spinnerEl) {
    spinnerEl.style.display = "block";
    const spanEl = spinnerEl.querySelector("span");
    const aiUserText = typeof webUIi18n !== 'undefined' && webUIi18n.initialized ?
      webUIi18n.t('ui.messages.spinnerGeneratingAIUser') : 'Generating AI user response';
    if (spanEl) spanEl.innerHTML = `<i class="fas fa-robot fa-pulse"></i> ${aiUserText}`;
  }

  // Disable the input elements
  LOCKED_IDS.forEach(function(id) {
    const el = $id(id);
    if (el) el.disabled = true;
  });
}

/**
 * Handle "ai_user" WebSocket message.
 * Appends streamed AI-generated text to the message input field.
 * @param {Object} data - Message data with content string
 */
function handleAIUser(data) {
  if (!isCurrent(data)) return;
  // Append AI user content to the message field
  const messageEl = $id("message");
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
  if (!isCurrent(data)) return;
  currentRequest = null;
  // Trim extra whitespace from the final message
  const trimmedContent = data["content"].trim();

  // Set the message content
  const finishedMessageEl = $id("message");
  if (finishedMessageEl) finishedMessageEl.value = trimmedContent;

  // Hide cancel button and spinner, and re-enable the input elements
  inProgress = false;
  unlockControls();

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

/**
 * Handle "ai_user_error": the current request failed. Ends it and gives the
 * page its controls back; the input box is left as it is. The error of a
 * request given up already is ignored, so it cannot change the next chat.
 * @param {Object} data - Message data with request_id and content
 */
function handleAIUserError(data) {
  if (!isCurrent(data)) return;
  currentRequest = null;
  inProgress = false;
  unlockControls();
  const known = {
    'ai_user_requires_conversation': ['ui.messages.aiUserRequiresConversation', 'AI User requires an existing conversation. Please start a conversation first.'],
    'ai_user_busy': ['ui.messages.aiUserBusy', 'An AI User suggestion is already being written.']
  };
  const content = String(data.content || '');
  const text = known[content] ? getTranslation(known[content][0], known[content][1]) : content;
  setAlert(`<i class='fa-solid fa-circle-exclamation'></i> ${escapeAlertText(text)}`, "error");
}

function escapeAlertText(text) {
  return text.replace(/[&<>"']/g, function (c) {
    return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
  });
}

/**
 * Called on Reset: a suggestion still being written belongs to the chat
 * that ended, so the page gets its controls back without it.
 */
function abandonAIUser() {
  const locked = inProgress;
  currentRequest = null;
  inProgress = false;
  if (locked) unlockControls();
}

// Export for browser environment
window.WsAIUserHandler = {
  handleAIUserStarted,
  handleAIUser,
  handleAIUserFinished,
  handleAIUserError,
  abandonAIUser,
  beginRequest,
  isWaiting
};

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = window.WsAIUserHandler;
}
})();
