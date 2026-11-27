/**
 * Monadic Chat Module Shims
 *
 * This file provides fallback implementations for module functions that might be missing
 * in order to make the application more resilient to loading errors.
 *
 * Rather than duplicating fallback implementations throughout the codebase, this
 * centralized approach ensures consistent behavior while minimizing code duplication.
 */

// Clipboard operation shims to ensure copying works in DevTools
document.addEventListener('keydown', function(e) {
  // Check if we're in a devtools context by looking for devtools-specific elements
  const inDevTools = document.querySelector('.inspector-view-tabbed-pane') ||
                    document.querySelector('.console-view') ||
                    document.querySelector('.elements-panel');

  if (inDevTools) {
    // Handle Cmd+C (macOS) or Ctrl+C (Windows/Linux)
    if ((e.metaKey || e.ctrlKey) && e.key === 'c') {
      const selection = window.getSelection().toString();
      if (selection) {
        // Use the Electron clipboard API if available, fall back to execCommand
        if (window.electronAPI && window.electronAPI.writeClipboard) {
          window.electronAPI.writeClipboard(selection);
        } else if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(selection);
        } else {
          // Last resort fallback to document.execCommand
          const textArea = document.createElement('textarea');
          textArea.value = selection;
          textArea.style.position = 'fixed';
          textArea.style.left = '-999999px';
          textArea.style.top = '-999999px';
          document.body.appendChild(textArea);
          textArea.focus();
          textArea.select();
          document.execCommand('copy');
          document.body.removeChild(textArea);
        }
      }
    }
  }
}, true);

// Ensure the window.shims namespace exists
window.shims = window.shims || {};

// UI Utilities Shims
window.shims.uiUtils = {
  // Resizes a textarea element based on its content
  autoResize: function(textarea, initialHeight) {
    textarea.style.height = 'auto';
    const newHeight = Math.max(textarea.scrollHeight, initialHeight);
    textarea.style.height = newHeight + 'px';
  },

  // Sets up a textarea with automatic resizing based on content
  setupTextarea: function(textarea, initialHeight) {
    let isIMEActive = false;

    textarea.style.height = initialHeight + 'px';

    textarea.addEventListener('compositionstart', function() {
      isIMEActive = true;
    });

    textarea.addEventListener('compositionend', function() {
      isIMEActive = false;
      window.shims.uiUtils.autoResize(textarea, initialHeight);
    });

    textarea.addEventListener('input', function() {
      if (!isIMEActive) {
        window.shims.uiUtils.autoResize(textarea, initialHeight);
      }
    });

    textarea.addEventListener('focus', function() {
      window.shims.uiUtils.autoResize(textarea, initialHeight);
    });

    window.shims.uiUtils.autoResize(textarea, initialHeight);
  },

  // Adjusts scroll buttons visibility based on scroll position
  adjustScrollButtons: function() {
    var mainPanel = $id('main');
    if (!mainPanel) return;

    // The conversation is not shown (the side column alone): no scroll buttons
    if (window.LayoutController && window.LayoutController.isMainHidden()) {
      $hide($id('back_to_top'));
      $hide($id('back_to_bottom'));
      return;
    }

    // Also check for menu-visible class (mobile menu state)
    if (document.body.classList.contains('menu-visible')) {
      var topBtn2 = $id('back_to_top');
      var bottomBtn2 = $id('back_to_bottom');
      $hide(topBtn2);
      $hide(bottomBtn2);
      return;
    }

    var mainHeight = mainPanel.clientHeight;
    var mainScrollHeight = mainPanel.scrollHeight;
    var mainScrollTop = mainPanel.scrollTop;

    // Position buttons relative to main panel
    var mainRect = mainPanel.getBoundingClientRect();
    var mainWidth = mainPanel.clientWidth;
    if (mainRect) {
      var buttonRight = window.innerWidth - (mainRect.left + mainWidth) + 30;
      var backToTop = $id('back_to_top');
      var backToBottom = $id('back_to_bottom');
      if (backToTop) backToTop.style.right = buttonRight + "px";
      if (backToBottom) backToBottom.style.right = buttonRight + "px";
    }

    // Calculate thresholds (100px minimum scroll to show buttons)
    var scrollThreshold = 100;

    var backToTopBtn = $id('back_to_top');
    var backToBottomBtn = $id('back_to_bottom');

    // Show top button when scrolled down enough from the top
    if (mainScrollTop > scrollThreshold) {
      $show(backToTopBtn);
    } else {
      $hide(backToTopBtn);
    }

    // Show bottom button when not near the bottom
    var distanceFromBottom = mainScrollHeight - mainScrollTop - mainHeight;
    if (distanceFromBottom > scrollThreshold) {
      $show(backToBottomBtn);
    } else {
      $hide(backToBottomBtn);
    }
  },

  // Gives a card header's controls their tooltips (MonadicTip)
  setupTooltips: function(container) {
    if (!container || !window.MonadicTip) return;
    container.querySelectorAll('.card-header [title]').forEach(function(el) {
      window.MonadicTip.attach(el, { delay: { show: 0, hide: 0 } });
    });
  },

  // Hides any tooltip shown; the controls keep theirs
  cleanupAllTooltips: function() {
    if (window.MonadicTip) window.MonadicTip.hideAll();
  }

};

