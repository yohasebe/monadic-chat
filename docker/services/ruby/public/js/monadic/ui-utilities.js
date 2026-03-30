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
    const mainPanel = $id('main');
    if (!mainPanel) return;

    // Use centralized configuration if available
    const isMobile = window.UIConfig ? window.UIConfig.isMobileView() : window.innerWidth < 600;
    const isTablet = window.UIConfig ? window.UIConfig.isTabletView() : window.innerWidth < 768;

    // On mobile and tablet screens where menu/content are exclusive, check toggle state
    if (isMobile || isTablet) {
    // Check if toggle button has menu-hidden class
    // When menu-hidden class is present, menu is hidden and main is showing
    // When menu-hidden class is absent, menu is showing and main is hidden
    const toggleBtn = $id('toggle-menu');
    const isMenuHidden = toggleBtn && toggleBtn.classList.contains('menu-hidden');

    if (!isMenuHidden) {
      // Menu is showing (toggle button doesn't have menu-hidden class), hide scroll buttons
      const topBtn = $id('back_to_top');
      const bottomBtn = $id('back_to_bottom');
      $hide(topBtn);
      $hide(bottomBtn);
      return;
    }
  }

  // Also check for menu-visible class (mobile menu state)
  if (document.body.classList.contains('menu-visible')) {
    const topBtn = $id('back_to_top');
    const bottomBtn = $id('back_to_bottom');
    $hide(topBtn);
    $hide(bottomBtn);
    return;
  }

  // Safe access to dimensions with fallbacks for iOS
  const mainHeight = mainPanel.clientHeight || 0;
  const mainScrollHeight = mainPanel.scrollHeight || 0;
  const mainScrollTop = mainPanel.scrollTop || 0;

  // Get scroll button elements
  const backToTopBtn = $id('back_to_top');
  const backToBottomBtn = $id('back_to_bottom');

  // Position buttons relative to main panel
  const mainRect = mainPanel.getBoundingClientRect();
  const mainWidth = mainPanel.clientWidth;
  if (mainRect) {
    const buttonRight = window.innerWidth - (mainRect.left + mainWidth) + 30;
    if (backToTopBtn) backToTopBtn.style.right = buttonRight + "px";
    if (backToBottomBtn) backToBottomBtn.style.right = buttonRight + "px";
  }

    // Calculate thresholds using config or default
    const scrollThreshold = window.UIConfig ? window.UIConfig.TIMING.SCROLL_THRESHOLD : 100;

  // Show top button when scrolled down enough from the top
  // This should work even when at the bottom
  if (mainScrollTop > scrollThreshold) {
    $show(backToTopBtn);
  } else {
    $hide(backToTopBtn);
  }

    // Show bottom button when not near the bottom
    const distanceFromBottom = mainScrollHeight - mainScrollTop - mainHeight;
    if (distanceFromBottom > scrollThreshold) {
      $show(backToBottomBtn);
    } else {
      $hide(backToBottomBtn);
    }
  } catch (error) {
    console.error("Error in adjustScrollButtons:", error);
    // Hide buttons on error to prevent stuck visible state
    var topBtn = $id('back_to_top');
    var bottomBtn = $id('back_to_bottom');
    $hide(topBtn);
    $hide(bottomBtn);
  }
}

/**
 * Sets up tooltips for specific UI elements
 * Includes error handling for Electron compatibility
 * @param {HTMLElement} container - Container element to attach tooltips to
 */
