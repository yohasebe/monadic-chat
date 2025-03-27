// Use a Set for faster searching
const mids = new Set();

function escapeHtml(unsafe)
{
    if (unsafe === null || unsafe === undefined) {
        return "";
    }

    return unsafe
         .replace(/&/g, "&amp;")
         .replace(/</g, "&lt;")
         .replace(/>/g, "&gt;")
         .replace(/"/g, "&quot;")
         .replace(/'/g, "&#039;");
 }

function createCard(role, badge, html, _lang = "en", mid = "", status = true, images = [], _monadic = false) {
  const status_class = status === true ? "active" : "";

  // Fix jupyter notebook URL issue
  let replaced_html;
  if (role === "system") {
    replaced_html = escapeHtml(html);
  } else {
    replaced_html = html.replaceAll("/lab/tree/", "/lab/tree/");
  }

  // add "?dummy=TIMESTAMP" to the end of the URL to prevent the browser from caching the image
  replaced_html = replaced_html.replace(/<img src="([^"]+)"/g, '<img src="$1?dummy=' + Date.now() + '"');

  let className;
  if (role === "user") {
    className = "role-user";
  } else if (role === "assistant") {
    className = "role-assistant";
  } else {
    className = "role-system";
  }

  let image_data = "";
  if (images && images.length > 0) {
    image_data = images.map((image) => {
      if (image.type === 'application/pdf') {
        return `
          <div class="pdf-preview mb-3">
          <i class="fas fa-file-pdf text-danger"></i>
          <span class="ms-2">${image.title}</span>
          </div>
          `;
      } else {
        return `<img class='base64-image mb-3' src='${image.data}' alt='${image.title}' style='max-width: 100%; height: auto;' />`;
      }
    }).join("");
  }

  // Create the card element with the mid attribute
  const card = $(`
    <div class="card mt-3" id="${mid}"> 
    <div class="card-header p-2 ps-3 d-flex justify-content-between">
    <div class="fs-5 card-title mb-0">${badge}</div>
    ${(!runningOnChrome && !runningOnEdge && !runningOnSafari) ? `
        <div class="me-1 text-secondary d-flex align-items-center">
        <span title="Copy" class="func-copy me-3"><i class="fas fa-copy"></i></span>
        <span title="Delete" class="func-delete me-3" ><i class="fas fa-xmark"></i></span>
        <span title="Edit" class="func-edit me-3"><i class="fas fa-pen-to-square"></i></span>
        <span class="status ${status_class}"></span>
        </div>
        ` : `
        <div class="me-1 text-secondary d-flex align-items-center">
        <span title="Copy" class="func-copy me-3"><i class="fas fa-copy"></i></span>
        <span title="Start TTS" class="func-play me-3"><i class="fas fa-play"></i></span>
        <span title="Stop TTS" class="func-stop me-3"><i class="fas fa-stop"></i></span>
        <span title="Delete" class="func-delete me-3" ><i class="fas fa-xmark"></i></span>
        <span title="Edit" class="func-edit me-3"><i class="fas fa-pen-to-square"></i></span>
        <span class="status ${status_class}"></span>
        </div>
        `}
    </div>
    <div class="card-body ${className} pb-1">
    <div class="card-text">${replaced_html}${image_data}</div>
    </div>
    </div>
    `);

  // Attach event listeners
  attachEventListeners(card);

  // Add to mids Set if mid is not empty
  if (mid !== "") {
    mids.add(mid);
  }

  return card;
}

// Function to attach all event listeners
function attachEventListeners($card) {
  // Direct event handler for the delete button
  // This will intercept the click before it bubbles up to the card handler
  $card.find(".func-delete").on("click", function(event) {
    // Stop event propagation to prevent other handlers from firing
    event.stopPropagation();
    
    const $parentCard = $(this).closest(".card");
    const mid = $parentCard.attr('id');
    
    if (!mid) return; // Safety check
    
    // For all cards, try to find if there's a corresponding message
    const messageIndex = messages.findIndex((m) => m.mid === mid);
    
    // Extra handling for error messages - check multiple error patterns
    const cardText = $parentCard.find(".card-text").text();
    const isApiError = cardText.includes("API ERROR:") || 
                      cardText.includes("Error:") || 
                      cardText.includes("invalid_message") ||
                      cardText.includes("Bad Request");
                      
    if (isApiError) {
      // Just directly detach the element from DOM without animation
      $parentCard.detach();
      
      // Force the browser to redraw
      document.body.offsetHeight;
      
      // Then completely remove it
      $parentCard.remove();
      
      // Also add this in case it's a temporary message
      $(`#${mid}`).remove();
      
      // If the message is in the messages array, remove it
      if (messageIndex !== -1) {
        messages.splice(messageIndex, 1);
      }
      
      // Notify the server
      ws.send(JSON.stringify({ "message": "DELETE", "mid": mid }));
      mids.delete(mid);
      
      // Add explicit visual feedback for the user
      setAlert("<i class='fas fa-circle-check'></i> Message deleted", "success");
      return;
    }
    
    // For system messages that might not be in the messages array
    if ($parentCard.find(".role-system").length > 0) {
      // Get message text for the modal
      const systemText = $parentCard.find(".card-text").text().substring(0, 100) + 
                        ($parentCard.find(".card-text").text().length > 100 ? "..." : "");
      
      // Store card data and any additional info needed for deletion
      $("#deleteConfirmation").data({
        "mid": mid,
        "messageIndex": messageIndex, 
        "isSystemMessage": true,
        "cardSelector": `#${mid}` // Store selector for later use
      });
      
      // Update modal contents
      $("#messageToDelete").text(systemText);
      
      // Show the confirmation modal
      $("#deleteConfirmation").modal("show");
      return;
    }
    
    // For regular messages, show the delete modal
    if (messageIndex !== -1) {
      // Check if this is the last message in the conversation
      const isLastMessage = messageIndex === messages.length - 1;
      const currentMessage = messages[messageIndex];
      
      // Store card data
      $("#deleteConfirmation").data({
        "mid": mid,
        "messageIndex": messageIndex
      });
      
      // Update modal contents
      const text = currentMessage.text || "";
      const truncatedText = text.length > 100 ? text.substring(0, 100) + "..." : text;
      $("#messageToDelete").text(truncatedText);
      
      // For the last message in the conversation that is an assistant or system message,
      // hide the "Delete this and all subsequent messages" button
      if (isLastMessage && (currentMessage.role === "assistant" || currentMessage.role === "system")) {
        $("#deleteMessageAndSubsequent").hide();
      } else {
        $("#deleteMessageAndSubsequent").show();
      }
      
      // Show the modal
      $("#deleteConfirmation").modal("show");
    } else {
      // If no message found, just delete the card
      $parentCard.remove();
      ws.send(JSON.stringify({ "message": "DELETE", "mid": mid }));
      mids.delete(mid);
    }
  });
  
  $card.on("click", ".func-play", function () {
    $(this).tooltip('hide');

    $("#monadic-spinner").show();

    const content = $card.find(".card-text");
    let text;
    try {
      // Direct approach - use text() to get plain text
      // This avoids double-encoding HTML entities
      text = content.text() || "";
      
      // Alternative approach if we need to handle HTML content properly:
      // Clone the element to avoid modifying the original
      const contentClone = content.clone();
      
      // Remove any <style> and <script> tags from the clone
      contentClone.find("style, script").remove();
      
      // Remove content after <hr> if present
      const hrElement = contentClone.find("hr").first();
      if (hrElement.length) {
        hrElement.nextAll().remove();
        hrElement.remove();
      }
      
      // Get the plain text content
      text = contentClone.text() || "";
    } catch (e) {
      console.error("Error extracting text for TTS:", e);
      text = content.text() || "";
    }
    
    text = removeCode(text);
    text = removeMarkdown(text);
    text = removeEmojis(text);
    ttsSpeak(text, true);
  });

  $card.on("click", ".func-stop", function () {
    $(this).tooltip('hide');
    $("#monadic-spinner").hide();
    ttsStop();
  });

  $card.on("click", ".func-copy", function () {
    $(this).tooltip('hide');
    const $this = $(this);
    
    // Get the message ID from the card
    const mid = $card.attr('id');
    
    // Find the message in the messages array
    const messageIndex = messages.findIndex((m) => m.mid === mid);
    let text = "";
    
    if (messageIndex !== -1) {
      // Get the original text from the message object
      const message = messages[messageIndex];
      
      // Use the text property which contains the original content
      if (message.text) {
        text = message.text;
      } else if (message.content) {
        // Fallback if text is not available but content is
        text = message.content;
      }
    }
    
    // If no text was found in the messages array, fall back to the displayed text
    // but with minimal cleanup
    if (!text) {
      const content = $card.find(".card-text");
      const contentClone = content.clone();
      contentClone.find("style, script").remove();
      text = contentClone.text();
    }
    
    navigator.clipboard.writeText(text).then(function () {
      $this.find("i").removeClass("fa-copy").addClass("fa-check").css("color", "#DC4C64");
      setTimeout(function () {
        $this.find("i").removeClass("fa-check").addClass("fa-copy").css("color", "");
      }, 1000);
    }, function () {
      $this.find("i").removeClass("fa-copy").addClass("fa-times").css("color", "#DC4C64");
      setTimeout(function () {
        $this.find("i").removeClass("fa-times").addClass("fa-copy").css("color", "");
      }, 1000);
    });
  });

  $card.on("click", ".func-edit", function () {
    $(this).tooltip('hide');
    const $this = $(this);
    const mid = $card.attr('id');
    const messageIndex = messages.findIndex((m) => m.mid === mid);
    const currentMessage = messages[messageIndex];

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

    // Check if this is the last message and it's a user message
    const isLastMessage = messageIndex === messages.length - 1;
    const isUserMessage = currentMessage.role === "user";
    
    if (isLastMessage && isUserMessage) {
      // Copy text to the message textarea instead of inline editing
      $("#message").val(text);
      $("#message").focus();
      
      // Remove the card
      deleteMessage(mid);
      
      // No need to create inline editor or notify server - just return
      return;
    }

    // Create an inline editing textarea
    const $cardText = $card.find(".card-text");
    const $editArea = $(`<textarea class="form-control inline-edit-textarea">${text}</textarea>`);
    
    // Style the textarea to match the #message textarea
    $editArea.css({
      'width': '100%',
      'min-height': '100px', 
      'margin-bottom': '10px',
      'white-space': 'pre-wrap',
      'font-family': 'inherit',
      'font-size': '1em',
      'color': '#333',
      'line-height': '1.8',
      'padding': '0.375rem 0.75rem',
      'border': '1px solid #ced4da',
      'border-radius': '0.25rem',
      'overflow-y': 'auto'
    });
    
    // Store original content and hide it
    const originalContent = $cardText.html();
    $cardText.html($editArea);
    
    // Create save and cancel buttons
    const $buttonRow = $(`
      <div class="d-flex justify-content-end mb-2">
        <button class="btn btn-sm btn-secondary me-2 cancel-edit">
          <i class="fas fa-times"></i> Cancel
        </button>
        <button class="btn btn-sm btn-primary save-edit">
          <i class="fas fa-check"></i> Save
        </button>
      </div>
    `);
    
    $cardText.append($buttonRow);
    
    // Focus on the textarea
    $editArea.focus();
    
    // Auto-resize the textarea
    const autoResize = function(textarea) {
      textarea.style.height = 'auto';
      textarea.style.height = (textarea.scrollHeight) + 'px';
    };
    
    $editArea.on('input', function() {
      autoResize(this);
    });
    
    // Trigger initial resize
    autoResize($editArea[0]);
    
    // Handle cancel button
    $cardText.on('click', '.cancel-edit', function(e) {
      e.stopPropagation();
      $cardText.html(originalContent);
      $this.find("i").removeClass("fa-check").addClass("fa-pen-to-square").css("color", "");
    });
    
    // Handle save button
    $cardText.on('click', '.save-edit', function(e) {
      e.stopPropagation();
      
      const newText = $editArea.val();
      
      // Update message in the messages array
      currentMessage.text = newText;
      
      // For user messages, we can update the display directly
      if (currentMessage.role === "user") {
        // Format user text with simple line breaks
        const displayText = newText.replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\n/g, "<br>");
        $cardText.html("<p>" + displayText + "</p>");
        
        // Change the icon back to the edit icon immediately for user messages
        $this.find("i").removeClass("fa-check").addClass("fa-pen-to-square").css("color", "");
      } else {
        // For assistant and system messages, we'll show a loading indicator
        // while we wait for the server to process the markdown and send back the HTML
        $cardText.html("<div class='text-center'><i class='fas fa-circle-notch fa-spin'></i> Processing...</div>");
      }
      
      // Notify the server about the change (without deleting the message)
      // The server will send back properly formatted HTML through the websocket
      ws.send(JSON.stringify({ 
        "message": "EDIT", 
        "mid": mid, 
        "content": newText,
        "role": currentMessage.role
      }));
      
      // Change the icon back to the edit icon (for non-user messages, this will be updated again when the server responds)
      $this.find("i").removeClass("fa-check").addClass("fa-pen-to-square").css("color", "");
    });
    
    // Change the icon to indicate edit mode
    $this.find("i").removeClass("fa-pen-to-square").addClass("fa-check").css("color", "#DC4C64");
  });

  // No duplicate click handler for .func-delete needed
  
// Function to delete system messages with our improved approach
window.deleteSystemMessage = function(mid, messageIndex) {
  // Find the card
  const $card = $(`#${mid}`);
  
  if (!$card.length) {
    return;
  }
  
  // Hide any tooltips
  $card.find(".tooltip").tooltip('hide');
  $('.tooltip').remove();
  
  // Immediately detach from DOM (visually removes it)
  $card.detach();
  
  // Force browser redraw
  document.body.offsetHeight;
  
  // Completely remove
  $card.remove();
  
  // Extra cleanup for any remaining elements
  $(`#${mid}`).remove();
  
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

// Expose these functions globally so they can be called from other scripts
window.deleteMessageAndSubsequent = function(mid, messageIndex) {
  // First check if this is a system message
  const $card = $(`#${mid}`);
  
  if ($card.find(".role-system").length > 0) {
    // Use specialized system message deletion
    deleteSystemMessage(mid, messageIndex);
    return;
  }
  
  // Regular message handling continues...
  // Hide any open tooltips
  $card.find(".tooltip").tooltip('hide');
  
  // Delete all subsequent messages
  const subsequentMessages = messages.slice(messageIndex + 1);
  subsequentMessages.forEach((m) => {
    $(`#${m.mid}`).remove();
    ws.send(JSON.stringify({ "message": "DELETE", "mid": m.mid }));
    mids.delete(m.mid);
  });

  // Delete current message
  messages.splice(messageIndex);
  $card.remove();
  ws.send(JSON.stringify({ "message": "DELETE", "mid": mid }));
  mids.delete(mid);
};

window.deleteMessageOnly = function(mid, messageIndex) {
  // Try to find the card with this mid, even if it's not in the messages array
  const $card = $(`#${mid}`);
  if (!$card.length) {
    console.error("Card not found:", mid);
    return;
  }
  
  // Hide any open tooltips
  $card.find(".tooltip").tooltip('hide');
  
  // Special case: handle system role messages with our specialized function
  if ($card.find(".role-system").length > 0) {
    // Use the specialized system message deletion to maintain consistency
    deleteSystemMessage(mid, messageIndex);
    return;
  }
  
  // Check if message exists in the array
  if (messageIndex === -1 || !messages[messageIndex]) {
    // Just delete the card without touching the messages array
    $card.remove();
    ws.send(JSON.stringify({ "message": "DELETE", "mid": mid }));
    mids.delete(mid);
    return;
  }
  
  // Show a confirmation dialog with clear warning
  const confirmDeletion = confirm(
    "Warning: Deleting just this message may break the role alternation pattern " +
    "(user → assistant → user → assistant) required by some models, " +
    "which could cause API errors.\n\n" +
    "Are you sure you want to delete only this message?"
  );
  
  if (!confirmDeletion) {
    return;
  }
  
  // Remove just this message, preserving subsequent messages
  messages.splice(messageIndex, 1);
  $card.remove();
  ws.send(JSON.stringify({ "message": "DELETE", "mid": mid }));
  mids.delete(mid);
};

  // Combine mouse events into a single listener
  $card.on("mouseenter", ".func-play, .func-stop, .func-copy, .func-delete, .func-edit", function () {
    $(this).tooltip('show');
    const $icon = $(this).find("i");
    $icon.css("color", "#DC4C64");
  });

  $card.on("mouseleave", ".func-play, .func-stop, .func-copy, .func-delete, .func-edit", function () {
    $(this).tooltip('hide');
    const $icon = $(this).find("i");
    $icon.css("color", "");
  });
}
