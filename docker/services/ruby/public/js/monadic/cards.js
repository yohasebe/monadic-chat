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
      // Store card data
      $("#deleteConfirmation").data({
        "mid": mid,
        "messageIndex": messageIndex
      });
      
      // Update modal contents
      const text = messages[messageIndex].text || "";
      const truncatedText = text.length > 100 ? text.substring(0, 100) + "..." : text;
      $("#messageToDelete").text(truncatedText);
      
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
      // Create a temporary DOM element to safely parse HTML
      const tempDiv = document.createElement('div');
      // Use textContent to prevent execution of scripts when extracting HTML
      tempDiv.textContent = content.html();
      // Safely parse and extract content
      const safeHtml = tempDiv.innerHTML;
      
      // Remove <style> and <script> tags using regex
      let cleanText = safeHtml.replace(/<style>[\s\S]*?<\/style>/g, "");
      cleanText = cleanText.replace(/<script>[\s\S]*?<\/script>/g, "");
      
      // Get only content before any <hr> tag, if present
      const hrSplit = cleanText.split(/<hr\s*\/?>/);
      const firstPart = hrSplit.length > 0 ? hrSplit[0] : cleanText;
      
      // Use DOMParser to safely extract text content
      const parser = new DOMParser();
      const doc = parser.parseFromString(firstPart, 'text/html');
      text = doc.body.textContent || "";
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
    const text = $card.find(".card-text").text();
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

    // Handle attached files
    if (currentMessage.images) {
      images = [...currentMessage.images];
      updateFileDisplay(images);
    } else {
      images = [];
      $("#image-used").empty();
    }

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

    const confirmed = confirm(`Are you sure to edit this message?\nThis will delete all the messages after it.`);
    if (confirmed) {
      $this.find("i").removeClass("fa-square-pen").addClass("fa-check").css("color", "#DC4C64");
      $("#message").val(text).trigger("input").focus();

      let role = currentMessage.role;
      if (role !== "user") {
        role = "sample-" + role;
      }
      $("#select-role").val(role).trigger("change");

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
    }
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
