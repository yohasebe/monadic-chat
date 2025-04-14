/**
 * UI Utility functions for Monadic Chat
 * This module contains functions related to UI manipulation and user interface handling
 */

// AI User toggle functionality has been removed

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
 * Enhanced for iOS compatibility
 */
function adjustScrollButtons() {
  const mainPanel = $("#main");
  // Safe access to dimensions with fallbacks for iOS
  const mainHeight = mainPanel.height() || 0;
  const mainScrollHeight = mainPanel.prop("scrollHeight") || 0;
  const mainScrollTop = mainPanel.scrollTop() || 0;
  
  // Get scroll button elements
  const backToTopBtn = $("#back_to_top");
  const backToBottomBtn = $("#back_to_bottom");
  
  // Standard behavior for all platforms
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
 * Includes error handling for Electron compatibility
 * @param {jQuery} container - Container element to attach tooltips to
 */
function setupTooltips(container) {
  try {
    if (container && container.tooltip) {
      container.tooltip({
        selector: '.card-header [title]',
        delay: { show: 0, hide: 0 },
        show: 100,
        container: 'body' // Place tooltips in body for easier management
      });
    }
  } catch (e) {
    console.warn('Tooltip initialization error:', e);
  }
}

/**
 * Removes all tooltip elements from the DOM
 * Helps prevent memory leaks from lingering tooltips
 * Includes error handling for Electron compatibility
 */
function cleanupAllTooltips() {
  try {
    $('.tooltip').remove(); // Directly remove all tooltip elements
    
    // Safely dispose tooltips if the method is available
    const bsElements = $('[data-bs-original-title]');
    if (bsElements.length && bsElements.tooltip) {
      bsElements.tooltip('dispose'); // Bootstrap 5
    }
    
    const originalElements = $('[data-original-title]');
    if (originalElements.length && originalElements.tooltip) {
      originalElements.tooltip('dispose'); // Bootstrap 4
    }
  } catch (e) {
    console.warn('Tooltip cleanup error:', e);
  }
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
    const isPdfEnabled = /sonnet|gemini|4o|4o-mini|o1|gpt-4\.\d/.test(selectedModel);
    
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

// Export functions to window for browser environment
window.uiUtils = {
  autoResize,
  setupTextarea,
  adjustScrollButtons,
  setupTooltips,
  cleanupAllTooltips,
  adjustImageUploadButton
};

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = window.uiUtils;
}
