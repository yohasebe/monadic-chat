// Use a Set for faster searching
const mids = new Set();

// escapeHtml and createCard have been extracted to card-renderer.js

// Function to attach all event listeners - uses event delegation on the card element
function attachEventListeners(card) {
  // First ensure we remove any existing listeners to prevent duplicates
  detachEventListeners(card);

  // We use a single click listener on the card for delegation
  function cardClickHandler(event) {
    // --- func-delete ---
    const deleteBtn = event.target.closest(".func-delete");
    if (deleteBtn && card.contains(deleteBtn)) {
      event.stopPropagation();

      const parentCard = deleteBtn.closest(".card");
      const mid = parentCard ? parentCard.id : null;

      if (!mid) return;

      // Check if this card is currently in edit mode and cancel it first
      if (activeEditSession && activeEditSession.mid === mid) {
        cancelEditMode(activeEditSession.cardText, activeEditSession.editButton);
        activeEditSession = null;
      }

      // For all cards, try to find if there's a corresponding message
      const messageIndex = messages.findIndex((m) => m.mid === mid);

      // Extra handling for error messages - check multiple error patterns
      const cardTextEl = parentCard.querySelector(".card-text");
      const cardText = cardTextEl ? cardTextEl.textContent : '';
      const isApiError = cardText.includes("API ERROR:") ||
                        cardText.includes("Error:") ||
                        cardText.includes("invalid_message") ||
                        cardText.includes("Bad Request");

      if (isApiError) {
        // Just directly remove the element from DOM
        parentCard.remove();

        // Force the browser to redraw
        document.body.offsetHeight;

        // Also remove in case it's a temporary message
        const dupEl = $id(mid);
        if (dupEl) dupEl.remove();

        // If the message is in the messages array, remove it
        if (messageIndex !== -1) {
          messages.splice(messageIndex, 1);
        }

        // Notify the server
        ws.send(JSON.stringify({ "message": "DELETE", "mid": mid }));
        mids.delete(mid);

        // Add explicit visual feedback for the user
        const messageDeletedText = getTranslation('ui.messages.messageDeleted', 'Message deleted');
        setAlert(`<i class='fas fa-circle-check'></i> ${messageDeletedText}`, "success");
        return;
      }

      // For system messages, treat the same as other messages
      // (no special treatment)

      // For regular messages, check if it's in the messages array
      if (messageIndex !== -1) {
        const isLastMessage = messageIndex === messages.length - 1;

        // Store card data
        const deleteConfirmEl = $id("deleteConfirmation");
        if (deleteConfirmEl) {
          deleteConfirmEl.dataset.mid = mid;
          deleteConfirmEl.dataset.messageIndex = messageIndex;
        }

        // Get message text for preview
        const cardBody = parentCard.querySelector(".card-body");
        let messageText = cardBody ? cardBody.textContent.trim() : '';

        // Clean up technical content
        if (messageText.startsWith('/*') || messageText.startsWith('//') ||
            messageText.includes('position: relative') || messageText.includes('{') && messageText.includes('}')) {
          messageText = "[Message contains code or technical content]";
        }

        const truncatedText = messageText.length > 100 ? messageText.substring(0, 100) + "..." : messageText;
        const msgToDeleteEl = $id("messageToDelete");
        if (msgToDeleteEl) msgToDeleteEl.textContent = truncatedText;

        // Configure modal based on message position
        const deleteSubBtn = $id("deleteMessageAndSubsequent");
        $toggle(deleteSubBtn, !isLastMessage);

        // Show the modal
        if (deleteConfirmEl) bootstrap.Modal.getOrCreateInstance(deleteConfirmEl).show();
      } else {
        // If no message found, just delete the card
        detachEventListeners(card);
        card.remove();
        ws.send(JSON.stringify({ "message": "DELETE", "mid": mid }));
        mids.delete(mid);

        const messageDeletedText = getTranslation('ui.messages.messageDeleted', 'Message deleted');
        setAlert(`<i class='fas fa-circle-check'></i> ${messageDeletedText}`, "success");
      }
      return;
    }

    // --- func-play ---
    const playBtn = event.target.closest(".func-play");
    if (playBtn && card.contains(playBtn)) {
      const currentCard = playBtn.closest('.card');

      // Tooltip cleanup
      if (typeof cleanupAllTooltips === 'function') {
        cleanupAllTooltips();
      } else {
        const tip = bootstrap.Tooltip.getInstance(playBtn);
        if (tip) tip.hide();
        document.querySelectorAll('.tooltip').forEach(el => el.remove());
      }

      // Stop any current TTS playback
      if (typeof ttsStop === 'function') {
        ttsStop();
      }

      // Show TTS-specific spinner
      const spinner = $id("monadic-spinner");
      if (spinner) {
        const spanEl = spinner.querySelector("span");
        if (spanEl) spanEl.innerHTML = '<i class="fas fa-headphones fa-pulse"></i> Processing audio';
        $show(spinner);
      }

      const content = currentCard ? currentCard.querySelector(".card-text") : null;
      let text = '';
      try {
        text = content ? content.textContent : '';

        // Clone to process
        if (content) {
          const contentClone = content.cloneNode(true);
          contentClone.querySelectorAll("style, script").forEach(el => el.remove());

          const hrElement = contentClone.querySelector("hr");
          if (hrElement) {
            // Remove everything after hr
            let sibling = hrElement.nextElementSibling;
            while (sibling) {
              const next = sibling.nextElementSibling;
              sibling.remove();
              sibling = next;
            }
            hrElement.remove();
          }

          text = contentClone.textContent || "";
        }
      } catch (e) {
        console.error("Error extracting text for TTS:", e);
        text = content ? content.textContent : '';
      }

      text = removeCode(text);
      text = removeMarkdown(text);
      text = removeEmojis(text);

      const mid = currentCard ? currentCard.id : '';

      if (mid && typeof highlightStopButton === 'function') {
        highlightStopButton(mid);
      }

      const ttsProviderEl = $id("tts-provider");
      const ttsProvider = ttsProviderEl ? ttsProviderEl.value : '';
      let ttsVoice;

      if (ttsProvider === "elevenlabs" || ttsProvider === "elevenlabs-flash" || ttsProvider === "elevenlabs-multilingual" || ttsProvider === "elevenlabs-v3") {
        const el = $id("elevenlabs-tts-voice");
        ttsVoice = el ? el.value : '';
      } else if (ttsProvider === "webspeech") {
        const el = $id("webspeech-voice");
        ttsVoice = el ? el.value : '';
      } else if (ttsProvider === "gemini-flash" || ttsProvider === "gemini-pro") {
        const el = $id("gemini-tts-voice");
        ttsVoice = el ? el.value : '';
      } else {
        const el = $id("tts-voice");
        ttsVoice = el ? el.value : '';
      }

      const ttsSpeedEl = $id("tts-speed");
      const ttsSpeed = ttsSpeedEl ? ttsSpeedEl.value : '';

      const elevenlabsEl = $id("elevenlabs-tts-voice");
      const geminiEl = $id("gemini-tts-voice");
      const mistralEl = $id("mistral-tts-voice");
      const grokEl = $id("grok-tts-voice");
      const convLangEl = $id("conversation-language");

      const ttsMessage = {
        message: "PLAY_TTS",
        text: text,
        tts_provider: ttsProvider,
        tts_voice: ttsVoice,
        elevenlabs_tts_voice: elevenlabsEl ? elevenlabsEl.value : '',
        gemini_tts_voice: geminiEl ? geminiEl.value : '',
        mistral_tts_voice: mistralEl ? mistralEl.value : '',
        grok_tts_voice: grokEl ? grokEl.value : '',
        tts_speed: ttsSpeed,
        conversation_language: convLangEl ? convLangEl.value : "auto",
        mid: mid
      };

      setTimeout(() => {
        ws.send(JSON.stringify(ttsMessage));
      }, 50);
      return;
    }

    // --- func-stop ---
    const stopBtn = event.target.closest(".func-stop");
    if (stopBtn && card.contains(stopBtn)) {
      if (typeof cleanupAllTooltips === 'function') {
        cleanupAllTooltips();
      } else {
        const tip = bootstrap.Tooltip.getInstance(stopBtn);
        if (tip) tip.hide();
        document.querySelectorAll('.tooltip').forEach(el => el.remove());
      }

      if (typeof window.setTextResponseCompleted === 'function') {
        window.setTextResponseCompleted(true);
      }
      if (typeof window.setTtsPlaybackStarted === 'function') {
        window.setTtsPlaybackStarted(true);
      }
      const spinner = $id("monadic-spinner");
      if (spinner) {
        $hide(spinner);
        const spanEl = spinner.querySelector("span");
        if (spanEl) spanEl.innerHTML = '<i class="fas fa-comment fa-pulse"></i> Starting';
      }

      ttsStop();

      if (typeof removeStopButtonHighlight === 'function') {
        removeStopButtonHighlight();
      }

      if (typeof ws !== 'undefined' && ws && ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({ message: "STOP_TTS" }));
      }

      if (typeof window.responseStarted !== 'undefined') {
        window.responseStarted = false;
      }
      if (typeof setAlert === 'function' && typeof window.isSystemBusy === 'function' && !window.isSystemBusy()) {
        const readyToStartText = getTranslation('ui.messages.readyToStart', 'Ready to start');
        setAlert(`<i class='fa-solid fa-circle-check'></i> ${readyToStartText}`, "success");
      }
      return;
    }

    // --- func-copy ---
    const copyBtn = event.target.closest(".func-copy");
    if (copyBtn && card.contains(copyBtn)) {
      (async function() {
        if (typeof cleanupAllTooltips === 'function') {
          cleanupAllTooltips();
        } else {
          const tip = bootstrap.Tooltip.getInstance(copyBtn);
          if (tip) tip.hide();
          document.querySelectorAll('.tooltip').forEach(el => el.remove());
        }

        const mid = card.id;
        const messageIndex = messages.findIndex((m) => m.mid === mid);
        let text = "";

        if (messageIndex !== -1) {
          const message = messages[messageIndex];
          if (message.text) {
            text = message.text;
          } else if (message.content) {
            text = message.content;
          }
        }

        if (!text) {
          const content = card.querySelector(".card-text");
          if (content) {
            const contentClone = content.cloneNode(true);
            contentClone.querySelectorAll("style, script").forEach(el => el.remove());
            text = contentClone.textContent;
          }
        }

        try {
          const textarea = document.createElement('textarea');
          textarea.value = text;
          textarea.style.position = 'fixed';
          textarea.style.opacity = 0;
          document.body.appendChild(textarea);
          textarea.select();

          const success = document.execCommand('copy');
          document.body.removeChild(textarea);

          if (!success) {
            throw new Error('execCommand copy failed');
          }

          const icon = copyBtn.querySelector("i");
          if (icon) {
            icon.classList.remove("fa-copy");
            icon.classList.add("fa-check", "icon-success");
            setTimeout(() => {
              icon.classList.remove("fa-check", "icon-success");
              icon.classList.add("fa-copy");
            }, 1000);
          }
        } catch (err) {
          console.error("Failed to copy text: ", err);

          try {
            if (window.electronAPI && typeof window.electronAPI.writeClipboard === 'function') {
              window.electronAPI.writeClipboard(text);
            } else if (navigator.clipboard && navigator.clipboard.writeText) {
              await navigator.clipboard.writeText(text);
            } else {
              throw new Error('No clipboard API available');
            }

            const icon = copyBtn.querySelector("i");
            if (icon) {
              icon.classList.remove("fa-copy");
              icon.classList.add("fa-check", "icon-success");
              setTimeout(() => {
                icon.classList.remove("fa-check", "icon-success");
                icon.classList.add("fa-copy");
              }, 1000);
            }
          } catch (fallbackErr) {
            console.error("All clipboard methods failed: ", fallbackErr);

            const icon = copyBtn.querySelector("i");
            if (icon) {
              icon.classList.remove("fa-copy");
              icon.classList.add("fa-xmark", "icon-success");
              setTimeout(() => {
                icon.classList.remove("fa-xmark", "icon-success");
                icon.classList.add("fa-copy");
              }, 1000);
            }
          }
        }
      })();
      return;
    }

    // --- func-edit ---
    const editBtn = event.target.closest(".func-edit");
    if (editBtn && card.contains(editBtn)) {
      if (typeof cleanupAllTooltips === 'function') {
        cleanupAllTooltips();
      } else {
        const tip = bootstrap.Tooltip.getInstance(editBtn);
        if (tip) tip.hide();
        document.querySelectorAll('.tooltip').forEach(el => el.remove());
      }

      const mid = card.id;
      const messageIndex = messages.findIndex((m) => m.mid === mid);
      const currentMessage = messages[messageIndex];

      // Check if any message is currently being edited and handle it first
      const existingEditArea = document.querySelector(".inline-edit-textarea");
      if (existingEditArea) {
        const activeEditCard = existingEditArea.closest(".card-text");

        const cancelBtn2 = activeEditCard ? activeEditCard.querySelector(".cancel-edit") : null;
        if (cancelBtn2) {
          cancelBtn2.click();
        } else if (activeEditCard) {
          const editButton2 = activeEditCard.closest(".card") ? activeEditCard.closest(".card").querySelector(".func-edit") : null;
          cancelEditMode(activeEditCard, editButton2);
        }
      }

      if (!currentMessage || !currentMessage.text) {
        alert("The current message can't be edited");
        return;
      }

      const text = currentMessage.text;

      // Check if message is JSON (which can't be edited)
      let json = false;
      try {
        JSON.parse(text);
        json = true;
      } catch (e) {
        // Not JSON, continue
      }

      if (json) {
        alert("The current app is monadic. You can't edit JSON messages");
        return;
      }

      // Check if this is the last message
      const isLastMessage = messageIndex === messages.length - 1;
      const lastCard = document.querySelector("#discourse .card:last-child");
      const isLastDisplayedCard = lastCard === card;

      if (isLastMessage || isLastDisplayedCard) {
        const messageInput = $id("message");
        if (messageInput) messageInput.value = text;

        const selectRole = $id("select-role");
        if (selectRole) {
          if (currentMessage.role === "user") {
            selectRole.value = "user";
          } else if (currentMessage.role === "assistant") {
            selectRole.value = "sample-assistant";
          } else if (currentMessage.role === "system") {
            selectRole.value = "sample-system";
          }
        }

        // If message has images, restore them
        if (currentMessage.images && Array.isArray(currentMessage.images) && currentMessage.images.length > 0) {
          images = images.filter(img => img.type === 'application/pdf');

          const messageImages = [...currentMessage.images];
          const baseImages = [];
          const maskImages = [];

          messageImages.forEach(imageData => {
            const imageCopy = {...imageData};
            if (imageCopy.is_mask || (imageCopy.title && imageCopy.title.startsWith("mask__"))) {
              maskImages.push(imageCopy);
            } else {
              baseImages.push(imageCopy);
            }
          });

          baseImages.forEach(baseImage => { images.push(baseImage); });

          maskImages.forEach(maskImage => {
            images.push(maskImage);
            if (maskImage.mask_for) {
              const hasBaseImage = baseImages.some(img => img.title === maskImage.mask_for);
              if (hasBaseImage) {
                window.currentMaskData = maskImage;
              }
            }
          });

          updateFileDisplay(images);
        }

        if (messageInput) messageInput.focus();

        deleteMessage(mid);
        return;
      }

      // Create an inline editing textarea
      const cardTextEl = card.querySelector(".card-text");
      const editArea = document.createElement('textarea');
      editArea.className = 'form-control inline-edit-textarea';
      editArea.value = text;
      editArea.textContent = text;

      // Style the textarea
      Object.assign(editArea.style, {
        width: '100%',
        minHeight: '100px',
        marginBottom: '10px',
        whiteSpace: 'pre-wrap',
        fontFamily: 'inherit',
        fontSize: '1em',
        color: '#333',
        lineHeight: '1.8',
        padding: '0.375rem 0.75rem',
        border: '1px solid #ced4da',
        borderRadius: '0.25rem',
        overflowY: 'auto'
      });

      // Store original content
      const originalContent = cardTextEl.innerHTML;
      cardTextEl._originalContent = originalContent;

      // Extract text content only (without images)
      const textContent = cardTextEl.querySelector('p');

      // Replace only the text part with the textarea
      if (textContent) {
        textContent.replaceWith(editArea);
      } else {
        cardTextEl.prepend(editArea);
      }

      // Update the global edit session tracker
      activeEditSession = {
        cardText: cardTextEl,
        editButton: editBtn,
        mid: mid,
        messageIndex: messageIndex
      };

      // Create save and cancel buttons
      const buttonRow = document.createElement('div');
      buttonRow.className = 'd-flex justify-content-end';
      buttonRow.innerHTML = `
        <button class="btn btn-sm btn-secondary me-2 cancel-edit">
          <i class="fas fa-times"></i> Cancel
        </button>
        <button class="btn btn-sm btn-primary save-edit">
          <i class="fas fa-check"></i> Save
        </button>
      `;

      cardTextEl.appendChild(buttonRow);

      editArea.focus();

      // Auto-resize the textarea
      const autoResize = function(textarea) {
        textarea.style.height = 'auto';
        textarea.style.height = (textarea.scrollHeight) + 'px';
      };

      editArea.addEventListener('input', function() {
        autoResize(this);
      });

      // Trigger initial resize
      autoResize(editArea);

      // Handle cancel button
      const cancelEditBtn = cardTextEl.querySelector('.cancel-edit');
      if (cancelEditBtn) {
        cancelEditBtn.addEventListener('click', function(e) {
          e.stopPropagation();
          cancelEditMode(cardTextEl, editBtn);
        });
      }

      // Handle save button
      const saveEditBtn = cardTextEl.querySelector('.save-edit');
      if (saveEditBtn) {
        saveEditBtn.addEventListener('click', function(e) {
          e.stopPropagation();

          const newText = editArea.value;

          // Update message in the messages array
          currentMessage.text = newText;

          // For user messages, we can update the display directly
          if (currentMessage.role === "user") {
            const displayText = newText.replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\n/g, "<br>");

            // Preserve existing images/PDFs
            const existingImages = cardTextEl.querySelectorAll('.pdf-preview, .base64-image, .image-container, .mask-overlay-container');
            const detachedImages = Array.from(existingImages).map(el => { el.remove(); return el; });

            cardTextEl.innerHTML = "<p>" + displayText + "</p>";

            detachedImages.forEach(el => cardTextEl.appendChild(el));

            const editIcon = editBtn.querySelector("i");
            if (editIcon) {
              editIcon.classList.remove("fa-check", "icon-success");
              editIcon.classList.add("fa-pen-to-square");
            }
          } else if (currentMessage.role === "assistant") {
            const displayText = newText.replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\n/g, "<br>");

            const existingImages = cardTextEl.querySelectorAll('.pdf-preview, .base64-image, .image-container, .mask-overlay-container');
            const detachedImages = Array.from(existingImages).map(el => { el.remove(); return el; });

            cardTextEl.innerHTML = "<p>" + displayText + "</p>";

            detachedImages.forEach(el => cardTextEl.appendChild(el));
          } else if (currentMessage.role === "system") {
            const displayText = newText.replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\n/g, "<br>");

            const existingImages = cardTextEl.querySelectorAll('.pdf-preview, .base64-image, .image-container, .mask-overlay-container');
            const detachedImages = Array.from(existingImages).map(el => { el.remove(); return el; });

            cardTextEl.innerHTML = displayText;

            detachedImages.forEach(el => cardTextEl.appendChild(el));

            const editIcon = editBtn.querySelector("i");
            if (editIcon) {
              editIcon.classList.remove("fa-check", "icon-success");
              editIcon.classList.add("fa-pen-to-square");
            }
          }

          // Clean up
          delete cardTextEl._originalContent;

          cleanupCardTextListeners(cardTextEl);

          const editMessage = {
            "message": "EDIT",
            "mid": mid,
            "content": newText,
            "role": currentMessage.role
          };

          if (currentMessage.images && Array.isArray(currentMessage.images) && currentMessage.images.length > 0) {
            editMessage.images = [...currentMessage.images];
          }

          ws.send(JSON.stringify(editMessage));

          const editIcon = editBtn.querySelector("i");
          if (editIcon) {
            editIcon.classList.remove("fa-check", "icon-success");
            editIcon.classList.add("fa-pen-to-square");
          }
        });
      }

      // Change the icon to indicate edit mode
      const editIcon = editBtn.querySelector("i");
      if (editIcon) {
        editIcon.classList.remove("fa-pen-to-square");
        editIcon.classList.add("fa-check", "icon-success");
      }
      return;
    }
  }

  card.addEventListener("click", cardClickHandler);
  card._cardClickHandler = cardClickHandler;

  // No duplicate click handler for .func-delete needed

