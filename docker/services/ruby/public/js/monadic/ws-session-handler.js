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

  var langSelect = document.getElementById('conversation-language');
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

  var spinner = document.getElementById('monadic-spinner');
  if (spinner && spinner.style.display === 'none') {
    spinner.style.display = '';
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
  var discourse = document.getElementById('discourse');
  var sysEl = systemElement[0] || systemElement;
  if (discourse && sysEl) discourse.appendChild(sysEl);
  if (window.MarkdownRenderer) {
    window.MarkdownRenderer.applyRenderers(sysEl);
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
  var discourse = document.getElementById('discourse');
  var sysEl = systemElement[0] || systemElement;
  if (discourse && sysEl) discourse.appendChild(sysEl);
  if (window.MarkdownRenderer) {
    window.MarkdownRenderer.applyRenderers(sysEl);
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
    var messageEl = document.getElementById('message');
    if (messageEl) messageEl.value = messageEl.value + " " + data["content"];

    var asrEl = document.getElementById('asr-p-value');
    if (data["logprob"] != null) {
      if (asrEl) { asrEl.textContent = "Last Speech-to-Text p-value: " + data["logprob"]; asrEl.style.display = ''; }
    } else {
      if (asrEl) { asrEl.textContent = ""; asrEl.style.display = 'none'; }
    }

    ['send', 'clear', 'voice'].forEach(function(id) {
      var el = document.getElementById(id);
      if (el) el.disabled = false;
    });

    if (messageEl) {
      var origPlaceholder = messageEl.dataset.originalPlaceholder || (typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messagePlaceholder') : "Type your message or click Speech Input button to use voice . . .");
      messageEl.setAttribute("placeholder", origPlaceholder);
    }

    var amplitudeEl = document.getElementById('amplitude');
    if (amplitudeEl) amplitudeEl.style.display = 'none';

    var easySubmit = document.getElementById('check-easy-submit');
    if (easySubmit && easySubmit.checked) {
      if (typeof window.isForegroundTab === 'function' && !window.isForegroundTab()) {
        if (window.debugWebSocket) console.log('[Send] Ignoring auto-submit: tab is not foreground');
      } else {
        var sendBtn = document.getElementById('send');
        if (sendBtn) sendBtn.click();
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
  const noPdfsText = (typeof getTranslation === 'function') ? getTranslation('ui.noPdfsLocal', 'No PDFs imported') : 'No PDFs imported';
  var pdfTitlesEl = document.getElementById('pdf-titles');
  if (pdfTitlesEl) pdfTitlesEl.innerHTML = rows || `<span class='text-secondary'>${noPdfsText}</span>`;

  data["content"].forEach((title, index) => {
    var delBtn = document.getElementById('pdf-del-' + index);
    if (delBtn) {
      delBtn.onclick = function() {
        const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) ||
                     (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);

        if (isIOS) {
          const base = (typeof webUIi18n !== 'undefined') ? webUIi18n.t('ui.modals.pdfDeleteConfirmation') : 'Are you sure you want to delete';
          if (confirm(`${base} ${title}?`)) {
            window.ws.send(JSON.stringify({ message: "DELETE_PDF", contents: title }));
          }
        } else {
          var modalEl = document.getElementById('pdfDeleteConfirmation');
          if (modalEl) bootstrap.Modal.getOrCreateInstance(modalEl).show();
          var pdfToDeleteEl = document.getElementById('pdfToDelete');
          if (pdfToDeleteEl) pdfToDeleteEl.textContent = title;
          var confirmBtn = document.getElementById('pdfDeleteConfirmed');
          if (confirmBtn) {
            confirmBtn.onclick = function(event) {
              event.preventDefault();
              window.ws.send(JSON.stringify({ message: "DELETE_PDF", contents: title }));
              if (modalEl) bootstrap.Modal.getOrCreateInstance(modalEl).hide();
              if (pdfToDeleteEl) pdfToDeleteEl.textContent = "";
            };
          }
        }
      };
    }
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
    const card = document.getElementById(msg["mid"]);
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

    var spinner = document.getElementById('monadic-spinner');
    if (spinner) spinner.style.display = 'none';
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