function setupTooltips(container) {
  try {
    if (container && typeof bootstrap !== 'undefined' && bootstrap.Tooltip) {
      var titleEls = container.querySelectorAll('.card-header [title]');
      titleEls.forEach(function(el) {
        new bootstrap.Tooltip(el, {
          trigger: 'hover',
          delay: { show: 0, hide: 0 },
          container: 'body'
        });
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
    document.querySelectorAll('.tooltip').forEach(function(el) { el.remove(); });

    // Safely dispose tooltips if Bootstrap is available
    if (typeof bootstrap !== 'undefined' && bootstrap.Tooltip) {
      document.querySelectorAll('[data-bs-original-title]').forEach(function(el) {
        var tip = bootstrap.Tooltip.getInstance(el);
        if (tip) tip.dispose();
      });
      document.querySelectorAll('[data-original-title]').forEach(function(el) {
        var tip = bootstrap.Tooltip.getInstance(el);
        if (tip) tip.dispose();
      });
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
  const imageFileElement = $id('image-file');
  const appsElement = $id('apps');
  const currentApp = appsElement ? appsElement.value : null;

  // Check if current app is an image generation app using the common function
  const isImageGenerationApp = window.isImageGenerationApp ? window.isImageGenerationApp(currentApp) : false;
  const allowPdfInImageApp = currentApp === "ImageGeneratorGemini3Preview";

  // Show button if model has vision capability OR if it's an image generation app
  if ((modelData && modelData.vision_capability) || isImageGenerationApp) {
    // Enable the button
    if (imageFileElement) imageFileElement.disabled = false;

    // Check if the model's provider supports PDF/File Inputs using the common functions
    const isPdfEnabled = window.isPdfSupportedForModel ? window.isPdfSupportedForModel(selectedModel) : false;
    const isFileInputsEnabled = window.isFileInputsSupportedForModel ? window.isFileInputsSupportedForModel(selectedModel) : false;

    // Button text labels
    const imageText = typeof webUIi18n !== 'undefined' && webUIi18n.t ? webUIi18n.t('ui.image') : 'Image';
    const imagePdfText = typeof webUIi18n !== 'undefined' && webUIi18n.t ? webUIi18n.t('ui.imagePdf') : 'Image/PDF';
    const fileText = typeof webUIi18n !== 'undefined' && webUIi18n.t ? webUIi18n.t('ui.file') : 'File';

    if (imageFileElement) {
      if (isImageGenerationApp && !allowPdfInImageApp) {
        imageFileElement.innerHTML = '<i class="fas fa-image"></i> <span data-i18n="ui.image">' + imageText + '</span>';
      } else if (isImageGenerationApp && allowPdfInImageApp) {
        imageFileElement.innerHTML = '<i class="fas fa-file"></i> <span data-i18n="ui.imagePdf">' + imagePdfText + '</span>';
      } else if (isFileInputsEnabled) {
        imageFileElement.innerHTML = '<i class="fas fa-file"></i> <span data-i18n="ui.file">' + fileText + '</span>';
      } else if (isPdfEnabled) {
        imageFileElement.innerHTML = '<i class="fas fa-file"></i> <span data-i18n="ui.imagePdf">' + imagePdfText + '</span>';
      } else {
        imageFileElement.innerHTML = '<i class="fas fa-image"></i> <span data-i18n="ui.image">' + imageText + '</span>';
      }
    }

    // Also update the file input's accept attribute
    const imageFileInput = $id('imageFile');
    if (imageFileInput) {
      if (isFileInputsEnabled && !isImageGenerationApp) {
        imageFileInput.setAttribute('accept', '.jpg,.jpeg,.png,.gif,.webp,.pdf,.xlsx,.docx,.pptx,.csv,.txt,.md,.json,.html,.xml');
      } else if ((isImageGenerationApp && !allowPdfInImageApp) || (!isPdfEnabled && !allowPdfInImageApp)) {
        imageFileInput.setAttribute('accept', '.jpg,.jpeg,.png,.gif,.webp');
      } else {
        imageFileInput.setAttribute('accept', '.jpg,.jpeg,.png,.gif,.webp,.pdf');
      }
    }

    if (imageFileElement) {
      $show(imageFileElement);
    }
  } else {
    if (imageFileElement) {
      imageFileElement.disabled = true;
      $hide(imageFileElement);
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
 * @param {string} containerSelector - CSS selector for the container to add handlers to
 */
function setupSearchCloseHandlers(containerSelector) {
  if (containerSelector === undefined) containerSelector = 'body';
  // Find all relevant UI elements that should dismiss search dialog when clicked
  var container = document.querySelector(containerSelector);
  if (!container) return;

  var uiElements = container.querySelectorAll('#message, #send, #clear, #voice, #discourse, .card, #model, #reasoning-effort, textarea, button');

  // Since mousedown happens before focus events, use it to close search before focus
  uiElements.forEach(function(el) {
    el.addEventListener('mousedown', function(e) {
      // Only simulate Escape if this isn't part of the search UI
      if (!isPartOfSearchUI(e.target)) {
        simulateEscapeKey();
      }
    });
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
