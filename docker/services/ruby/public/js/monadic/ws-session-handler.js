/**
 * WebSocket Session Handler for Monadic Chat
 *
 * Handles session-level WebSocket messages that don't involve
 * streaming state or audio playback:
 * - context_extraction_started / context_update: Context panel lifecycle
 * - language_updated: Conversation language changes with RTL support
 * - processing_status / system_info: System message display
 * - stt: Speech-to-text completion
 * - pdf_titles / pdf_deleted: PDF document management
 * - change_status: Message active/inactive status toggle
 * - success: Generic success notifications
 * - sample_success: Sample message addition confirmation
 *
 * Extracted from websocket.js to reduce the size of connect_websocket().
 */
(function() {
'use strict';

/**
 * Handle "context_extraction_started" WebSocket message.
 * Shows loading state in the context panel.
 * @param {Object} _data - Message data (unused)
 */
function handleContextExtractionStarted(_data) {
  if (typeof ContextPanel !== "undefined") {
    ContextPanel.showLoading();
    if (window.debugWebSocket) console.log("[WS] Context extraction started");
  }
}

/**
 * Handle "context_update" WebSocket message.
 * Updates context panel with extracted data and optional schema.
 * @param {Object} data - Message data with context and optional schema
 */
function handleContextUpdate(data) {
  if (typeof WorkflowViewer !== 'undefined' && WorkflowViewer.setStage) {
    WorkflowViewer.setStage('context');
  }
  if (typeof ContextPanel !== "undefined") {
    ContextPanel.hideLoading();
    if (data.context) {
      ContextPanel.updateContext(data.context, data.schema || null);
      if (window.debugWebSocket) console.log("[WS] Context panel updated:", data.context, "schema:", data.schema);
    }
  }
}

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

  if (data.language && $("#conversation-language").val() !== data.language) {
    $("#conversation-language").val(data.language);
  }

  if (data.text_direction) {
    if (data.text_direction === "rtl") {
      $("body").addClass("rtl-messages");
      if (window.debugWebSocket) console.log("RTL messages enabled for:", data.language);
    } else {
      $("body").removeClass("rtl-messages");
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

  if (!$("#monadic-spinner").is(":visible")) {
    $("#monadic-spinner").show();
  }

  const $systemDiv = $('<div class="system-info-message"><i class="fas fa-hourglass-half"></i> </div>');
  const contentText = typeof data.content === 'object' ? JSON.stringify(data.content) : data.content;
  $systemDiv.append($('<span>').text(contentText));

  const systemElement = createCard("system",
    "<span class='text-success'><i class='fas fa-database'></i></span> <span class='fw-bold fs-6 text-success'>System</span>",
    $systemDiv[0].outerHTML,
    "en",
    null,
    true,
    []
  );
  $("#discourse").append(systemElement);
  if (window.MarkdownRenderer) {
    window.MarkdownRenderer.applyRenderers(systemElement[0]);
  }

  if (window.autoScroll) {
    const chatBottom = document.getElementById('chat-bottom');
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
  const $systemDiv = $('<div class="system-info-message"><i class="fas fa-info-circle"></i> </div>');
  const contentText = typeof data.content === 'object' ? JSON.stringify(data.content) : data.content;
  $systemDiv.append($('<span>').text(contentText));

  const systemElement = createCard("system",
    "<span class='text-success'><i class='fas fa-database'></i></span> <span class='fw-bold fs-6 text-success'>System</span>",
    $systemDiv[0].outerHTML,
    "en",
    null,
    true,
    []
  );
  $("#discourse").append(systemElement);
  if (window.MarkdownRenderer) {
    window.MarkdownRenderer.applyRenderers(systemElement[0]);
  }

  if (window.autoScroll) {
    const chatBottom = document.getElementById('chat-bottom');
    if (chatBottom && !isElementInViewport(chatBottom)) {
      chatBottom.scrollIntoView(false);
    }
  }
}

/**
 * Handle "stt" WebSocket message.
 * Processes speech-to-text completion with optional auto-submit.
 * @param {Object} data - Message data with content string and logprob
 */
function handleSTT(data) {
  // Use the handler if available, otherwise use inline code
  let handled = false;
  if (typeof wsHandlers !== 'undefined' && wsHandlers && typeof wsHandlers.handleSTTMessage === 'function') {
    handled = wsHandlers.handleSTTMessage(data);
  }

  if (!handled) {
    $("#message").val($("#message").val() + " " + data["content"]);
    let logprob = "Last Speech-to-Text p-value: " + data["logprob"];
    $("#asr-p-value").text(logprob);
    $("#send, #clear, #voice").prop("disabled", false);

    const origPlaceholder = $("#message").data("original-placeholder") || (typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messagePlaceholder') : "Type your message or click Speech Input button to use voice . . .");
    $("#message").attr("placeholder", origPlaceholder);

    $("#amplitude").hide();

    if ($("#check-easy-submit").is(":checked")) {
      if (typeof window.isForegroundTab === 'function' && !window.isForegroundTab()) {
        if (window.debugWebSocket) console.log('[Send] Ignoring auto-submit: tab is not foreground');
      } else {
        $("#send").click();
      }
    }
    const voiceFinishedText = getTranslation('ui.messages.voiceRecognitionFinished', 'Voice recognition finished');
    setAlert(`<i class='fa-solid fa-circle-check'></i> ${voiceFinishedText}`, "secondary");
    setInputFocus();
  }
}

/**
 * Handle "pdf_titles" WebSocket message.
 * Renders the PDF list with delete buttons.
 * @param {Object} data - Message data with content array of title strings
 */
function handlePDFTitles(data) {
  const rows = data["content"].map((title, index) => {
    const safeTitle = String(title).replace(/</g, '&lt;');
    return `<div class="d-flex align-items-center justify-content-between py-1 border-bottom pdf-db-row">`
         +   `<span class="pdf-db-name">${safeTitle}</span>`
         +   `<button id='pdf-del-${index}' type='button' class='btn btn-sm btn-outline-secondary'>`
         +     `<i class='fa-regular fa-trash-can text-secondary'></i>`
         +   `</button>`
         + `</div>`;
  }).join("");
  $("#pdf-titles").html(rows || `<span class='text-secondary'>(none)</span>`);
  data["content"].forEach((title, index) => {
    $(`#pdf-del-${index}`).off('click').on('click', function () {
      const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) ||
                   (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);

      if (isIOS) {
        const base = (typeof webUIi18n !== 'undefined') ? webUIi18n.t('ui.modals.pdfDeleteConfirmation') : 'Are you sure you want to delete';
        if (confirm(`${base} ${title}?`)) {
          window.ws.send(JSON.stringify({ message: "DELETE_PDF", contents: title }));
        }
      } else {
        $("#pdfDeleteConfirmation").modal("show");
        $("#pdfToDelete").text(title);
        $("#pdfDeleteConfirmed").off("click").on("click", function (event) {
          event.preventDefault();
          window.ws.send(JSON.stringify({ message: "DELETE_PDF", contents: title }));
          $("#pdfDeleteConfirmation").modal("hide");
          $("#pdfToDelete").text("");
        });
      }
    });
  });
}

/**
 * Handle "pdf_deleted" WebSocket message.
 * Shows deletion result and refreshes PDF list.
 * @param {Object} data - Message data with res and content
 */
function handlePDFDeleted(data) {
  if (data["res"] === "success") {
    setAlert(`<i class='fa-solid fa-circle-check'></i> ${data["content"]}`, "info");
  } else {
    setAlert(data["content"], "error");
  }
  window.ws.send(JSON.stringify({ "message": "PDF_TITLES" }));
}

/**
 * Handle "change_status" WebSocket message.
 * Toggles active/inactive class on message cards.
 * @param {Object} data - Message data with content array of {mid, active} objects
 */
function handleChangeStatus(data) {
  data["content"].forEach((msg) => {
    const card = $(`#${msg["mid"]}`);
    if (card.length) {
      if (msg["active"]) {
        card.find(".status").addClass("active");
      } else {
        card.find(".status").removeClass("active");
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

    $("#monadic-spinner").hide();
    document.getElementById('cancel_query').style.setProperty('display', 'none', 'important');

    const sampleAddedText = getTranslation('ui.messages.sampleMessageAdded', 'Sample message added');
    setAlert(`<i class='fas fa-check-circle'></i> ${sampleAddedText}`, "success");
  }
}

// Export for browser environment
window.WsSessionHandler = {
  handleContextExtractionStarted,
  handleContextUpdate,
  handleLanguageUpdated,
  handleProcessingStatus,
  handleSystemInfo,
  handleSTT,
  handlePDFTitles,
  handlePDFDeleted,
  handleChangeStatus,
  handleSuccess,
  handleSampleSuccess
};

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = window.WsSessionHandler;
}
})();