// Form Handlers Shims. Routes through window.monadicFetch (which is
// loaded earlier in the bundle) so the X-Requested-With contract and
// JSON parsing live in one place.
window.shims.formHandlers = {
  fetchWebpage: function (url, urlLabel) {
    if (!url) return Promise.reject(new Error("Please specify the URL of the page to fetch"));
    if (!url.match(/^(http|https):\/\/[^ "]+$/)) return Promise.reject(new Error("Please enter a valid URL"));

    const formData = new FormData();
    formData.append("pageURL", url);
    formData.append("urlLabel", urlLabel || "");

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 30000);
    return window.monadicFetch.postJson("/fetch_webpage", formData, { signal: controller.signal })
      .finally(() => clearTimeout(timer));
  },

  importSession: function (file) {
    if (!file) return Promise.reject(new Error("Please select a file to import"));

    const formData = new FormData();
    formData.append('file', file);
    if (typeof window.getMonadicTabId === 'function' && window.getMonadicTabId()) {
      formData.append('tab_id', window.getMonadicTabId());
    }

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 30000);
    return window.monadicFetch.postJson("/load", formData, { signal: controller.signal })
      .finally(() => clearTimeout(timer));
  },

  // Sets up validation for URL input fields
  setupUrlValidation: function(urlInput, submitButton) {
    const validateUrl = function() {
      const url = urlInput.value;
      const validUrl = url.match(/^(http|https):\/\/[^ "]+$/);
      submitButton.disabled = !validUrl;
    };

    urlInput.addEventListener("change", validateUrl);
    urlInput.addEventListener("keyup", validateUrl);
    urlInput.addEventListener("input", validateUrl);
  },

  // Sets up validation for file input fields
  setupFileValidation: function(fileInput, submitButton) {
    fileInput.addEventListener("change", function() {
      submitButton.disabled = !fileInput.files || fileInput.files.length === 0;
    });
  },

  // Shows a dialog (MonadicDialog) and focuses its field; cleanupFn runs
  // once it has closed
  showModalWithFocus: function(modalId, focusElementId, cleanupFn) {
    var modal = $id(modalId);
    var focusElement = $id(focusElementId);
    if (!modal || !focusElement || typeof window.MonadicDialog === 'undefined') return;
    var dialog = window.MonadicDialog.of(modal);
    if (typeof cleanupFn === 'function') {
      modal.addEventListener('mdialog:shown', function onShown() {
        modal.removeEventListener('mdialog:shown', onShown);
        modal.addEventListener('mdialog:hidden', function onHidden() {
          modal.removeEventListener('mdialog:hidden', onHidden);
          cleanupFn();
        });
      });
    }
    dialog.open();
    focusElement.focus();
  }
};

// Helper function to load modules with shim fallbacks
window.loadModuleWithShim = function(moduleName) {
  // Check if the module is already available
  if (window[moduleName]) return window[moduleName];

  // Check if we have a shim for this module
  if (window.shims && window.shims[moduleName]) {
    console.warn(`Using shim for ${moduleName} module`);
    return window.shims[moduleName];
  }

  // If no shim available, return an empty object
  console.error(`No module or shim available for ${moduleName}`);
  return {};
};

// Function to install shims as needed
window.installShims = function() {
  // Install UI utilities shim if needed
  if (!window.uiUtils) {
    console.warn('Installing UI utilities shim');
    window.uiUtils = window.shims.uiUtils;
  }

  // Install form handlers shim if needed
  if (!window.formHandlers) {
    console.warn('Installing form handlers shim');
    window.formHandlers = window.shims.formHandlers;
  }
};

// Export the shims for CommonJS environment (for testing)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    uiUtils: window.shims.uiUtils,
    formHandlers: window.shims.formHandlers,
    loadModuleWithShim: window.loadModuleWithShim,
    installShims: window.installShims
  };
}
