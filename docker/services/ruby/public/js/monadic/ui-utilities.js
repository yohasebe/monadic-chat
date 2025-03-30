/**
 * UI Utility functions for Monadic Chat
 * This module contains functions related to UI manipulation and user interface handling
 */

/**
 * Resizes a textarea element based on its content
 * @param {HTMLElement} textarea - The textarea element to resize
 * @param {number} initialHeight - The minimum height for the textarea
 */
function autoResize(textarea, initialHeight) {
  textarea.style.height = 'auto';
  const newHeight = Math.max(textarea.scrollHeight, initialHeight);
  textarea.style.height = newHeight + 'px';
}

/**
 * Sets up a textarea with automatic resizing based on content
 * @param {HTMLElement} textarea - The textarea element to set up
 * @param {number} initialHeight - The minimum height for the textarea
 */
function setupTextarea(textarea, initialHeight) {
  let isIMEActive = false;

  textarea.style.height = initialHeight + 'px';

  textarea.addEventListener('compositionstart', function() {
    isIMEActive = true;
  });

  textarea.addEventListener('compositionend', function() {
    isIMEActive = false;
    autoResize(textarea, initialHeight);
  });

  textarea.addEventListener('input', function() {
    if (!isIMEActive) {
      autoResize(textarea, initialHeight);
    }
  });

  textarea.addEventListener('focus', function() {
    autoResize(textarea, initialHeight);
  });

  autoResize(textarea, initialHeight);
}

/**
 * Adjusts user interface elements based on screen size and viewport
 */
function adjustScrollButtons() {
  const mainPanel = $("#main");
  const mainHeight = mainPanel.height();
  const mainScrollHeight = mainPanel.prop("scrollHeight");
  const mainScrollTop = mainPanel.scrollTop();
  
  // Get scroll button elements
  const backToTopBtn = $("#back_to_top");
  const backToBottomBtn = $("#back_to_bottom");
  
  // Show/hide the scroll to top button
  if (mainScrollTop > mainHeight / 2) {
    if (backToTopBtn.show) backToTopBtn.show();
  } else {
    if (backToTopBtn.hide) backToTopBtn.hide();
  }
  
  // Show/hide the scroll to bottom button
  if (mainScrollHeight - mainScrollTop - mainHeight > mainHeight / 2) {
    if (backToBottomBtn.show) backToBottomBtn.show();
  } else {
    if (backToBottomBtn.hide) backToBottomBtn.hide();
  }
}

/**
 * Sets up tooltips for specific UI elements
 * @param {jQuery} container - Container element to attach tooltips to
 */
function setupTooltips(container) {
  container.tooltip({
    selector: '.card-header [title]',
    delay: { show: 0, hide: 0 },
    show: 100,
    container: 'body' // Place tooltips in body for easier management
  });
}

/**
 * Removes all tooltip elements from the DOM
 * Helps prevent memory leaks from lingering tooltips
 */
function cleanupAllTooltips() {
  $('.tooltip').remove(); // Directly remove all tooltip elements
  $('[data-bs-original-title]').tooltip('dispose'); // Bootstrap 5
  $('[data-original-title]').tooltip('dispose'); // Bootstrap 4
}

/**
 * Adjusts image upload button availability based on selected model
 * @param {string} selectedModel - The currently selected AI model
 */
function adjustImageUploadButton(selectedModel) {
  if (!modelSpec || !selectedModel) return;
  
  const modelData = modelSpec[selectedModel];
  const imageFileElement = $("#image-file");
  
  if (modelData && modelData.vision_capability) {
    // Enable the button
    imageFileElement.prop("disabled", false);
    
    // Update button text based on PDF support
    const isPdfEnabled = /sonnet|gemini|4o|4o-mini|o1|gpt-4\.5/.test(selectedModel);
    
    if (isPdfEnabled) {
      imageFileElement.html('<i class="fas fa-file"></i> Use Image/PDF');
    } else {
      imageFileElement.html('<i class="fas fa-image"></i> Use Image');
    }
    
    if (imageFileElement.show) {
      imageFileElement.show();
    }
  } else {
    imageFileElement.prop("disabled", true);
    if (imageFileElement.hide) {
      imageFileElement.hide();
    }
  }
}

// Export functions for CommonJS environments
try {
  module.exports = {
    autoResize,
    setupTextarea,
    adjustScrollButtons,
    setupTooltips,
    cleanupAllTooltips,
    adjustImageUploadButton
  };
} catch (e) {
  // In browser environment, exports will be attached to window
  console.log('Running in browser environment, modules will be attached to window object');
}