// Function to delete system messages with our improved approach
window.deleteSystemMessage = function(mid, messageIndex) {
  const cardEl = $id(mid);

  if (!cardEl) {
    return;
  }

  // Check if this card is currently in edit mode and cancel it first
  if (activeEditSession && activeEditSession.mid === mid) {
    cancelEditMode(activeEditSession.cardText, activeEditSession.editButton);
    activeEditSession = null;
  }

  // First detach event listeners to prevent memory leaks
  detachEventListeners(cardEl);

  // Properly clean up all tooltips
  if (typeof cleanupAllTooltips === 'function') {
    cleanupAllTooltips();
  } else {
    cardEl.querySelectorAll("[title]").forEach(function(el) {
      const tip = bootstrap.Tooltip.getInstance(el);
      if (tip) { tip.hide(); tip.dispose(); }
    });
    document.querySelectorAll('.tooltip').forEach(el => el.remove());
  }

  // Immediately remove from DOM
  cardEl.remove();

  // Force browser redraw
  document.body.offsetHeight;

  // Extra cleanup for any remaining elements
  const dupEl = $id(mid);
  if (dupEl) dupEl.remove();

  // Clean up messages array if needed
  if (messageIndex !== -1 && messages[messageIndex]) {
    messages.splice(messageIndex, 1);
  }

  // Notify server
  ws.send(JSON.stringify({ "message": "DELETE", "mid": mid }));
  mids.delete(mid);

  // Success feedback
  setAlert("<i class='fas fa-circle-check'></i> Message deleted", "success");
};

