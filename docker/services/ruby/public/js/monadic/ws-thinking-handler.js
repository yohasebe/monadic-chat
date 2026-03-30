/**
 * WebSocket Thinking/Reasoning Handler for Monadic Chat
 *
 * Handles thinking/reasoning content display and fragment management:
 * - thinking/reasoning: Streaming display of model reasoning process
 * - clear_fragments: Reset fragment buffer between tool calls
 *
 * Extracted from websocket.js to reduce the size of connect_websocket().
 */
(function() {
'use strict';

/**
 * Handle "thinking" or "reasoning" WebSocket message.
 * Creates or updates a temporary reasoning card showing the model's
 * internal reasoning process (e.g., Claude's thinking blocks).
 * @param {Object} data - Message data with content and type
 */
function handleThinking(data) {
  const content = data.content || '';
  if (!content) return;

  if (typeof WorkflowViewer !== 'undefined' && WorkflowViewer.setStage) {
    WorkflowViewer.setStage('model');
  }
  if (typeof window.setReasoningStreamActive === 'function') {
    window.setReasoningStreamActive(true);
  }
  if (typeof ensureThinkingSpinnerVisible === 'function') {
    ensureThinkingSpinnerVisible();
  }

  // Create or get temporary reasoning card
  let tempReasoningCard = document.getElementById("temp-reasoning-card");
  if (!tempReasoningCard) {
    const titleText = data.type === 'thinking' ?
      (typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.thinkingProcess') : 'Thinking Process') :
      (typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.reasoningProcess') : 'Reasoning Process');

    tempReasoningCard = document.createElement('div');
    tempReasoningCard.id = 'temp-reasoning-card';
    tempReasoningCard.className = 'card mt-3 streaming-card';
    tempReasoningCard.innerHTML = `
        <div class="card-header p-2 ps-3">
          <div class="fs-6 card-title mb-0 text-muted d-flex align-items-center">
            <i class="fas fa-brain me-2"></i>
            <span>${titleText}</span>
          </div>
        </div>
        <div class="card-body">
          <div class="card-text"></div>
        </div>`;
    const discourse = document.getElementById("discourse");
    if (discourse) discourse.appendChild(tempReasoningCard);
  }

  // Append thinking/reasoning content
  const tempText = tempReasoningCard.querySelector(".card-text");
  if (tempText) {
    // Use DocumentFragment for efficient DOM manipulation while preserving newlines
    const docFrag = document.createDocumentFragment();
    const lines = content.split('\n');

    lines.forEach((line, index) => {
      if (index > 0) {
        docFrag.appendChild(document.createElement('br'));
      }
      if (line) {
        docFrag.appendChild(document.createTextNode(line));
      }
    });

    tempText.appendChild(docFrag);
  }
}

/**
 * Handle "clear_fragments" WebSocket message.
 * Clears the fragment buffer in temp-card before streaming post-tool response,
 * preventing pre-tool text from being concatenated with post-tool response.
 * @param {Object} _data - Message data (unused)
 */
function handleClearFragments(_data) {
  const tempCard = document.getElementById("temp-card");
  if (tempCard) {
    const cardText = tempCard.querySelector(".card-text");
    if (cardText) cardText.innerHTML = '';
    // Reset sequence tracking
    window._lastProcessedSequence = -1;
    window._lastProcessedIndex = -1;
  }
}

// Export for browser environment
window.WsThinkingHandler = {
  handleThinking,
  handleClearFragments
};

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = window.WsThinkingHandler;
}
})();
