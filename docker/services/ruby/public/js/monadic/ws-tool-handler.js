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

/**
 * Handle "wait" WebSocket message.
 * Displays progress information during tool execution, agent processing,
 * and parallel dispatch operations.
 * @param {Object} data - Message data with content, source, minutes, step_progress, etc.
 */
function handleWait(data) {
  window.callingFunction = true;

  // Check if content is a translation key
  let waitContent = data["content"];
  if (waitContent === 'generating_ai_user_response') {
    waitContent = typeof getTranslation === 'function' ?
      getTranslation('ui.messages.generatingAIUserResponse', 'Generating AI user response...') :
      'Generating AI user response...';
  }

  // Check if this is an agent progress message
  const isAgentProgress = (
    data["source"] && (
      data["source"] === "OpenAICodeAgent" ||
      data["source"] === "ClaudeCodeAgent" ||
      data["source"] === "GrokCodeAgent" ||
      data["source"] === "ImageGenerator" ||
      data["source"] === "VideoAnalyzer" ||
      data["source"] === "SecondOpinion" ||
      data["source"] === "ParallelDispatch" ||
      data["source"] === "ParallelCodeExecution" ||
      data["source"] === "MultiProviderVerification" ||
      data["source"].includes("Agent") ||
      data["source"].includes("Generator") ||
      data["source"].includes("Analyzer")
    )
  );

  if (isAgentProgress) {
    let displayContent = waitContent;
    if (data["minutes"] !== undefined) {
      const minutes = data["minutes"];
      const remaining = data["remaining"];
      let messageKey;
      let iconHtml = '<i class="fas fa-laptop-code"></i>';

      if (data["source"] === "OpenAICodeAgent") {
        iconHtml = '<i class="fas fa-laptop-code" style="color: #4285f4;"></i>';
        if (minutes <= 1) messageKey = 'openaiCodeGenerating';
        else if (minutes <= 2) messageKey = 'openaiCodeStructuring';
        else if (minutes <= 3) messageKey = 'openaiCodeAnalyzing';
        else if (minutes <= 4) messageKey = 'openaiCodeOptimizing';
        else messageKey = 'openaiCodeFinalizing';
      } else if (data["source"] === "ClaudeCodeAgent") {
        iconHtml = '<i class="fas fa-laptop-code" style="color: #6f42c1;"></i>';
        if (minutes <= 1) messageKey = 'claudeCodeGenerating';
        else if (minutes <= 2) messageKey = 'claudeCodeStructuring';
        else if (minutes <= 3) messageKey = 'claudeCodeAnalyzing';
        else if (minutes <= 4) messageKey = 'claudeCodeOptimizing';
        else messageKey = 'claudeCodeFinalizing';
      } else {
        if (minutes <= 1) messageKey = 'agentProcessing';
        else if (minutes <= 3) messageKey = 'agentAnalyzing';
        else messageKey = 'agentFinalizing';
      }

      const _getTranslation = typeof getTranslation === 'function' ? getTranslation : (k, f) => f;
      let localizedMessage = _getTranslation(`ui.messages.${messageKey}`, waitContent);

      if (minutes > 0) {
        const elapsedText = _getTranslation('ui.messages.elapsedTime', '{minutes} minute(s) elapsed')
          .replace('{minutes}', minutes);
        displayContent = `${iconHtml} ${localizedMessage} (${elapsedText})`;
      } else {
        displayContent = `${iconHtml} ${localizedMessage}`;
      }

      if (remaining > 0 && remaining <= 5) {
        const remainingText = _getTranslation('ui.messages.remainingTime', '{minutes} minute(s) remaining')
          .replace('{minutes}', remaining);
        displayContent += ` - ${remainingText}`;
      }
      displayContent += '...';
    } else if (data["step_progress"]) {
      const sp = data["step_progress"];
      const spMode = sp["mode"] || "sequential";
      const spCurrent = sp["current"] || 0;
      const spSteps = sp["steps"] || [];

      let spIcon, spColor;
      switch (data["source"]) {
        case "OpenAICodeAgent":
          spIcon = "fa-laptop-code"; spColor = "#4285f4"; break;
        case "ClaudeCodeAgent":
          spIcon = "fa-laptop-code"; spColor = "#6f42c1"; break;
        case "GrokCodeAgent":
          spIcon = "fa-laptop-code"; spColor = "#6b7280"; break;
        case "ParallelDispatch":
          spIcon = "fa-network-wired"; spColor = "#10b981"; break;
        case "ParallelCodeExecution":
          spIcon = "fa-code"; spColor = "#10b981"; break;
        case "MultiProviderVerification":
          spIcon = "fa-people-arrows"; spColor = "#7c3aed"; break;
        default:
          spIcon = "fa-laptop-code"; spColor = "#6b7280"; break;
      }

      const spHeader = `<i class="fas ${spIcon}" style="color: ${spColor};"></i> ${data["content"] || "Processing..."}`;
      const indicators = spSteps.map((name, i) => {
        let icon;
        if (spMode === "sequential") {
          if (i < spCurrent) {
            icon = `<i class="fas fa-check" style="color: ${spColor};"></i>`;
          } else if (i === spCurrent) {
            icon = '<span class="parallel-task-spinner"></span>';
          } else {
            icon = '<span class="step-pending-dot"></span>';
          }
        } else {
          icon = i < spCurrent
            ? `<i class="fas fa-check" style="color: ${spColor};"></i>`
            : '<span class="parallel-task-spinner"></span>';
        }
        return `<div style="margin: 2px 0;">${icon} ${name}</div>`;
      }).join('');
      displayContent = `${spHeader}<div style="margin-top: 4px;"><small>${indicators}</small></div>`;
    } else if (
      (data["source"] === "ParallelDispatch" || data["source"] === "MultiProviderVerification") &&
      data["parallel_progress"]
    ) {
      const isMultiProvider = data["source"] === "MultiProviderVerification";
      const iconHtml = isMultiProvider
        ? '<i class="fas fa-people-arrows" style="color: #7c3aed;"></i>'
        : '<i class="fas fa-network-wired" style="color: #10b981;"></i>';
      const pp = data["parallel_progress"];
      const completed = pp["completed"] || 0;
      const total = pp["total"] || 0;
      const label = isMultiProvider
        ? `Provider opinions: ${completed}/${total} completed`
        : `Parallel tasks: ${completed}/${total} completed`;
      displayContent = `${iconHtml} ${label}`;
      if (pp["task_names"]) {
        const checkColor = isMultiProvider ? "#7c3aed" : "#10b981";
        const indicators = pp["task_names"].map((name, i) => {
          const icon = i < completed
            ? `<i class="fas fa-check" style="color: ${checkColor};"></i>`
            : '<span class="parallel-task-spinner"></span>';
          return `<div style="margin: 2px 0;">${icon} ${name}</div>`;
        }).join('');
        displayContent += `<div style="margin-top: 4px;"><small>${indicators}</small></div>`;
      }
    } else if (!waitContent.includes('<i class="fas')) {
      let iconHtml = '<i class="fas fa-laptop-code"></i>';
      if (data["source"] === "OpenAICodeAgent") {
        iconHtml = '<i class="fas fa-laptop-code" style="color: #4285f4;"></i>';
      } else if (data["source"] === "ClaudeCodeAgent") {
        iconHtml = '<i class="fas fa-laptop-code" style="color: #6f42c1;"></i>';
      } else if (data["source"] === "GrokCodeAgent") {
        iconHtml = '<i class="fas fa-laptop-code" style="color: #6b7280;"></i>';
      }
      displayContent = `${iconHtml} ${waitContent}`;
    }

    // Display agent progress in streaming temp card
    let tempCard = $("#temp-card");
    if (!tempCard.length) {
      tempCard = $(`
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
    } else {
      tempCard.detach();
      $("#discourse").append(tempCard);
    }

    $("#temp-card .card-text").html(`<div class="mb-0" style="color: inherit;">${displayContent}</div>`);
    $("#temp-card").show();
  } else {
    // Regular wait messages go to status-message
    setAlert(waitContent, "warning");
  }

  // Show the spinner and update its message
  $("#monadic-spinner").show();

  const _getTranslation = typeof getTranslation === 'function' ? getTranslation : (k, f) => f;

  // Highlight workflow node based on wait content
  if (typeof WorkflowViewer !== 'undefined' && WorkflowViewer.setStage) {
    WorkflowViewer.setStage(data["content"].includes("CALLING FUNCTIONS") ? 'tools' : 'model');
  }

  // Customize spinner message based on wait content
  if (data["content"].includes("CALLING FUNCTIONS")) {
    const callingFunctionsText = _getTranslation('ui.messages.spinnerCallingFunctions', 'Calling functions');
    $("#monadic-spinner span").html(`<i class="fas fa-cogs fa-pulse"></i> ${callingFunctionsText}`);
  } else if (data["content"].includes("SEARCHING WEB")) {
    const searchingWebText = _getTranslation('ui.messages.spinnerSearchingWeb', 'Searching web');
    $("#monadic-spinner span").html(`<i class="fas fa-search fa-pulse"></i> ${searchingWebText}`);
  } else if (data["content"].includes("PROCESSING")) {
    const processingText = _getTranslation('ui.messages.spinnerProcessing', 'Processing');
    $("#monadic-spinner span").html(`<i class="fas fa-spinner fa-pulse"></i> ${processingText}`);
  } else {
    const processingRequestText = _getTranslation('ui.messages.spinnerProcessingRequest', 'Processing request');
    $("#monadic-spinner span").html(`<i class="fas fa-brain fa-pulse"></i> ${processingRequestText}`);
  }
}

// Export for browser environment
window.WsToolHandler = {
  handleToolExecuting,
  handleMessage,
  handleWait
};

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = window.WsToolHandler;
}