/**
 * Update turn numbers on all cards (user and assistant) after a deletion
 * @param {number} deletedTurn - The turn number that was deleted (1-indexed)
 */
function updateCardTurnNumbers(deletedTurn) {
  if (!deletedTurn || deletedTurn < 1) return;

  const turnLabelText = typeof webUIi18n !== "undefined"
    ? webUIi18n.t("ui.messages.contextTurnLabel")
    : "Turn";

  // Find all cards with turn badges that have turn > deletedTurn
  document.querySelectorAll('#discourse .card[data-turn]').forEach(function(cardEl) {
    const currentTurn = parseInt(cardEl.getAttribute('data-turn'), 10);

    if (currentTurn > deletedTurn) {
      const newTurn = currentTurn - 1;
      cardEl.setAttribute('data-turn', newTurn);

      const badge = cardEl.querySelector('.card-turn-badge');
      if (badge) {
        badge.setAttribute('data-turn', newTurn);
        badge.setAttribute('title', `${turnLabelText} ${newTurn}`);
        badge.textContent = `T${newTurn}`;
      }
    }
  });
}

/**
 * Get the turn number of an assistant card by its mid
 * @param {string} mid - The message ID
 * @returns {number|null} The turn number or null if not found
 */
function getCardTurnNumber(mid) {
  const cardEl = $id(mid);
  if (!cardEl) return null;

  const turn = cardEl.getAttribute('data-turn');
  return turn ? parseInt(turn, 10) : null;
}

