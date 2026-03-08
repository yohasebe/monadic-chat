/**
 * WebSocket Tool Handler for Monadic Chat
 *
 * Handles tool execution lifecycle messages:
 * - tool_executing: Updates UI when a tool starts executing
 * - message: Handles DONE (with/without tool_calls) and CLEAR signals
 *
 * Extracted from websocket.js to reduce the size of connect_websocket().
 */

/**
 * Handle "tool_executing" WebSocket message.
 * Updates the UI to show which tool is currently executing.
 * @param {Object} data - Message data with content (tool name)
 */
function handleToolExecuting(data) {
  window.toolCallCount++;
  window.currentToolName = data["content"];

  // Show temp card early if hidden (immediate feedback)
  const toolTempCard = $("#temp-card");
  if (toolTempCard.length && toolTempCard.is(":hidden")) {
    toolTempCard.show();
  }

  // Update temp card header with tool name and count
  if (typeof updateToolStatus === 'function') {
    updateToolStatus(window.currentToolName, window.toolCallCount);
  }

  // Update workflow viewer
  if (typeof WorkflowViewer !== 'undefined' && WorkflowViewer.setActiveTool) {
    WorkflowViewer.setActiveTool(data["content"], window.toolCallCount);
  }
}

/**
 * Handle "message" WebSocket message.
 * Processes DONE signals (with or without pending tool calls) and CLEAR signals.
 * @param {Object} data - Message data with content and finish_reason
 */
function handleMessage(data) {
  if (data["content"] === "DONE") {
    // Check if tool calls are pending
    if (data["finish_reason"] === "tool_calls") {
      // Keep spinner visible for tool calls
      window.callingFunction = true;
      $("#monadic-spinner").show();
      const processingToolsText = typeof getTranslation === 'function' ?
        getTranslation('ui.messages.spinnerProcessingTools', 'Processing tools') :
        'Processing tools';
      $("#monadic-spinner span").html(`<i class="fas fa-cogs fa-pulse"></i> ${processingToolsText}`);
    } else {
      // No tool calls, ensure callingFunction is false
      window.callingFunction = false;
      if (typeof WorkflowViewer !== 'undefined' && WorkflowViewer.setStage) {
        WorkflowViewer.setStage('done');
      }
    }
    if (window.ws && typeof window.ws.send === 'function') {
      window.ws.send(JSON.stringify({ "message": "HTML" }));
    }
  } else if (data["content"] === "CLEAR") {
    $("#chat").html("");
    $("#temp-card .status").hide();
    $("#indicator").show();
  }
}

// Export for browser environment
window.WsToolHandler = {
  handleToolExecuting,
  handleMessage
};

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = window.WsToolHandler;
}
