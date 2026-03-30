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
    var mainPanel = document.getElementById('main');
    if (!mainPanel) return;

    var windowWidth = window.innerWidth;
    var isMobile = windowWidth < 600;
    var isMedium = windowWidth < 768; // Bootstrap md breakpoint

    // On mobile and medium screens where menu/content are exclusive, check toggle state
    if (isMobile || isMedium) {
      var toggleBtn = document.getElementById('toggle-menu');
      var isMenuHidden = toggleBtn && toggleBtn.classList.contains('menu-hidden');

      if (!isMenuHidden) {
        var topBtn = document.getElementById('back_to_top');
        var bottomBtn = document.getElementById('back_to_bottom');
        if (topBtn) topBtn.style.display = 'none';
        if (bottomBtn) bottomBtn.style.display = 'none';
        return;
      }
    }

    // Also check for menu-visible class (mobile menu state)
    if (document.body.classList.contains('menu-visible')) {
      var topBtn2 = document.getElementById('back_to_top');
      var bottomBtn2 = document.getElementById('back_to_bottom');
      if (topBtn2) topBtn2.style.display = 'none';
      if (bottomBtn2) bottomBtn2.style.display = 'none';
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
      var backToTop = document.getElementById('back_to_top');
      var backToBottom = document.getElementById('back_to_bottom');
      if (backToTop) backToTop.style.right = buttonRight + "px";
      if (backToBottom) backToBottom.style.right = buttonRight + "px";
    }

    // Calculate thresholds (100px minimum scroll to show buttons)
    var scrollThreshold = 100;

    var backToTopBtn = document.getElementById('back_to_top');
    var backToBottomBtn = document.getElementById('back_to_bottom');

    // Show top button when scrolled down enough from the top
    if (mainScrollTop > scrollThreshold) {
      if (backToTopBtn) backToTopBtn.style.display = '';
    } else {
      if (backToTopBtn) backToTopBtn.style.display = 'none';
    }

    // Show bottom button when not near the bottom
    var distanceFromBottom = mainScrollHeight - mainScrollTop - mainHeight;
    if (distanceFromBottom > scrollThreshold) {
      if (backToBottomBtn) backToBottomBtn.style.display = '';
    } else {
      if (backToBottomBtn) backToBottomBtn.style.display = 'none';
    }
  },

  // Sets up tooltips for card header elements
  setupTooltips: function(container) {
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
  },

  // Removes all tooltip elements to prevent memory leaks
  cleanupAllTooltips: function() {
    try {
      document.querySelectorAll('.tooltip').forEach(function(el) { el.remove(); });

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
  },

  // Adjusts image upload button based on selected model and app settings
  adjustImageUploadButton: function(selectedModel) {
    if (!modelSpec || !selectedModel) return;

    var modelData = modelSpec[selectedModel];
    var imageFileElement = document.getElementById('image-file');
    var appsElement = document.getElementById('apps');
    var currentApp = appsElement ? appsElement.value : null;

    // Check if current app has image capability enabled
    var toBool = window.toBool || (function(value) {
      if (typeof value === 'boolean') return value;
      if (typeof value === 'string') return value === 'true';
      return !!value;
    });

    // Check if current app is an image generation app
    var isImageGenerationApp = apps[currentApp] && toBool(apps[currentApp].image_generation);
    var allowPdfInImageApp = currentApp === "ImageGeneratorGemini3Preview";

    // Show button if model has vision capability OR if it's an image generation app
    if ((modelData && modelData.vision_capability) || isImageGenerationApp) {
      // Enable the button
      if (imageFileElement) imageFileElement.disabled = false;

      // Update button text based on PDF/File Inputs support and image generation capability (SSOT-aware)
      var isPdfEnabled = (typeof window !== 'undefined' && window.isPdfSupportedForModel)
        ? window.isPdfSupportedForModel(selectedModel)
        : /sonnet|gemini|4o|4o-mini|o1|gpt-4\.\d/.test(selectedModel);
      var isFileInputsEnabled = (typeof window !== 'undefined' && window.isFileInputsSupportedForModel)
        ? window.isFileInputsSupportedForModel(selectedModel)
        : false;

      // Button text labels
      var imageText = typeof webUIi18n !== 'undefined' && webUIi18n.t ? webUIi18n.t('ui.image') : 'Image';
      var imagePdfText = typeof webUIi18n !== 'undefined' && webUIi18n.t ? webUIi18n.t('ui.imagePdf') : 'Image/PDF';
      var fileText = typeof webUIi18n !== 'undefined' && webUIi18n.t ? webUIi18n.t('ui.file') : 'File';

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

      // Update accept attribute if present
      var imageFileInput = document.getElementById('imageFile');
      if (imageFileInput) {
        if (isFileInputsEnabled && !isImageGenerationApp) {
          imageFileInput.setAttribute('accept', '.jpg,.jpeg,.png,.gif,.webp,.pdf,.xlsx,.docx,.pptx,.csv,.txt,.md,.json,.html,.xml');
        } else if ((isImageGenerationApp && !allowPdfInImageApp) || (!isPdfEnabled && !allowPdfInImageApp)) {
          imageFileInput.setAttribute('accept', '.jpg,.jpeg,.png,.gif,.webp');
        } else {
          imageFileInput.setAttribute('accept', '.jpg,.jpeg,.png,.gif,.webp,.pdf');
        }
      }

      if (imageFileElement) imageFileElement.style.display = '';
    } else {
      if (imageFileElement) {
        imageFileElement.disabled = true;
        imageFileElement.style.display = 'none';
      }
    }
  }
};