// Expose these functions globally so they can be called from other scripts
// Note: createCard and escapeHtml are now exported from card-renderer.js
window.attachEventListeners = attachEventListeners;
window.detachEventListeners = detachEventListeners;
window.cancelEditMode = cancelEditMode;
window.cleanupCardTextListeners = cleanupCardTextListeners;
window.updateCardTurnNumbers = updateCardTurnNumbers;
window.getCardTurnNumber = getCardTurnNumber;

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    attachEventListeners,
    detachEventListeners,
    cancelEditMode,
    cleanupCardTextListeners,
    deleteSystemMessage,
    deleteMessageAndSubsequent,
    deleteMessageOnly,
    updateCardTurnNumbers,
    getCardTurnNumber
  };
}
window.deleteMessageAndSubsequent = function(mid, messageIndex) {
  // HTML dataset attributes arrive as strings. `messageIndex + 1` would then
  // perform string concatenation ("2" + 1 === "21") and `slice("21")` would
  // return an empty array — silently skipping the subsequent messages. Coerce
  // once at the boundary so the rest of the function can treat it as a number.
  messageIndex = Number(messageIndex);

  const cardEl = $id(mid);

  if (cardEl && cardEl.querySelector(".role-system")) {
    deleteSystemMessage(mid, messageIndex);
    return;
  }

  // Check if this card is currently in edit mode and cancel it first
  if (activeEditSession && activeEditSession.mid === mid) {
    cancelEditMode(activeEditSession.cardText, activeEditSession.editButton);
    activeEditSession = null;
  }

  // Properly clean up all tooltips
  if (typeof cleanupAllTooltips === 'function') {
    cleanupAllTooltips();
  } else if (cardEl) {
    cardEl.querySelectorAll("[title]").forEach(function(el) {
      const tip = bootstrap.Tooltip.getInstance(el);
      if (tip) { tip.hide(); tip.dispose(); }
    });
    document.querySelectorAll('.tooltip').forEach(el => el.remove());
  }

  // First detach event listeners from the current card
  if (cardEl) detachEventListeners(cardEl);

  // Delete all subsequent messages
  const subsequentMessages = messages.slice(messageIndex + 1);
  subsequentMessages.forEach((m) => {
    const subsequentCard = $id(m.mid);
    if (subsequentCard) {
      detachEventListeners(subsequentCard);
      subsequentCard.remove();
    }
    ws.send(JSON.stringify({ "message": "DELETE", "mid": m.mid }));
    mids.delete(m.mid);
  });

  // Delete current message
  messages.splice(messageIndex);
  if (cardEl) cardEl.remove();
  ws.send(JSON.stringify({ "message": "DELETE", "mid": mid }));
  mids.delete(mid);
};

