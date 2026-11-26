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
    const isMenuHidden = window.LayoutController ? window.LayoutController.isMenuHidden()
      : (toggleBtn && toggleBtn.classList.contains('menu-hidden'));

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
 * Gives a card header's controls their tooltips (MonadicTip).
 * @param {HTMLElement} container - Container element to attach tooltips to
 */
function setupTooltips(container) {
  if (!container || !window.MonadicTip) return;
  container.querySelectorAll('.card-header [title]').forEach(function(el) {
    window.MonadicTip.attach(el, { delay: { show: 0, hide: 0 } });
  });
}

/**
 * Shows the tooltip of a card header's control when the pointer or the focus
 * comes to it. The tooltip is made then, so a control added later needs
 * nothing done for it; made during this first event, it is shown from here
 * (its own listeners come too late for it).
 * @param {HTMLElement} container - Element the cards are added to
 */
function showCardTooltipsOnHover(container) {
  if (!container || container._cardTooltipsOnHover) return;
  container._cardTooltipsOnHover = true;
  var show = function(event) {
    if (!window.MonadicTip) return;
    var target = event.target;
    var el = target && target.closest
      ? target.closest('.card-header [title], .card-header [data-mtip]')
      : null;
    if (!el || !container.contains(el) || window.MonadicTip.get(el)) return;
    var keyboard = event.type === 'focusin';
    if (keyboard) {
      try { if (!el.matches(':focus-visible')) keyboard = false; } catch (_) { /* older engines */ }
      if (!keyboard) return;
    }
    window.MonadicTip.attach(el, { delay: { show: 0, hide: 0 } }).show(keyboard ? 'focus' : 'hover');
  };
  container.addEventListener('mouseover', show);
  container.addEventListener('focusin', show);
}

/**
 * Hides any tooltip shown (MonadicTip); the controls keep theirs.
 */
function cleanupAllTooltips() {
  if (window.MonadicTip) window.MonadicTip.hideAll();
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
  showCardTooltipsOnHover,
  cleanupAllTooltips,
  simulateEscapeKey,
  setupSearchCloseHandlers
};

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = window.uiUtils;
}
