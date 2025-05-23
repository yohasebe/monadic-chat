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
    const mainPanel = $("#main");
    const mainHeight = mainPanel.height();
    const mainScrollHeight = mainPanel.prop("scrollHeight");
    const mainScrollTop = mainPanel.scrollTop();
    
    // Show/hide the scroll to top button
    if (mainScrollTop > mainHeight / 2) {
      if ($("#back_to_top").show) $("#back_to_top").show();
    } else {
      if ($("#back_to_top").hide) $("#back_to_top").hide();
    }
    
    // Show/hide the scroll to bottom button
    if (mainScrollHeight - mainScrollTop - mainHeight > mainHeight / 2) {
      if ($("#back_to_bottom").show) $("#back_to_bottom").show();
    } else {
      if ($("#back_to_bottom").hide) $("#back_to_bottom").hide();
    }
  },

  // Sets up tooltips for card header elements
  setupTooltips: function(container) {
    try {
      if (container && container.tooltip) {
        container.tooltip({
          selector: '.card-header [title]',
          delay: { show: 0, hide: 0 },
          show: 100,
          container: 'body'
        });
      }
    } catch (e) {
      console.warn('Tooltip initialization error:', e);
    }
  },

  // Removes all tooltip elements to prevent memory leaks
  cleanupAllTooltips: function() {
    try {
      $('.tooltip').remove();
      
      // Safely dispose tooltips if the method is available
      const bsElements = $('[data-bs-original-title]');
      if (bsElements.length && bsElements.tooltip) {
        bsElements.tooltip('dispose');
      }
      
      const originalElements = $('[data-original-title]');
      if (originalElements.length && originalElements.tooltip) {
        originalElements.tooltip('dispose');
      }
    } catch (e) {
      console.warn('Tooltip cleanup error:', e);
    }
  },

  // Adjusts image upload button based on selected model and app settings
  adjustImageUploadButton: function(selectedModel) {
    if (!modelSpec || !selectedModel) return;
    
    const modelData = modelSpec[selectedModel];
    const imageFileElement = $("#image-file");
    const currentApp = $("#apps").val();
    
    // Check if current app is an image generation app
    const isImageGenerationApp = apps[currentApp] && 
      (apps[currentApp].image_generation === true || apps[currentApp].image_generation === "true");
    
    if (modelData && modelData.vision_capability) {
      // Enable the button
      imageFileElement.prop("disabled", false);
      
      // Update button text based on PDF support and image generation capability
      const isPdfEnabled = /sonnet|gemini|4o|4o-mini|o1|gpt-4\.\d/.test(selectedModel);
      
      // If it's an image generation app, show "Image" regardless of PDF support
      if (isImageGenerationApp) {
        imageFileElement.html('<i class="fas fa-image"></i> Image');
      } else if (isPdfEnabled) {
        imageFileElement.html('<i class="fas fa-file"></i> Image/PDF');
      } else {
        imageFileElement.html('<i class="fas fa-image"></i> Image');
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
  
      $.ajax({
        url: "/pdf",
        type: "POST",
        data: formData,
        processData: false,
        contentType: false,
        timeout: 120000,
        success: resolve,
        error: reject
      });
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
  
      $.ajax({
        url: "/document",
        type: "POST",
        data: formData,
        processData: false,
        contentType: false,
        timeout: 60000,
        success: resolve,
        error: reject
      });
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
  
      $.ajax({
        url: "/fetch_webpage",
        type: "POST",
        data: formData,
        processData: false,
        contentType: false,
        timeout: 30000,
        success: resolve,
        error: reject
      });
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
      
      $.ajax({
        url: "/load",
        type: "POST",
        data: formData,
        processData: false,
        contentType: false,
        timeout: 30000,
        success: resolve,
        error: reject
      });
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
    const modal = document.getElementById(modalId);
    const focusElement = document.getElementById(focusElementId);
    
    if (!modal || !focusElement) return;
    
    $(modal).modal("show");
    
    const timerKey = 'focusTimer';
    const existingTimer = $(modal).data(timerKey);
    
    if (existingTimer) {
      clearTimeout(existingTimer);
      $(modal).removeData(timerKey);
    }
    
    $(modal).data(timerKey, setTimeout(function() {
      focusElement.focus();
      $(modal).removeData(timerKey);
    }, 500));
    
    if (typeof cleanupFn === 'function') {
      $(modal).one('hidden.bs.modal', function() {
        cleanupFn();
        
        const remainingTimer = $(modal).data(timerKey);
        if (remainingTimer) {
          clearTimeout(remainingTimer);
          $(modal).removeData(timerKey);
        }
      });
    }
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