window.deleteMessageOnly = function(mid, messageIndex) {
  const cardEl = $id(mid);
  if (!cardEl) {
    console.error("Card not found:", mid);
    return;
  }

  // Get the turn number before deletion (for assistant cards)
  const deletedTurn = getCardTurnNumber(mid);

  // Properly clean up all tooltips
  if (typeof cleanupAllTooltips === 'function') {
    cleanupAllTooltips();
  } else {
    cardEl.querySelectorAll("[title]").forEach(function(el) {
      const tip = bootstrap.Tooltip.getInstance(el);
      if (tip) { tip.hide(); tip.dispose(); }
    });
    document.querySelectorAll('.tooltip').forEach(el => el.remove());
  }

  // Special case: handle system role messages
  if (cardEl.querySelector(".role-system")) {
    deleteSystemMessage(mid, messageIndex);
    return;
  }

  // Check if this card is currently in edit mode and cancel it first
  if (activeEditSession && activeEditSession.mid === mid) {
    cancelEditMode(activeEditSession.cardText, activeEditSession.editButton);
    activeEditSession = null;
  }

  // Detach event listeners before doing anything else
  detachEventListeners(cardEl);

  // Check if message exists in the array
  if (messageIndex === -1 || !messages[messageIndex]) {
    cardEl.remove();
    ws.send(JSON.stringify({ "message": "DELETE", "mid": mid }));
    mids.delete(mid);
    if (deletedTurn) {
      updateCardTurnNumbers(deletedTurn);
    }
    return;
  }

  // Remove just this message, preserving subsequent messages
  messages.splice(messageIndex, 1);
  cardEl.remove();
  ws.send(JSON.stringify({ "message": "DELETE", "mid": mid }));
  mids.delete(mid);

  // Update turn numbers on remaining cards
  if (deletedTurn) {
    updateCardTurnNumbers(deletedTurn);
  }
};

  // Tooltip handlers via mouseenter/mouseleave delegation
  function tooltipEnterHandler(event) {
    const target = event.target.closest(".func-play, .func-stop, .func-copy, .func-delete, .func-edit, .status, .card-turn-badge");
    if (target && card.contains(target)) {
      const tip = bootstrap.Tooltip.getInstance(target);
      if (tip) tip.show();
      const icon = target.querySelector("i");
      if (icon) icon.classList.add("icon-active");
    }
  }

  function tooltipLeaveHandler(event) {
    const target = event.target.closest(".func-play, .func-stop, .func-copy, .func-delete, .func-edit, .status, .card-turn-badge");
    if (target && card.contains(target)) {
      const tip = bootstrap.Tooltip.getInstance(target);
      if (tip) tip.hide();

      if (event.type === "mouseleave") {
        const icon = target.querySelector("i");
        if (icon) icon.classList.remove("icon-active");
      }

      // For iOS devices
      const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) ||
                    (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);

      if (isIOS && (event.type === "click" || event.type === "touchend")) {
        const isPlayButton = target.classList.contains("func-play");
        const isStopButton = target.classList.contains("func-stop");

        if (isPlayButton || isStopButton) {
          const icon = target.querySelector("i");
          setTimeout(() => {
            if (icon) icon.classList.remove("icon-active");
          }, 500);
        }
      }
    }
  }

  card.addEventListener("mouseenter", tooltipEnterHandler, true);
  card.addEventListener("mouseleave", tooltipLeaveHandler, true);
  card.addEventListener("touchend", tooltipLeaveHandler, true);
  card._tooltipEnterHandler = tooltipEnterHandler;
  card._tooltipLeaveHandler = tooltipLeaveHandler;
}

