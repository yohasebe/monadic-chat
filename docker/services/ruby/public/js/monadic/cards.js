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
    // Don't escape HTML for system messages as they may contain formatted content
    // Only escape if the content looks like plain text (no HTML tags)
    if (html.indexOf('<') === -1 && html.indexOf('>') === -1) {
      replaced_html = escapeHtml(html).replace(/\n/g, "<br>");
    } else {
      replaced_html = html;
    }
  } else {
    replaced_html = html.replaceAll("/lab/tree/", "/lab/tree/");
  }

  // add "?dummy=TIMESTAMP" to the end of the URL to prevent the browser from caching the image
  replaced_html = replaced_html.replace(/<img src="([^"]+)"/g, '<img src="$1?dummy=' + Date.now() + '"');

  let className, roleIcon, roleIconColor;
  if (role === "user") {
    className = "role-user";
    roleIcon = "fa-face-smile";
    roleIconColor = "#4CACDC"; // User color
  } else if (role === "assistant") {
    className = "role-assistant";
    roleIcon = "fa-robot";
    roleIconColor = "#DC4C64"; // Assistant color
  } else if (role === "info") {
    className = "role-info";
    roleIcon = "fa-info-circle";
    roleIconColor = "#2196f3"; // Info color
  } else {
    className = "role-system";
    roleIcon = "fa-bars";
    roleIconColor = "#22ad50"; // System color
  }

  let image_data = "";
  if (images && images.length > 0) {
    // Group mask images with their original images
    const imageMap = new Map();
    const maskImages = [];
    
    // First pass - identify all mask images and base images
    images.forEach(image => {
      if (image.is_mask || (image.title && image.title.startsWith("mask__"))) {
        // Store mask images separately with reference to their base image
        maskImages.push(image);
      } else {
        // Store base images in a map with their title as key
        imageMap.set(image.title, image);
      }
    });
    
    // Second pass - create HTML for each base image, with its mask if available
    const renderedImages = [];
    
    // Process regular images first
    imageMap.forEach((image, title) => {
      // Check if this image has a mask
      const maskImage = maskImages.find(mask => 
        mask.mask_for === title || 
        (mask.title && mask.title.includes(title.replace(/\.[^.]+$/, "")))
      );
      
      if (maskImage) {
        // This image has a mask - render as overlay
        
        renderedImages.push(`
          <div class="mask-overlay-container mb-3">
            <img class='base-image' alt='${image.title}' src='${image.data}' />
            <img class='mask-overlay' alt='${maskImage.title}' src='${maskImage.display_data || maskImage.data}' style="opacity: 0.6;" />
            <div class="mask-overlay-label">MASK</div>
          </div>
        `);
      } else if (image.type === 'application/pdf') {
        // PDF file
        renderedImages.push(`
          <div class="pdf-preview mb-3">
          <i class="fas fa-file-pdf text-danger"></i>
          <span class="ms-2">${image.title}</span>
          </div>
        `);
      } else {
        // Regular image without mask
        renderedImages.push(`
          <img class='base64-image mb-3' src='${image.data}' alt='${image.title}' style='max-width: 100%; height: auto;' />
        `);
      }
    });
    
    // Finally, add any mask images that don't have a matching base image
    maskImages.forEach(mask => {
      if (!renderedImages.some(html => html.includes(`alt='${mask.title}'`))) {
        // Only if not already rendered
        if (!imageMap.has(mask.mask_for)) {
          renderedImages.push(`
            <img class='base64-image mb-3' src='${mask.display_data || mask.data}' alt='${mask.title}' style='max-width: 100%; height: auto;' />
          `);
        }
      }
    });
    
    image_data = renderedImages.join("");
  }

  // Update badge with colored icon (mobile-friendly)
  const enhancedBadge = badge.replace(/class=['"]text-secondary['"]/g, `class="text-secondary"`);
  const enhancedBadge2 = enhancedBadge.replace(/<i class=['"]fas (fa-face-smile|fa-robot|fa-bars)['"]><\/i>/g, 
    `<i class="fas ${roleIcon}" style="color: ${roleIconColor};"></i>`);

  // Create the card element with the mid attribute
  const card = $(`
    <div class="card mt-3" id="${mid}"> 
    <div class="card-header p-2 ps-3 d-flex justify-content-between">
    <div class="fs-5 card-title mb-0">${enhancedBadge2}</div>
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
    <div class="card-body ${className}">
    <div class="card-text">${replaced_html}${image_data}</div>
    </div>
    </div>
    `);

  // Check if this card already exists (could happen during refresh/updates)
  if (mid !== "" && $(`#${mid}`).length > 0) {
    // Remove existing card to avoid duplicates
    $(`#${mid}`).remove();
  }

  // Attach event listeners
  attachEventListeners(card);

  // Add to mids Set if mid is not empty
  if (mid !== "") {
    mids.add(mid);
  }

  return card;
}

// Function to attach all event listeners - uses namespaced events for easy cleanup
function attachEventListeners($card) {
  // First ensure we remove any existing listeners to prevent duplicates
  detachEventListeners($card);
  
  // Direct event handler for the delete button
  // This will intercept the click before it bubbles up to the card handler
  $card.find(".func-delete").on("click.cardEvent", function(event) {
    // Stop event propagation to prevent other handlers from firing
    event.stopPropagation();
    
    const $parentCard = $(this).closest(".card");
    const mid = $parentCard.attr('id');
    
    if (!mid) return; // Safety check
    
    // Check if this card is currently in edit mode and cancel it first
    if (activeEditSession && activeEditSession.mid === mid) {
      // Cancel the edit mode before proceeding with delete
      cancelEditMode(activeEditSession.cardText, activeEditSession.editButton);
      activeEditSession = null; // Clear the global reference
    }
    
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
    
    // For system messages, treat the same as other messages
    if ($parentCard.find(".role-system").length > 0) {
      // No special treatment - handle like other messages
    }
    
    // For regular messages, check if it's in the messages array
    if (messageIndex !== -1) {
      // Check if this is the last message in the conversation
      const isLastMessage = messageIndex === messages.length - 1;
      
      // Always show modal for delete confirmation, even for last message
      // Store card data
      $("#deleteConfirmation").data({
        "mid": mid,
        "messageIndex": messageIndex
      });
      
      // Configure modal based on message position
      if (isLastMessage) {
        // If it's the last message, hide the "Delete this and below" button since there's nothing below
        $("#deleteMessageAndSubsequent").hide();
      } else {
        // For messages in the middle, show both options
        $("#deleteMessageAndSubsequent").show();
      }
      
      // Show the modal
      $("#deleteConfirmation").modal("show");
    } else {
      // If no message found, just delete the card
      $parentCard.remove();
      ws.send(JSON.stringify({ "message": "DELETE", "mid": mid }));
      mids.delete(mid);
      
      // Add explicit visual feedback for the user
      setAlert("<i class='fas fa-circle-check'></i> Message deleted", "success");
    }
  });
  
  $card.on("click.cardEvent", ".func-play", function () {
    // Get the actual parent card of the clicked button
    const $currentCard = $(this).closest('.card');
    
    // Use the more robust tooltip cleanup method
    if (typeof cleanupAllTooltips === 'function') {
      cleanupAllTooltips();
    } else {
      $(this).tooltip('hide');
      $('.tooltip').remove();
    }
    
    // Stop any current TTS playback to prevent double playback
    if (typeof ttsStop === 'function') {
      ttsStop();
    }

    // Show TTS-specific spinner
    $("#monadic-spinner")
      .find("span i")
      .removeClass("fa-comment")
      .addClass("fa-headphones");
    $("#monadic-spinner")
      .find("span")
      .html('<i class="fas fa-headphones fa-pulse"></i> Processing audio');
    $("#monadic-spinner").show();

    const content = $currentCard.find(".card-text");
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
    
    // Get the message ID if available
    const mid = $currentCard.attr('id') || '';
    
    // Send a PLAY_TTS message to have the server handle sentence splitting and TTS
    const ttsProvider = $("#tts-provider").val();
    let ttsVoice;
    
    if (ttsProvider === "elevenlabs" || ttsProvider === "elevenlabs-flash" || ttsProvider === "elevenlabs-multilingual") {
      ttsVoice = $("#elevenlabs-tts-voice").val();
    } else if (ttsProvider === "webspeech") {
      ttsVoice = $("#webspeech-voice").val();
    } else if (ttsProvider === "gemini-flash" || ttsProvider === "gemini-pro") {
      ttsVoice = $("#gemini-tts-voice").val();
    } else {
      ttsVoice = $("#tts-voice").val();
    }
    
    const ttsSpeed = $("#tts-speed").val();
    
    // Send websocket message for server-side TTS processing
    const ttsMessage = {
      message: "PLAY_TTS",
      text: text,
      tts_provider: ttsProvider,
      tts_voice: ttsVoice,
      elevenlabs_tts_voice: $("#elevenlabs-tts-voice").val(),
      gemini_tts_voice: $("#gemini-tts-voice").val(),
      tts_speed: ttsSpeed,
      mid: mid
    };
    
    // Small delay to ensure previous TTS is stopped before starting new one
    setTimeout(() => {
      ws.send(JSON.stringify(ttsMessage));
    }, 50);
  });

  $card.on("click.cardEvent", ".func-stop", function () {
    // Use the more robust tooltip cleanup method
    if (typeof cleanupAllTooltips === 'function') {
      cleanupAllTooltips();
    } else {
      $(this).tooltip('hide');
      $('.tooltip').remove();
    }
    
    // Hide the spinner and reset it back to default state
    $("#monadic-spinner").hide();
    // Reset spinner to default state for other operations
    $("#monadic-spinner")
      .find("span")
      .html('<i class="fas fa-comment fa-pulse"></i> Starting');
    
    // Stop frontend TTS
    ttsStop();
    
    // Send stop signal to backend as well
    if (typeof ws !== 'undefined' && ws && ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({ message: "STOP_TTS" }));
    }
    
    // Reset response state and alert message
    if (typeof window.responseStarted !== 'undefined') {
      window.responseStarted = false;
    }
    if (typeof setAlert === 'function') {
      setAlert("<i class='fa-solid fa-circle-check'></i> Ready to start", "success");
    }
  });

  $card.on("click.cardEvent", ".func-copy", async function () {
    // Use the more robust tooltip cleanup method
    if (typeof cleanupAllTooltips === 'function') {
      cleanupAllTooltips();
    } else {
      $(this).tooltip('hide');
      $('.tooltip').remove();
    }
    
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
    
    try {
      // Copy text to clipboard
      // Use document.execCommand directly
      const textarea = document.createElement('textarea');
      textarea.value = text;
      textarea.style.position = 'fixed';  // Fixed position to prevent scrolling on mobile
      textarea.style.opacity = 0;
      document.body.appendChild(textarea);
      textarea.select();
      
      const success = document.execCommand('copy');
      document.body.removeChild(textarea);
      
      if (!success) {
        throw new Error('execCommand copy failed');
      }
      
      // Show success indicator
      const icon = $this.find("i");
      icon.removeClass("fa-copy").addClass("fa-check").css("color", "#DC4C64");
      
      // Return to normal state after delay
      setTimeout(() => {
        icon.removeClass("fa-check").addClass("fa-copy").css("color", "");
      }, 1000);
    } catch (err) {
      console.error("Failed to copy text: ", err);
      
      // Try fallback methods if execCommand fails
      try {
        if (window.electronAPI && typeof window.electronAPI.writeClipboard === 'function') {
          window.electronAPI.writeClipboard(text);
        } else if (navigator.clipboard && navigator.clipboard.writeText) {
          await navigator.clipboard.writeText(text);
        } else {
          throw new Error('No clipboard API available');
        }
        
        // Show success indicator
        const icon = $this.find("i");
        icon.removeClass("fa-copy").addClass("fa-check").css("color", "#DC4C64");
        
        // Return to normal state after delay
        setTimeout(() => {
          icon.removeClass("fa-check").addClass("fa-copy").css("color", "");
        }, 1000);
      } catch (fallbackErr) {
        console.error("All clipboard methods failed: ", fallbackErr);
        
        // Show error indicator
        const icon = $this.find("i");
        icon.removeClass("fa-copy").addClass("fa-xmark").css("color", "#DC4C64");
        
        // Return to normal state after delay
        setTimeout(() => {
          icon.removeClass("fa-xmark").addClass("fa-copy").css("color", "");
        }, 1000);
      }
    }
  });

  $card.on("click.cardEvent", ".func-edit", function () {
    // Use the more robust tooltip cleanup method
    if (typeof cleanupAllTooltips === 'function') {
      cleanupAllTooltips();
    } else {
      $(this).tooltip('hide');
      $('.tooltip').remove();
    }
    
    const $this = $(this);
    const mid = $card.attr('id');
    const messageIndex = messages.findIndex((m) => m.mid === mid);
    const currentMessage = messages[messageIndex];

    // Check if any message is currently being edited and handle it first
    const $existingEditArea = $(".inline-edit-textarea");
    if ($existingEditArea.length > 0) {
      // Find the current active edit card
      const $activeEditCard = $existingEditArea.closest(".card-text");
      
      // Get the cancel button from the active edit card
      const $cancelBtn = $activeEditCard.find(".cancel-edit");
      if ($cancelBtn.length > 0) {
        // Trigger the cancel event to restore the original content
        $cancelBtn.trigger("click");
      } else {
        // If we can't find the cancel button but there's an edit area,
        // use our helper function to cancel edit mode
        const $editButton = $activeEditCard.closest(".card").find(".func-edit");
        cancelEditMode($activeEditCard, $editButton);
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

    // Check if this is the last message - either by message array index or by DOM position
    const isLastMessage = messageIndex === messages.length - 1;
    // Also check if this is the last card in the DOM (important for sample messages)
    const isLastDisplayedCard = $card.is($("#discourse .card:last-child"));
    
    if (isLastMessage || isLastDisplayedCard) {
      // Copy text to the message textarea instead of inline editing
      $("#message").val(text);
      
      // Set the appropriate role in the selector based on the current message role
      if (currentMessage.role === "user") {
        $("#select-role").val("user");
      } else if (currentMessage.role === "assistant") {
        $("#select-role").val("sample-assistant");
      } else if (currentMessage.role === "system") {
        $("#select-role").val("sample-system");
      }
      
      // If message has images, restore them in the current images array
      if (currentMessage.images && Array.isArray(currentMessage.images) && currentMessage.images.length > 0) {
        // Clear existing images except PDFs
        images = images.filter(img => img.type === 'application/pdf');
        
        // Process each image in the message
        const messageImages = [...currentMessage.images];
        const baseImages = [];
        const maskImages = [];
        
        // First, categorize images into base and mask images
        messageImages.forEach(imageData => {
          // Create a fresh copy to avoid reference issues
          const imageCopy = {...imageData};
          
          // Check if this is a mask image
          if (imageCopy.is_mask || (imageCopy.title && imageCopy.title.startsWith("mask__"))) {
            maskImages.push(imageCopy);
          } else {
            baseImages.push(imageCopy);
          }
        });
        
        // Add base images first
        baseImages.forEach(baseImage => {
          images.push(baseImage);
        });
        
        // Then add mask images and set currentMaskData if applicable
        maskImages.forEach(maskImage => {
          // Add to images array 
          images.push(maskImage);
          
          // Set as current mask if it has a base image reference
          if (maskImage.mask_for) {
            const hasBaseImage = baseImages.some(img => img.title === maskImage.mask_for);
            if (hasBaseImage) {
              // Set as the current active mask
              window.currentMaskData = maskImage;
            }
          }
        });
        
        // Update the display to show the restored images
        updateFileDisplay(images);
      }
      
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
    
    // Store original content
    const originalContent = $cardText.html();
    // Store the original content for retrieval
    $cardText.data('originalContent', originalContent);
    
    // Extract text content only (without images)
    const $textContent = $cardText.find('p').first();
    const $images = $cardText.find('.pdf-preview, .base64-image, .image-container, .mask-overlay-container');
    
    // Replace only the text part with the textarea
    if ($textContent.length > 0) {
      $textContent.replaceWith($editArea);
    } else {
      // If no paragraph found, insert textarea at the beginning
      $cardText.prepend($editArea);
    }
    
    // Update the global edit session tracker
    activeEditSession = {
      cardText: $cardText,
      editButton: $this,
      mid: mid,
      messageIndex: messageIndex
    };
    
    // Create save and cancel buttons with consistent styling for all roles
    const $buttonRow = $(`
      <div class="d-flex justify-content-end">
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
    
    // Clean up any existing handlers first to prevent duplicates
    $cardText.off('click', '.cancel-edit');
    $cardText.off('click', '.save-edit');
    
    // Handle cancel button
    $cardText.on('click', '.cancel-edit', function(e) {
      e.stopPropagation();
      // Use our helper function to handle edit cancellation
      cancelEditMode($cardText, $this);
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
        
        // Preserve existing images/PDFs by extracting them first
        const $existingImages = $cardText.find('.pdf-preview, .base64-image, .image-container, .mask-overlay-container').detach();
        
        // Update the text content
        $cardText.html("<p>" + displayText + "</p>");
        
        // Re-append the images/PDFs
        if ($existingImages.length > 0) {
          $cardText.append($existingImages);
        }
        
        // Change the icon back to the edit icon immediately for user messages
        $this.find("i").removeClass("fa-check").addClass("fa-pen-to-square").css("color", "");
      } else if (currentMessage.role === "assistant") {
        // For assistant messages, temporarily show the raw text like user messages
        // The server will send back properly formatted HTML
        const displayText = newText.replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\n/g, "<br>");
        
        // Preserve existing images/PDFs by extracting them first
        const $existingImages = $cardText.find('.pdf-preview, .base64-image, .image-container, .mask-overlay-container').detach();
        
        // Update the text content
        $cardText.html("<p>" + displayText + "</p>");
        
        // Re-append the images/PDFs
        if ($existingImages.length > 0) {
          $cardText.append($existingImages);
        }
      } else if (currentMessage.role === "system") {
        // System messages are escaped HTML with line breaks preserved
        const displayText = newText.replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\n/g, "<br>");
        
        // Preserve existing images/PDFs by extracting them first
        const $existingImages = $cardText.find('.pdf-preview, .base64-image, .image-container, .mask-overlay-container').detach();
        
        // Update the text content
        $cardText.html(displayText);
        
        // Re-append the images/PDFs
        if ($existingImages.length > 0) {
          $cardText.append($existingImages);
        }
        
        // Change the icon back to the edit icon immediately for system messages
        $this.find("i").removeClass("fa-check").addClass("fa-pen-to-square").css("color", "");
      }
      
      // Clean up the data attribute
      $cardText.removeData('originalContent');
      
      // Clean up any edit-specific event listeners to prevent memory leaks
      cleanupCardTextListeners($cardText);
      
      // Notify the server about the change (without deleting the message)
      // The server will send back properly formatted HTML through the websocket
      
      // For inline editing, we don't modify the images - just update the text content
      // Images are only modified when editing the last message through the message input area
      
      // Create edit message without changing the images
      const editMessage = { 
        "message": "EDIT", 
        "mid": mid, 
        "content": newText,
        "role": currentMessage.role
      };
      
      // Keep existing images if available
      if (currentMessage.images && Array.isArray(currentMessage.images) && currentMessage.images.length > 0) {
        editMessage.images = [...currentMessage.images];
      }
      
      ws.send(JSON.stringify(editMessage));
      
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
  
  // Check if this card is currently in edit mode and cancel it first
  if (activeEditSession && activeEditSession.mid === mid) {
    // Cancel the edit mode before proceeding with delete
    cancelEditMode(activeEditSession.cardText, activeEditSession.editButton);
    activeEditSession = null; // Clear the global reference
  }
  
  // First detach event listeners to prevent memory leaks
  detachEventListeners($card);
  
  // Properly clean up all tooltips to prevent orphaned tooltip elements
  if (typeof cleanupAllTooltips === 'function') {
    cleanupAllTooltips();
  } else {
    // Fallback cleanup method if global function isn't available
    $card.find("[title]").tooltip('hide').tooltip('dispose');
    $('.tooltip').remove();
  }
  
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
window.createCard = createCard;
window.attachEventListeners = attachEventListeners;
window.detachEventListeners = detachEventListeners;
window.cancelEditMode = cancelEditMode;
window.cleanupCardTextListeners = cleanupCardTextListeners;

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    createCard,
    attachEventListeners,
    detachEventListeners,
    cancelEditMode,
    cleanupCardTextListeners,
    deleteSystemMessage,
    deleteMessageAndSubsequent,
    deleteMessageOnly
  };
}
window.deleteMessageAndSubsequent = function(mid, messageIndex) {
  // First check if this is a system message
  const $card = $(`#${mid}`);
  
  if ($card.find(".role-system").length > 0) {
    // Use specialized system message deletion
    deleteSystemMessage(mid, messageIndex);
    return;
  }
  
  // Check if this card is currently in edit mode and cancel it first
  if (activeEditSession && activeEditSession.mid === mid) {
    // Cancel the edit mode before proceeding with delete
    cancelEditMode(activeEditSession.cardText, activeEditSession.editButton);
    activeEditSession = null; // Clear the global reference
  }
  
  // Regular message handling continues...
  // Properly clean up all tooltips to prevent orphaned tooltip elements
  if (typeof cleanupAllTooltips === 'function') {
    cleanupAllTooltips();
  } else {
    // Fallback cleanup method if global function isn't available
    $card.find("[title]").tooltip('hide').tooltip('dispose');
    $('.tooltip').remove();
  }
  
  // First detach event listeners from the current card
  detachEventListeners($card);
  
  // Delete all subsequent messages
  const subsequentMessages = messages.slice(messageIndex + 1);
  subsequentMessages.forEach((m) => {
    const $subsequentCard = $(`#${m.mid}`);
    // Detach event listeners before removal
    if ($subsequentCard.length) {
      detachEventListeners($subsequentCard);
      $subsequentCard.remove();
    }
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
  
  // Properly clean up all tooltips to prevent orphaned tooltip elements
  if (typeof cleanupAllTooltips === 'function') {
    cleanupAllTooltips();
  } else {
    // Fallback cleanup method if global function isn't available
    $card.find("[title]").tooltip('hide').tooltip('dispose');
    $('.tooltip').remove();
  }
  
  // Special case: handle system role messages with our specialized function
  if ($card.find(".role-system").length > 0) {
    // Use the specialized system message deletion to maintain consistency
    deleteSystemMessage(mid, messageIndex);
    return;
  }
  
  // Check if this card is currently in edit mode and cancel it first
  if (activeEditSession && activeEditSession.mid === mid) {
    // Cancel the edit mode before proceeding with delete
    cancelEditMode(activeEditSession.cardText, activeEditSession.editButton);
    activeEditSession = null; // Clear the global reference
  }
  
  // Detach event listeners before doing anything else
  detachEventListeners($card);
  
  // Check if message exists in the array
  if (messageIndex === -1 || !messages[messageIndex]) {
    // Just delete the card without touching the messages array
    $card.remove();
    ws.send(JSON.stringify({ "message": "DELETE", "mid": mid }));
    mids.delete(mid);
    return;
  }
  
  // Remove the extra confirmation dialog to simplify the deletion process
  
  // Remove just this message, preserving subsequent messages
  messages.splice(messageIndex, 1);
  $card.remove();
  ws.send(JSON.stringify({ "message": "DELETE", "mid": mid }));
  mids.delete(mid);
};

  // Combine mouse events into a single listener
  $card.on("mouseenter.cardEvent", ".func-play, .func-stop, .func-copy, .func-delete, .func-edit", function () {
    $(this).tooltip('show');
    const $icon = $(this).find("i");
    $icon.css("color", "#DC4C64");
  });

  $card.on("mouseleave.cardEvent click.cardEvent touchend.cardEvent", ".func-play, .func-stop, .func-copy, .func-delete, .func-edit", function (event) {
    $(this).tooltip('hide');
    
    // Reset color only on mouseleave, not on click or touchend for iOS
    if (event.type === "mouseleave") {
      const $icon = $(this).find("i");
      $icon.css("color", "");
    }
    
    // For iOS devices, handle special case for play/stop buttons
    const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) || 
                  (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
    
    if (isIOS && (event.type === "click" || event.type === "touchend")) {
      // Get the specific action (play or stop)
      const isPlayButton = $(this).hasClass("func-play");
      const isStopButton = $(this).hasClass("func-stop");
      
      if (isPlayButton || isStopButton) {
        const $icon = $(this).find("i");
        // Add timeout to reset icon color after action completes
        setTimeout(() => {
          $icon.css("color", "");
        }, 500);
      }
    }
  });
}

// Global variable to track active edit state
let activeEditSession = null;

// Helper function to cancel edit mode for a card
function cancelEditMode($cardText, $editButton) {
  if ($cardText && $cardText.length) {
    try {
      // Restore original content if available
      const storedContent = $cardText.data('originalContent');
      if (storedContent) {
        $cardText.html(storedContent);
      } else {
        // If original content not available, request refresh from server
        const $card = $cardText.closest('.card');
        const mid = $card.attr('id');
        if (mid) {
          ws.send(JSON.stringify({ 
            "message": "REFRESH", 
            "mid": mid
          }));
        }
      }
      
      // Clean up data attribute
      $cardText.removeData('originalContent');
      
      // Reset edit button icon if provided
      if ($editButton && $editButton.length) {
        $editButton.find("i")
          .removeClass("fa-check fa-spinner fa-spin")
          .addClass("fa-pen-to-square")
          .css("color", "");
      }
      
      // Clean up any edit-specific event listeners
      cleanupCardTextListeners($cardText);
      
      // Clear the global edit session reference
      if (activeEditSession && 
          activeEditSession.cardText && 
          activeEditSession.cardText.is($cardText)) {
        activeEditSession = null;
      }
    } catch (err) {
      console.error("Error during edit mode cancellation:", err);
      // Still attempt to reset UI state even if error occurs
      try {
        $cardText.find('.inline-edit-textarea, .cancel-edit, .save-edit').remove();
        if ($editButton && $editButton.length) {
          $editButton.find("i")
            .removeClass("fa-check fa-spinner fa-spin")
            .addClass("fa-pen-to-square")
            .css("color", "");
        }
      } catch (e) {
        // Last resort fallback - ignore any errors in the error handler
        console.error("Failed to reset UI after error:", e);
      }
      
      // Clear the global edit session reference
      activeEditSession = null;
    }
  }
}

// Helper function to clean up edit-specific event listeners
function cleanupCardTextListeners($cardText) {
  if ($cardText && $cardText.length) {
    // Remove click handlers for edit operation buttons
    $cardText.off('click', '.cancel-edit');
    $cardText.off('click', '.save-edit');
    
    // Remove listeners from the buttons themselves
    $cardText.find('.cancel-edit, .save-edit').off();
    
    // Clean up input event listeners from any textareas
    $cardText.find('.inline-edit-textarea').off('input');
    
    // Ensure the buttons are completely removed to prevent memory leaks
    $cardText.find('.cancel-edit, .save-edit, .inline-edit-textarea').each(function() {
      $(this).data('events', null);
    });
  }
}

// Function to remove all event listeners - helps prevent memory leaks
function detachEventListeners($card) {
  // Remove all namespaced event listeners
  if ($card && $card.length) {
    // Remove card-level events
    $card.off(".cardEvent");
    
    // Remove events from child elements
    $card.find(".func-delete, .func-play, .func-stop, .func-copy, .func-edit").off(".cardEvent");
    
    // Clean up card text edit button events
    const $cardText = $card.find(".card-text");
    cleanupCardTextListeners($cardText);
    
    // Clean up any stored data attributes
    $card.find(".card-text").removeData('originalContent');
    
    // Remove any lingering tooltip effects
    try {
      // Use the global cleanup function if available
      if (typeof cleanupAllTooltips === 'function') {
        cleanupAllTooltips();
      } else {
        // Otherwise use a more aggressive approach
        $card.find("[title]").tooltip("dispose");
        $('[data-bs-original-title]').tooltip('dispose');
        $('[data-original-title]').tooltip('dispose');
        $('.tooltip').remove();
      }
    } catch (e) {
      // If there's an error in tooltip disposal, force remove all tooltips
      $('.tooltip').remove();
    }
  }
}