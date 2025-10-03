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
  try {
    const mainPanel = $("#main");
    
    // Use centralized configuration if available
    const isMobile = window.UIConfig ? window.UIConfig.isMobileView() : $(window).width() < 600;
    const isTablet = window.UIConfig ? window.UIConfig.isTabletView() : $(window).width() < 768;
  
    // On mobile and tablet screens where menu/content are exclusive, check toggle state
    if (isMobile || isTablet) {
    // Check if toggle button has menu-hidden class
    // When menu-hidden class is present, menu is hidden and main is showing
    // When menu-hidden class is absent, menu is showing and main is hidden
    const toggleBtn = $("#toggle-menu");
    const isMenuHidden = toggleBtn.hasClass("menu-hidden");
    
    if (!isMenuHidden) {
      // Menu is showing (toggle button doesn't have menu-hidden class), hide scroll buttons
      $("#back_to_top").hide();
      $("#back_to_bottom").hide();
      return;
    }
  }
  
  // Also check for menu-visible class (mobile menu state) 
  if ($("body").hasClass("menu-visible")) {
    $("#back_to_top").hide();
    $("#back_to_bottom").hide();
    return;
  }
  
  // Safe access to dimensions with fallbacks for iOS
  const mainHeight = mainPanel.height() || 0;
  const mainScrollHeight = mainPanel.prop("scrollHeight") || 0;
  const mainScrollTop = mainPanel.scrollTop() || 0;
  
  // Get scroll button elements
  const backToTopBtn = $("#back_to_top");
  const backToBottomBtn = $("#back_to_bottom");
  
  // Position buttons relative to main panel
  const mainOffset = mainPanel.offset();
  const mainWidth = mainPanel.width();
  if (mainOffset) {
    const buttonRight = $(window).width() - (mainOffset.left + mainWidth) + 30;
    backToTopBtn.css("right", buttonRight + "px");
    backToBottomBtn.css("right", buttonRight + "px");
  }
  
    // Calculate thresholds using config or default
    const scrollThreshold = window.UIConfig ? window.UIConfig.TIMING.SCROLL_THRESHOLD : 100;
  
  // Show top button when scrolled down enough from the top
  // This should work even when at the bottom
  if (mainScrollTop > scrollThreshold) {
    backToTopBtn.fadeIn(200);
  } else {
    backToTopBtn.fadeOut(200);
  }
  
    // Show bottom button when not near the bottom
    const distanceFromBottom = mainScrollHeight - mainScrollTop - mainHeight;
    if (distanceFromBottom > scrollThreshold) {
      backToBottomBtn.fadeIn(200);
    } else {
      backToBottomBtn.fadeOut(200);
    }
  } catch (error) {
    console.error("Error in adjustScrollButtons:", error);
    // Hide buttons on error to prevent stuck visible state
    $("#back_to_top, #back_to_bottom").hide();
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
 * Adjusts image upload button availability based on selected model and app settings
 * @param {string} selectedModel - The currently selected AI model
 */
function adjustImageUploadButton(selectedModel) {
  if (!modelSpec || !selectedModel) return;
  
  const modelData = modelSpec[selectedModel];
  const imageFileElement = $("#image-file");
  const currentApp = $("#apps").val();

  // Check if current app has image capability enabled
  const toBool = window.toBool || ((value) => {
    if (typeof value === 'boolean') return value;
    if (typeof value === 'string') return value === 'true';
    return !!value;
  });
  const appHasImageCapability = apps && apps[currentApp] && toBool(apps[currentApp]["image"]);

  // Check if current app is an image generation app using the common function
  const isImageGenerationApp = window.isImageGenerationApp ? window.isImageGenerationApp(currentApp) : false;
  
  // Show button only if BOTH app has image capability AND model has vision capability
  // OR if it's an image generation app (which always needs image input)
  if ((appHasImageCapability && modelData && modelData.vision_capability) || isImageGenerationApp) {
    // Enable the button
    imageFileElement.prop("disabled", false);
    
    // Check if the model's provider supports PDF using the common function
    const isPdfEnabled = window.isPdfSupportedForModel ? window.isPdfSupportedForModel(selectedModel) : false;
    
    // If it's an image generation app, show "Image" regardless of PDF support
    const imageText = typeof webUIi18n !== 'undefined' && webUIi18n.t ? webUIi18n.t('ui.image') : 'Image';
    const imagePdfText = typeof webUIi18n !== 'undefined' && webUIi18n.t ? webUIi18n.t('ui.imagePdf') : 'Image/PDF';
    
    if (isImageGenerationApp) {
      imageFileElement.html('<i class="fas fa-image"></i> <span data-i18n="ui.image">' + imageText + '</span>');
    } else if (isPdfEnabled) {
      imageFileElement.html('<i class="fas fa-file"></i> <span data-i18n="ui.imagePdf">' + imagePdfText + '</span>');
    } else {
      imageFileElement.html('<i class="fas fa-image"></i> <span data-i18n="ui.image">' + imageText + '</span>');
    }
    
    // Also update the file input's accept attribute
    const imageFileInput = $('#imageFile');
    if (imageFileInput.length) {
      if (isImageGenerationApp || !isPdfEnabled) {
        imageFileInput.attr('accept', '.jpg,.jpeg,.png,.gif,.webp');
      } else {
        imageFileInput.attr('accept', '.jpg,.jpeg,.png,.gif,.webp,.pdf');
      }
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

/**
 * Simulates an Escape key press to close any browser dialogs like search
 */
function simulateEscapeKey() {
  // Create a keyboard event for Escape key
  const escEvent = new KeyboardEvent('keydown', {
    key: 'Escape',
    code: 'Escape',
    keyCode: 27,
    which: 27,
    bubbles: true,
    cancelable: true
  });
  
  // Dispatch event on document to close browser's search dialog
  document.dispatchEvent(escEvent);
}

/**
 * Sets up click handlers on interactive elements to close search dialog
 * @param {jQuery} containerSelector - Selector for the container to add handlers to
 */
function setupSearchCloseHandlers(containerSelector = 'body') {
  // Find all relevant UI elements that should dismiss search dialog when clicked
  // We select only specific UI elements, not document-wide, to prevent unwanted behavior
  const uiElements = $(containerSelector).find('#message, #send, #clear, #voice, #discourse, .card, #model, #reasoning-effort, textarea, button');
  
  // Since mousedown happens before focus events, use it to close search before focus
  uiElements.on('mousedown', function(e) {
    // Only simulate Escape if this isn't part of the search UI
    if (!isPartOfSearchUI(e.target)) {
      simulateEscapeKey();
    }
  });
  
  // Helper function to check if element is part of search UI
  function isPartOfSearchUI(element) {
    // Skip check if element is null or undefined
    if (!element) return false;
    
    // Check tag name for common search elements (case-insensitive)
    const tagName = element.tagName ? element.tagName.toLowerCase() : '';
    if (tagName === 'input' && element.type === 'search') {
      return true;
    }

    // Check if the element is a button inside search UI (browser-specific)
    if (tagName === 'button' || tagName === 'div' || tagName === 'span') {
      // Check if the element is inside a search related parent
      let parent = element.parentElement;
      while (parent) {
        // Chrome search UI detection
        if (parent.shadowRoot && parent.tagName === 'SEARCH-DIALOG') {
          return true;
        }
        parent = parent.parentElement;
      }
      
      // Additional check for Safari/Firefox search UI buttons
      if (element.getAttribute('aria-label')) {
        const label = element.getAttribute('aria-label').toLowerCase();
        if (label.includes('search') || label.includes('find') || 
            label.includes('next') || label.includes('previous')) {
          return true;
        }
      }
    }

    // Check for common search UI class names
    // This will vary by browser, so we check for common patterns
    if (element.className && typeof element.className === 'string') {
      const classNames = element.className.toLowerCase();
      if (classNames.includes('find') || classNames.includes('search')) {
        return true;
      }
    }
    
    // Also check if any parent elements match search UI criteria
    // This handles cases where user clicks on inner elements of search UI
    let parent = element.parentElement;
    let searchPatterns = ['find', 'search', 'findinpage', 'findbar'];
    
    while (parent) {
      // Check for shadow DOM elements (used by Chrome's search UI)
      if (parent.shadowRoot) {
        return true;
      }
      
      if (parent.className && typeof parent.className === 'string') {
        const parentClass = parent.className.toLowerCase();
        if (searchPatterns.some(pattern => parentClass.includes(pattern))) {
          return true;
        }
      }
      
      if (parent.id && searchPatterns.some(pattern => parent.id.toLowerCase().includes(pattern))) {
        return true;
      }

      // Check for browser-specific search dialogs (Firefox, Safari, etc.)
      if (parent.getAttribute && parent.getAttribute('role') === 'dialog') {
        return true;
      }
      
      parent = parent.parentElement;
    }
    
    // Additional check for the element being part of browser's default search UI
    // Most browsers place search dialog in a special container
    if (window.getComputedStyle(element).zIndex > 1000) {
      const rect = element.getBoundingClientRect();
      // Search dialogs are typically positioned at the top of the viewport
      if (rect.top < 100) {
        return true;
      }
    }
    
    return false;
  }
}

// Export functions to window for browser environment
window.uiUtils = {
  autoResize,
  setupTextarea,
  adjustScrollButtons,
  setupTooltips,
  cleanupAllTooltips,
  adjustImageUploadButton,
  simulateEscapeKey,
  setupSearchCloseHandlers
};

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = window.uiUtils;
}