// Global variable to track active edit state
let activeEditSession = null;

// Helper function to cancel edit mode for a card
function cancelEditMode(cardTextEl, editButton) {
  if (cardTextEl) {
    try {
      // Restore original content if available
      const storedContent = cardTextEl._originalContent;
      if (storedContent) {
        cardTextEl.innerHTML = storedContent;
      } else {
        // If original content not available, request refresh from server
        const parentCard = cardTextEl.closest('.card');
        const mid = parentCard ? parentCard.id : null;
        if (mid) {
          ws.send(JSON.stringify({
            "message": "REFRESH",
            "mid": mid
          }));
        }
      }

      // Clean up data attribute
      delete cardTextEl._originalContent;

      // Reset edit button icon if provided
      if (editButton) {
        const icon = editButton.querySelector("i");
        if (icon) {
          icon.classList.remove("fa-check", "fa-spinner", "fa-spin", "icon-active");
          icon.classList.add("fa-pen-to-square");
        }
      }

      // Clean up any edit-specific event listeners
      cleanupCardTextListeners(cardTextEl);

      // Clear the global edit session reference
      if (activeEditSession &&
          activeEditSession.cardText &&
          activeEditSession.cardText === cardTextEl) {
        activeEditSession = null;
      }
    } catch (err) {
      console.error("Error during edit mode cancellation:", err);
      try {
        cardTextEl.querySelectorAll('.inline-edit-textarea, .cancel-edit, .save-edit').forEach(el => el.remove());
        if (editButton) {
          const icon = editButton.querySelector("i");
          if (icon) {
            icon.classList.remove("fa-check", "fa-spinner", "fa-spin", "icon-active");
            icon.classList.add("fa-pen-to-square");
          }
        }
      } catch (e) {
        console.error("Failed to reset UI after error:", e);
      }

      activeEditSession = null;
    }
  }
}

