/**
 * Form handling utility functions for Monadic Chat
 * This module contains functions related to form validation, submission, and state management
 */

/**
 * Handles file uploads for the PDF viewer
 * @param {File} file - The file to upload
 * @param {string} fileTitle - Title for the PDF
 * @returns {Promise} - Promise resolving to the upload response
 */
function uploadPdf(file, fileTitle) {
  if (!file) {
    throw new Error("Please select a PDF file to upload");
  }
  
  // Validate file type
  if (file.type !== "application/pdf") {
    throw new Error("Please select a PDF file");
  }
  
  // Prepare form data
  const formData = new FormData();
  formData.append("pdfFile", file);
  formData.append("pdfTitle", fileTitle);

  // Resolve endpoint from server default (Settings)
  return new Promise((resolve, reject) => {
    $.getJSON('/api/pdf_storage_defaults')
      .done(function(info) {
        const mode = ((info && info.default_storage) ? info.default_storage : 'local').toLowerCase();
        const endpoint = (mode === 'cloud') ? "/openai/pdf?action=upload" : "/pdf";
        $.ajax({
          url: endpoint,
          type: "POST",
          data: formData,
          processData: false,
          contentType: false,
          dataType: "json", // Expect JSON response
          timeout: 120000, // PDF processing can take time
          success: resolve,
          error: reject
        });
      })
      .fail(function() {
        // Fallback to local upload
        $.ajax({
          url: "/pdf",
          type: "POST",
          data: formData,
          processData: false,
          contentType: false,
          dataType: "json",
          timeout: 120000,
          success: resolve,
          error: reject
        });
      });
  });
}

/**
 * Converts document files to text and adds to the message textarea
 * @param {File} doc - The document file to convert
 * @param {string} docLabel - Optional label for the document
 * @returns {Promise} - Promise resolving to the conversion response
 */
function convertDocument(doc, docLabel) {
  if (!doc) {
    throw new Error("Please select a document file to convert");
  }
  
  // Check if the file is a valid document type
  if (doc.type === "application/octet-stream") {
    throw new Error("Unsupported file type");
  }
  
  // Prepare form data
  const formData = new FormData();
  formData.append("docFile", doc);
  formData.append("docLabel", docLabel || "");

  // Use Promise for better async handling
  return new Promise((resolve, reject) => {
    $.ajax({
      url: "/document",
      type: "POST",
      data: formData,
      processData: false,
      contentType: false,
      timeout: 60000, // 60 second timeout
      success: resolve,
      error: reject
    });
  });
}

/**
 * Fetches content from a webpage and adds to message textarea
 * @param {string} url - The URL to fetch content from
 * @param {string} urlLabel - Optional label for the URL
 * @returns {Promise} - Promise resolving to the fetch response
 */
function fetchWebpage(url, urlLabel) {
  if (!url) {
    throw new Error("Please specify the URL of the page to fetch");
  }
  
  // Validate URL format
  if (!url.match(/^(http|https):\/\/[^ "]+$/)) {
    throw new Error("Please enter a valid URL");
  }
  
  // Prepare form data
  const formData = new FormData();
  formData.append("pageURL", url);
  formData.append("urlLabel", urlLabel || "");

  // Use Promise for better async handling
  return new Promise((resolve, reject) => {
    $.ajax({
      url: "/fetch_webpage",
      type: "POST",
      data: formData,
      processData: false,
      contentType: false,
      timeout: 30000, // 30 second timeout
      success: resolve,
      error: reject
    });
  });
}

/**
 * Imports a saved session from a JSON file
 * @param {File} file - The JSON file to import
 * @returns {Promise} - Promise resolving to the import response
 */
function importSession(file) {
  if (!file) {
    throw new Error("Please select a file to import");
  }
  
  // Prepare form data
  const formData = new FormData();
  formData.append('file', file);
  
  // Use Promise for better async handling
  return new Promise((resolve, reject) => {
    $.ajax({
      url: "/load",
      type: "POST",
      data: formData,
      processData: false,
      contentType: false,
      timeout: 30000, // 30 second timeout
      success: resolve,
      error: reject
    });
  });
}

/**
 * Sets up form validation for URL input field
 * @param {HTMLElement} urlInput - The URL input element
 * @param {HTMLElement} submitButton - The submit button to enable/disable
 */
function setupUrlValidation(urlInput, submitButton) {
  const validateUrl = function() {
    const url = urlInput.value;
    // check if url is a valid url starting with http or https
    const validUrl = url.match(/^(http|https):\/\/[^ "]+$/);
    submitButton.disabled = !validUrl;
  };
  
  // Attach validators to all relevant events
  urlInput.addEventListener("change", validateUrl);
  urlInput.addEventListener("keyup", validateUrl);
  urlInput.addEventListener("input", validateUrl);
}

/**
 * Sets up form validation for file input fields
 * @param {HTMLElement} fileInput - The file input element
 * @param {HTMLElement} submitButton - The submit button to enable/disable
 */
function setupFileValidation(fileInput, submitButton) {
  fileInput.addEventListener("change", function() {
    submitButton.disabled = !fileInput.files || fileInput.files.length === 0;
  });
}

/**
 * Handles showing a modal dialog with proper focus management
 * @param {string} modalId - The ID of the modal to show
 * @param {string} focusElementId - The ID of the element to focus when modal is shown
 * @param {Function} cleanupFn - Optional cleanup function when modal is hidden
 */
function showModalWithFocus(modalId, focusElementId, cleanupFn) {
  const modal = document.getElementById(modalId);
  const focusElement = document.getElementById(focusElementId);
  
  if (!modal || !focusElement) return;
  
  // Show the modal using jQuery
  $(modal).modal("show");
  
  // Use a clean approach to focus management
  const timerKey = 'focusTimer';
  
  // Clear any existing timer
  const existingTimer = $(modal).data(timerKey);
  if (existingTimer) {
    clearTimeout(existingTimer);
    $(modal).removeData(timerKey);
  }
  
  // Set new timer and store reference
  $(modal).data(timerKey, setTimeout(function() {
    focusElement.focus();
    $(modal).removeData(timerKey);
  }, 500));
  
  // Set up cleanup for when modal is hidden
  if (typeof cleanupFn === 'function') {
    // Use jQuery one() to ensure this only happens once
    $(modal).one('hidden.bs.modal', function() {
      cleanupFn();
      
      // Also clean up any timers
      const remainingTimer = $(modal).data(timerKey);
      if (remainingTimer) {
        clearTimeout(remainingTimer);
        $(modal).removeData(timerKey);
      }
    });
  }
}

// Export functions to window for browser environment
window.formHandlers = {
  uploadPdf,
  convertDocument,
  fetchWebpage,
  importSession,
  setupUrlValidation,
  setupFileValidation,
  showModalWithFocus
};

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = window.formHandlers;
}
