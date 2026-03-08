/**
 * WebSocket Message Renderer for Monadic Chat
 *
 * Handles rendering of completed messages to the DOM:
 * - past_messages: Restore and render chat history from server
 * - edit_success: Apply edited message content with renderers
 * - display_sample: Render sample messages with formatting
 *
 * Extracted from websocket.js to reduce the size of connect_websocket().
 */
(function() {
'use strict';

/**
 * Handle "past_messages" WebSocket message.
 * Restores chat history by rendering each message as a card.
 * Syncs with SessionState and updates UI indicators.
 * @param {Object} data - Message data with content array of message objects
 */
function handlePastMessages(data) {
  const serverMessages = Array.isArray(data["content"]) ? data["content"] : [];
  if (window.debugWebSocket) console.log(`[Session] Rendering past_messages (count=${serverMessages.length})`);

  if (data["from_import"]) {
    if (typeof setAutoSpeechSuppressed === 'function') {
      setAutoSpeechSuppressed(true, { reason: 'past_messages import' });
    }
    window.isProcessingImport = true;
    window.skipAssistantInitiation = true;
  }

  if (typeof window !== 'undefined') {
    window.isRestoringSession = false;
  }

  const shouldSyncSessionState =
    window.SessionState &&
    typeof window.SessionState.clearMessages === "function" &&
    typeof window.SessionState.addMessage === "function";

  if (shouldSyncSessionState) {
    window.SessionState.clearMessages();
  }

  if (typeof mids !== "undefined" && typeof mids.clear === "function") {
    mids.clear();
  }

  $("#discourse").empty();

  const currentApp = $("#apps").val();
  if (currentApp && window.SessionState && typeof window.SessionState.setCurrentApp === "function") {
    window.SessionState.setCurrentApp(currentApp);
  }

  const currentModel = $("#model").val();
  if (currentModel && window.SessionState) {
    window.SessionState.app.model = currentModel;
  }

  // Track turn number for assistant cards during session restore
  let assistantTurnCount = 0;

  serverMessages.forEach((msg, index) => {
    if (!msg || typeof msg !== "object") {
      return;
    }

    if (!msg.mid) {
      msg.mid = `restored-${Date.now()}-${index}`;
    }

    if (shouldSyncSessionState) {
      window.SessionState.addMessage({ ...msg });
    }

    if (index === 0 && msg.role === "system") {
      // Skip rendering system message at index 0
      if (typeof mids !== "undefined" && typeof mids.add === "function") {
        mids.add(msg.mid);
      }
      return;
    }

    switch (msg.role) {
      case "user": {
        let text = (msg.text || "").trim();
        if (text.startsWith("{") && text.endsWith("}")) {
          try {
            const json = JSON.parse(text);
            text = json.message || text;
          } catch (err) {
            console.warn('[Session] Failed to parse user message JSON', err);
          }
        }
        const safeHtml = text
          .replace(/</g, "&lt;")
          .replace(/>/g, "&gt;")
          .replace(/\n/g, "<br>")
          .replace(/\s/g, " ");
        const images = Array.isArray(msg.images) ? msg.images : [];
        // User turn number is the next assistant turn (current count + 1)
        const userTurnNumber = assistantTurnCount + 1;
        const userCard = createCard(
          "user",
          "<span class='text-secondary'><i class='fas fa-face-smile'></i></span> <span class='fw-bold fs-6 user-color'>User</span>",
          `<p>${safeHtml}</p>`,
          msg.lang,
          msg.mid,
          msg.active,
          images,
          false,  // monadic parameter
          userTurnNumber  // turnNumber
        );
        $("#discourse").append(userCard);
        break;
      }
      case "assistant": {
        // Increment turn count for this assistant message
        assistantTurnCount++;
        const badge =
          msg.badge ||
          "<span class='text-secondary'><i class='fas fa-robot'></i></span> <span class='fw-bold fs-6 assistant-color'>Assistant</span>";
        const assistantCard = createCard(
          "assistant",
          badge,
          renderMessage(msg),
          msg.lang,
          msg.mid,
          msg.active,
          Array.isArray(msg.images) ? msg.images : [],
          false,  // monadic parameter
          assistantTurnCount  // turnNumber
        );
        $("#discourse").append(assistantCard);
        if (window.MarkdownRenderer) {
          window.MarkdownRenderer.applyRenderers(assistantCard[0]);
        }
        break;
      }
      case "info": {
        const infoCard = createCard(
          "info",
          "<span class='text-secondary'><i class='fas fa-info-circle'></i></span> <span class='fw-bold fs-6 text-info'>Info</span>",
          renderMessage(msg),
          msg.lang,
          msg.mid,
          msg.active
        );
        $("#discourse").append(infoCard);
        if (window.MarkdownRenderer) {
          window.MarkdownRenderer.applyRenderers(infoCard[0]);
        }
        break;
      }
      case "system": {
        const systemCard = createCard(
          "system",
          "<span class='text-secondary'><i class='fas fa-bars'></i></span> <span class='fw-bold fs-6 text-success'>System</span>",
          renderMessage(msg),
          msg.lang,
          msg.mid,
          msg.active
        );
        $("#discourse").append(systemCard);
        if (window.MarkdownRenderer) {
          window.MarkdownRenderer.applyRenderers(systemCard[0]);
        }
        break;
      }
      default:
        break;
    }

    if (typeof mids !== "undefined" && typeof mids.add === "function") {
      mids.add(msg.mid);
    }
  });

  if (!shouldSyncSessionState && Array.isArray(window.messages)) {
    window.messages = [...serverMessages];
  }

  setStats(formatInfo(serverMessages), "info");

  const hasConversation = serverMessages.some((m) => m.role !== "system");
  const labelPromise = window.i18nReady || Promise.resolve();
  labelPromise.then(() => {
    if (hasConversation) {
      const continueText =
        typeof webUIi18n !== "undefined" && webUIi18n.initialized
          ? webUIi18n.t("ui.session.continueSession")
          : "Continue Session";
      $("#start-label").text(continueText);
    } else {
      const startText =
        typeof webUIi18n !== "undefined" && webUIi18n.initialized
          ? webUIi18n.t("ui.session.startSession")
          : "Start Session";
      $("#start-label").text(startText);
    }
  });

  const connectedText =
    typeof webUIi18n !== "undefined" && webUIi18n.initialized
      ? webUIi18n.t("ui.messages.connected")
      : "Connected";
  setAlert(`<i class='fa-solid fa-circle-check'></i> ${connectedText}`, "success");

  if (typeof window.updateAIUserButtonState === 'function') {
    window.updateAIUserButtonState(serverMessages);
  }

  if (window.SessionState && typeof window.SessionState.clearResetFlags === "function") {
    window.SessionState.clearResetFlags();
  }
  // Clear isProcessingImport flag after import completes
  if (window.isProcessingImport) {
    window.isProcessingImport = false;
  }
  // Clear skipAssistantInitiation for non-import cases
  if (window.skipAssistantInitiation && !data["from_import"]) {
    window.skipAssistantInitiation = false;
  }
  // After loading past messages, set initialLoadComplete to true
  window.initialLoadComplete = true;
}

/**
 * Handle "edit_success" WebSocket message.
 * Updates the card content with edited HTML and re-applies renderers.
 * @param {Object} data - Message data with mid, html, content, images
 */
function handleEditSuccess(data) {
  // Handle successful message edit
  setAlert(`<i class='fa-solid fa-circle-check'></i> ${data.content}`, "success");

  // Get the message card by mid
  const $card = $(`#${data.mid}`);
  if (!$card.length) {
    return;
  }

  const $cardText = $card.find(".card-text");

  // Update the HTML content
  if (data.html) {
    // Update the card with the HTML from server
    $cardText.html(data.html);

    // Apply renderers to the updated content
    if (window.MarkdownRenderer) {
      window.MarkdownRenderer.applyRenderers($cardText[0]);
    }

    // Check if we have preserved images from before editing
    const $preservedImages = $cardText.data('preservedImages');

    // Add images if they exist
    if (data.images && Array.isArray(data.images) && data.images.length > 0) {
      // Group mask images with their original images
      const imageMap = new Map();
      const maskImages = [];

      // First pass - identify all mask images and base images
      data.images.forEach(image => {
        if (image.is_mask || (image.title && image.title.startsWith("mask__"))) {
          // Store mask images separately with reference to their base image
          maskImages.push(image);
        } else {
          // Store base images in a map with their title as key
          imageMap.set(image.title, image);
        }
      });

      // Second pass - create HTML for each base image, with its mask if available
      let image_data = "";

      // Process regular images first
      imageMap.forEach((image, title) => {
        // Check if this image has a mask
        const maskImage = maskImages.find(mask =>
          mask.mask_for === title ||
          (mask.title && mask.title.includes(title.replace(/\.[^.]+$/, "")))
        );

        if (maskImage) {
          // This image has a mask - render as overlay
          image_data += `
            <div class="mask-overlay-container mb-3">
              <img class='base-image' alt='${image.title}' src='${image.data}' />
              <img class='mask-overlay' alt='${maskImage.title}' src='${maskImage.display_data || maskImage.data}' style="opacity: 0.6;" />
              <div class="mask-overlay-label">MASK</div>
            </div>
          `;
        } else if (image.type === 'application/pdf') {
          // PDF file
          image_data += `
            <div class="pdf-preview mb-3">
              <i class="fas fa-file-pdf text-danger"></i>
              <span class="ms-2">${image.title}</span>
            </div>
          `;
        } else {
          // Regular image without mask
          image_data += `
            <img class='base64-image mb-3' src='${image.data}' alt='${image.title}' style='max-width: 100%; height: auto;' />
          `;
        }
      });

      // Finally, add any mask images that don't have a matching base image
      maskImages.forEach(mask => {
        if (!imageMap.has(mask.mask_for)) {
          image_data += `
            <img class='base64-image mb-3' src='${mask.display_data || mask.data}' alt='${mask.title}' style='max-width: 100%; height: auto;' />
          `;
        }
      });

      $cardText.append(image_data);
    } else if ($preservedImages && $preservedImages.length > 0) {
      // If no images from server but we have preserved images, restore them
      $cardText.append($preservedImages);
    }

    // Clean up the preserved images data
    $cardText.removeData('preservedImages');

    // Update the messages array with the new images
    const messages = window.messages || [];
    const messageIndex = messages.findIndex((m) => m.mid === data.mid);
    if (messageIndex !== -1 && data.images) {
      messages[messageIndex].images = data.images;
    }

    // Apply all the required processing for assistant messages
    const htmlContent = $card;

    // Use toBool helper for defensive boolean evaluation
    const toBool = window.toBool || ((value) => {
      if (typeof value === 'boolean') return value;
      if (typeof value === 'string') return value === 'true';
      return !!value;
    });

    const p = window.params || {};

    if (toBool(p["toggle"])) {
      applyToggle(htmlContent);
    }

    if (toBool(p["mermaid"])) {
      applyMermaid(htmlContent);
    }

    if (typeof applyDrawIO === 'function') {
      applyDrawIO(htmlContent);
    }

    if (toBool(p["mathjax"])) {
      applyMathJax(htmlContent);
    }

    if (toBool(p["abc"])) {
      applyAbc(htmlContent);
    }

    formatSourceCode(htmlContent);
    cleanupListCodeBlocks(htmlContent);

    setCopyCodeButton(htmlContent);
  }
}

/**
 * Handle "display_sample" WebSocket message.
 * Renders a sample message as a card with formatting.
 * @param {Object} data - Message data with content {mid, role, text, badge}
 */
function handleDisplaySample(data) {
  // Immediately display the sample message
  const content = data.content;
  if (!content || !content.mid || !content.role || !content.text || !content.badge) {
    if (content) console.error("Invalid display_sample message format:", data);
    return;
  }

  // First check if this message already exists
  if ($("#" + content.mid).length > 0) {
    return;
  }

  // Phase 2: Render text client-side using MarkdownRenderer
  let renderedHtml;
  if (content.role === "user") {
    // User messages: simple HTML escaping and line breaks
    renderedHtml = "<p>" + content.text.replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\n/g, "<br>").replace(/\s/g, " ") + "</p>";
  } else {
    // Assistant and system messages: use MarkdownRenderer
    renderedHtml = window.MarkdownRenderer ? window.MarkdownRenderer.render(content.text) : content.text;
  }

  // Create appropriate element based on role
  const cardElement = createCard(
    content.role,
    content.badge,
    renderedHtml,
    "en", // Default language
    content.mid,
    true  // Always active
  );

  // Append to discourse
  $("#discourse").append(cardElement);
  // applyRenderers is called within MarkdownRenderer.render(), so no need to call again
  // But for safety, call it anyway in case render() wasn't used
  if (window.MarkdownRenderer && content.role !== "assistant" && content.role !== "system") {
    window.MarkdownRenderer.applyRenderers(cardElement[0]);
  }

  // Add message to messages array to ensure edit functionality works correctly
  // This ensures sample messages are treated consistently with API-generated messages
  if (content.text) {
    const messageObj = {
      "role": content.role,
      "text": content.text,
      "mid": content.mid
    };

    // Add to messages array - this ensures last message detection works correctly
    window.SessionState.addMessage(messageObj);
  }

  // Apply appropriate styling based on current settings
  const htmlContent = $("#discourse div.card:last");

  // Use toBool helper for defensive boolean evaluation
  const toBool = window.toBool || ((value) => {
    if (typeof value === 'boolean') return value;
    if (typeof value === 'string') return value === 'true';
    return !!value;
  });

  const p = window.params || {};

  if (toBool(p["toggle"])) {
    applyToggle(htmlContent);
  }

  if (toBool(p["mermaid"])) {
    applyMermaid(htmlContent);
  }

  if (typeof applyDrawIO === 'function') {
    applyDrawIO(htmlContent);
  }

  if (toBool(p["mathjax"])) {
    applyMathJax(htmlContent);
  }

  if (toBool(p["abc"])) {
    applyAbc(htmlContent);
  }

  formatSourceCode(htmlContent);
  cleanupListCodeBlocks(htmlContent);

  setCopyCodeButton(htmlContent);

  // Scroll to bottom
  if (window.autoScroll && window.chatBottom && !isElementInViewport(window.chatBottom)) {
    window.chatBottom.scrollIntoView(false);
  }
}

// Export for browser environment
window.WsMessageRenderer = {
  handlePastMessages,
  handleEditSuccess,
  handleDisplaySample
};

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = window.WsMessageRenderer;
}
})();