// Helper function to clean up edit-specific event listeners
function cleanupCardTextListeners(cardTextEl) {
  if (cardTextEl) {
    // Remove the buttons and textarea elements (their event listeners are GC'd)
    cardTextEl.querySelectorAll('.cancel-edit, .save-edit').forEach(function(el) {
      // Clone and replace to remove all event listeners
      const clone = el.cloneNode(true);
      if (el.parentNode) el.parentNode.replaceChild(clone, el);
    });

    cardTextEl.querySelectorAll('.inline-edit-textarea').forEach(function(el) {
      const clone = el.cloneNode(true);
      if (el.parentNode) el.parentNode.replaceChild(clone, el);
    });
  }
}

// Function to remove all event listeners - helps prevent memory leaks
function detachEventListeners(card) {
  if (card) {
    // Remove the click handler
    if (card._cardClickHandler) {
      card.removeEventListener("click", card._cardClickHandler);
      delete card._cardClickHandler;
    }

    // Remove tooltip handlers
    if (card._tooltipEnterHandler) {
      card.removeEventListener("mouseenter", card._tooltipEnterHandler, true);
      delete card._tooltipEnterHandler;
    }
    if (card._tooltipLeaveHandler) {
      card.removeEventListener("mouseleave", card._tooltipLeaveHandler, true);
      card.removeEventListener("touchend", card._tooltipLeaveHandler, true);
      delete card._tooltipLeaveHandler;
    }

    // Clean up card text edit button events
    const cardTextEl = card.querySelector(".card-text");
    if (cardTextEl) {
      cleanupCardTextListeners(cardTextEl);
      delete cardTextEl._originalContent;
    }

    // Remove any lingering tooltip effects
    try {
      if (typeof cleanupAllTooltips === 'function') {
        cleanupAllTooltips();
      } else {
        card.querySelectorAll("[title]").forEach(function(el) {
          const tip = bootstrap.Tooltip.getInstance(el);
          if (tip) tip.dispose();
        });
        document.querySelectorAll('[data-bs-original-title]').forEach(function(el) {
          const tip = bootstrap.Tooltip.getInstance(el);
          if (tip) tip.dispose();
        });
        document.querySelectorAll('[data-original-title]').forEach(function(el) {
          const tip = bootstrap.Tooltip.getInstance(el);
          if (tip) tip.dispose();
        });
        document.querySelectorAll('.tooltip').forEach(el => el.remove());
      }
    } catch (e) {
      document.querySelectorAll('.tooltip').forEach(el => el.remove());
    }
  }
}