// Form Handlers Shims
window.shims.formHandlers = {
  // Uploads a PDF file to the server
  uploadPdf: function(file, fileTitle) {
    return new Promise((resolve, reject) => {
      if (!file) {
        reject(new Error("Please select a PDF file to upload"));
        return;
      }

      if (file.type !== "application/pdf") {
        reject(new Error("Please select a PDF file"));
        return;
      }

      const formData = new FormData();
      formData.append("pdfFile", file);
      formData.append("pdfTitle", fileTitle);

      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 120000);
      fetch("/pdf", { method: "POST", body: formData, signal: controller.signal })
        .then(res => { clearTimeout(timer); return res.ok ? res.json() : Promise.reject(new Error(`Upload failed: ${res.status}`)); })
        .then(resolve)
        .catch(e => { clearTimeout(timer); reject(e); });
    });
  },

  // Converts a document file to text
  convertDocument: function(doc, docLabel) {
    return new Promise((resolve, reject) => {
      if (!doc) {
        reject(new Error("Please select a document file to convert"));
        return;
      }

      if (doc.type === "application/octet-stream") {
        reject(new Error("Unsupported file type"));
        return;
      }

      const formData = new FormData();
      formData.append("docFile", doc);
      formData.append("docLabel", docLabel || "");

      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 60000);
      fetch("/document", { method: "POST", body: formData, signal: controller.signal })
        .then(res => { clearTimeout(timer); return res.ok ? res.json() : Promise.reject(new Error(`Conversion failed: ${res.status}`)); })
        .then(resolve)
        .catch(e => { clearTimeout(timer); reject(e); });
    });
  },

  // Fetches content from a webpage
  fetchWebpage: function(url, urlLabel) {
    return new Promise((resolve, reject) => {
      if (!url) {
        reject(new Error("Please specify the URL of the page to fetch"));
        return;
      }

      if (!url.match(/^(http|https):\/\/[^ "]+$/)) {
        reject(new Error("Please enter a valid URL"));
        return;
      }

      const formData = new FormData();
      formData.append("pageURL", url);
      formData.append("urlLabel", urlLabel || "");

      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 30000);
      fetch("/fetch_webpage", { method: "POST", body: formData, signal: controller.signal })
        .then(res => { clearTimeout(timer); return res.ok ? res.json() : Promise.reject(new Error(`Fetch failed: ${res.status}`)); })
        .then(resolve)
        .catch(e => { clearTimeout(timer); reject(e); });
    });
  },

  // Imports a session from a JSON file
  importSession: function(file) {
    return new Promise((resolve, reject) => {
      if (!file) {
        reject(new Error("Please select a file to import"));
        return;
      }

      const formData = new FormData();
      formData.append('file', file);

      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 30000);
      fetch("/load", { method: "POST", body: formData, signal: controller.signal })
        .then(res => { clearTimeout(timer); return res.ok ? res.json() : Promise.reject(new Error(`Import failed: ${res.status}`)); })
        .then(resolve)
        .catch(e => { clearTimeout(timer); reject(e); });
    });
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

  // Shows a modal with proper focus management
  showModalWithFocus: function(modalId, focusElementId, cleanupFn) {
    var modal = document.getElementById(modalId);
    var focusElement = document.getElementById(focusElementId);

    if (!modal || !focusElement) return;

    bootstrap.Modal.getOrCreateInstance(modal).show();

    var timerKey = '_focusTimer';
    var existingTimer = modal[timerKey];

    if (existingTimer) {
      clearTimeout(existingTimer);
      delete modal[timerKey];
    }

    modal[timerKey] = setTimeout(function() {
      focusElement.focus();
      delete modal[timerKey];
    }, 500);

    if (typeof cleanupFn === 'function') {
      modal.addEventListener('hidden.bs.modal', function onHidden() {
        cleanupFn();

        var remainingTimer = modal[timerKey];
        if (remainingTimer) {
          clearTimeout(remainingTimer);
          delete modal[timerKey];
        }
        modal.removeEventListener('hidden.bs.modal', onHidden);
      });
    }
  },

  // Uploads an audio or MIDI file for analysis
  uploadAudioFile: function(file) {
    return new Promise((resolve, reject) => {
      if (!file) {
        reject(new Error("Please select an audio or MIDI file"));
        return;
      }

      const formData = new FormData();
      formData.append("audioFile", file);

      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 60000);
      fetch("/upload_audio", { method: "POST", body: formData, signal: controller.signal })
        .then(res => { clearTimeout(timer); return res.ok ? res.json() : Promise.reject(new Error(`Audio upload failed: ${res.status}`)); })
        .then(resolve)
        .catch(e => { clearTimeout(timer); reject(e); });
    });
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
