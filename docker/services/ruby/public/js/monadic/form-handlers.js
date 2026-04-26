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
async function uploadPdf(file, fileTitle) {
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

  // Resolve endpoint from server default (Settings).
  const postTo = async (endpoint) => {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 120000);
    try {
      const res = await fetch(endpoint, { method: "POST", body: formData, signal: controller.signal });
      clearTimeout(timer);
      if (!res.ok) throw new Error(`Upload failed: ${res.status}`);
      return await res.json();
    } catch (e) {
      clearTimeout(timer);
      throw e;
    }
  };

  try {
    const res = await fetch('/api/pdf_storage_defaults');
    const info = res.ok ? await res.json() : {};
    const mode = ((info && info.default_storage) ? info.default_storage : 'local').toLowerCase();
    const endpoint = (mode === 'cloud') ? "/openai/pdf?action=upload" : "/pdf";
    return await postTo(endpoint);
  } catch (_) {
    // Fallback to local storage
    return await postTo('/pdf');
  }
}

/**
 * Converts document files to text and adds to the message textarea
 * @param {File} doc - The document file to convert
 * @param {string} docLabel - Optional label for the document
 * @returns {Promise} - Promise resolving to the conversion response
 */
async function convertDocument(doc, docLabel) {
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

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 60000);
  try {
    const res = await fetch("/document", { method: "POST", body: formData, signal: controller.signal });
    clearTimeout(timer);
    if (!res.ok) throw new Error(`Document conversion failed: ${res.status}`);
    return await res.json();
  } catch (e) {
    clearTimeout(timer);
    throw e;
  }
}

/**
 * Fetches content from a webpage and adds to message textarea
 * @param {string} url - The URL to fetch content from
 * @param {string} urlLabel - Optional label for the URL
 * @returns {Promise} - Promise resolving to the fetch response
 */
async function fetchWebpage(url, urlLabel) {
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

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 30000);
  try {
    const res = await fetch("/fetch_webpage", { method: "POST", body: formData, signal: controller.signal });
    clearTimeout(timer);
    if (!res.ok) throw new Error(`Webpage fetch failed: ${res.status}`);
    return await res.json();
  } catch (e) {
    clearTimeout(timer);
    throw e;
  }
}

/**
 * Imports a saved session from a JSON file
 * @param {File} file - The JSON file to import
 * @returns {Promise} - Promise resolving to the import response
 */
async function importSession(file) {
  if (!file) {
    throw new Error("Please select a file to import");
  }

  // Prepare form data
  const formData = new FormData();
  formData.append('file', file);

  // Include tab_id for WebSocket session routing
  if (typeof window.tabId !== 'undefined' && window.tabId) {
    formData.append('tab_id', window.tabId);
  }

  return await postLoadWithPassphraseRetry(formData, file);
}

/**
 * POST /load with optional retry when the backend reports a Privacy Filter
 * encrypted file requires a passphrase. The user is prompted via the
 * #privacyImportPassphraseModal; on confirm we re-send the same file plus
 * the passphrase. Wrong passphrase loops back to the prompt with an error.
 */
async function postLoadWithPassphraseRetry(formData, file, lastError) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 30000);
  let res;
  try {
    res = await fetch("/load", {
      method: "POST",
      body: formData,
      signal: controller.signal,
      headers: { "X-Requested-With": "XMLHttpRequest" }
    });
    clearTimeout(timer);
  } catch (e) {
    clearTimeout(timer);
    throw e;
  }
  if (!res.ok) throw new Error(`Import failed: ${res.status}`);
  const data = await res.json();
  if (data && data.needs_passphrase) {
    // Hide the Load File modal + spinner so the passphrase prompt is the
    // sole foreground UI (avoids stacked modals + spinning indicator).
    suspendLoadModalForPassphrase();
    let passphrase;
    try {
      passphrase = await promptPrivacyImportPassphrase(data, lastError);
    } finally {
      // Re-arm the modal/spinner if we'll continue with the retry POST.
      resumeLoadModalForRetry();
    }
    if (passphrase === null) {
      // Cancelled — also dismiss the Load modal entirely so the user is back
      // to a clean state instead of staring at the disabled-buttons modal.
      hideLoadModalCompletely();
      throw new Error("Import cancelled by user");
    }
    const retryForm = new FormData();
    retryForm.append('file', file);
    retryForm.append('passphrase', passphrase);
    if (typeof window.tabId !== 'undefined' && window.tabId) {
      retryForm.append('tab_id', window.tabId);
    }
    return await postLoadWithPassphraseRetry(retryForm, file, data.error || null);
  }
  return data;
}

function suspendLoadModalForPassphrase() {
  const loadModalEl = document.getElementById('loadModal');
  if (loadModalEl && window.bootstrap && window.bootstrap.Modal) {
    window.bootstrap.Modal.getInstance(loadModalEl)?.hide();
  }
  const spinner = document.getElementById('monadic-spinner');
  if (spinner) spinner.style.display = 'none';
  const loadSpinner = document.getElementById('load-spinner');
  if (loadSpinner) loadSpinner.style.display = 'none';
}

function resumeLoadModalForRetry() {
  // Re-show the spinner so the user knows the next decrypt attempt is in
  // flight. We do NOT reopen loadModal — passphrase modal stays primary.
  const spinner = document.getElementById('monadic-spinner');
  if (spinner) spinner.style.display = '';
}

function hideLoadModalCompletely() {
  const loadModalEl = document.getElementById('loadModal');
  if (loadModalEl && window.bootstrap && window.bootstrap.Modal) {
    window.bootstrap.Modal.getInstance(loadModalEl)?.hide();
  }
  const spinner = document.getElementById('monadic-spinner');
  if (spinner) spinner.style.display = 'none';
  const loadSpinner = document.getElementById('load-spinner');
  if (loadSpinner) loadSpinner.style.display = 'none';
  document.querySelectorAll('#loadModal button').forEach(function (b) { b.disabled = false; });
}

function promptPrivacyImportPassphrase(serverData, lastError) {
  return new Promise(function (resolve) {
    const modalEl = document.getElementById('privacyImportPassphraseModal');
    if (!modalEl || !window.bootstrap || !window.bootstrap.Modal) {
      const fallback = window.prompt(
        (lastError === 'wrong_passphrase' ? 'Wrong passphrase. ' : '') +
        'Enter passphrase for the encrypted privacy export:'
      );
      resolve(fallback === null || fallback === undefined ? null : String(fallback));
      return;
    }

    const errEl = document.getElementById('privacy-import-error');
    const headerEl = document.getElementById('privacy-import-header-info');
    const passInput = document.getElementById('privacy-import-passphrase');
    const continueBtn = document.getElementById('privacy-import-continue');

    if (errEl) {
      if (lastError === 'wrong_passphrase') {
        errEl.textContent = 'Wrong passphrase. Please try again.';
        errEl.style.display = '';
      } else {
        errEl.textContent = '';
        errEl.style.display = 'none';
      }
    }
    if (headerEl) {
      const h = serverData && serverData.header ? serverData.header : {};
      const lines = [];
      if (h.app_name) lines.push('App: ' + h.app_name);
      if (h.created_at) lines.push('Exported: ' + h.created_at);
      if (h.message_count !== undefined) lines.push('Messages: ' + h.message_count);
      headerEl.textContent = lines.join(' · ');
    }
    if (passInput) passInput.value = '';
    if (continueBtn) continueBtn.disabled = true;

    const modal = window.bootstrap.Modal.getOrCreateInstance(modalEl);

    function onInput() {
      if (continueBtn) continueBtn.disabled = !passInput || passInput.value.length === 0;
    }
    function onContinue() {
      cleanup();
      const value = passInput ? passInput.value : '';
      modal.hide();
      resolve(value);
    }
    function onCancel() {
      cleanup();
      resolve(null);
    }
    function cleanup() {
      if (passInput) passInput.removeEventListener('input', onInput);
      if (continueBtn) continueBtn.removeEventListener('click', onContinue);
      modalEl.removeEventListener('hidden.bs.modal', onHidden);
      const cancelBtn = document.getElementById('privacy-import-cancel');
      if (cancelBtn) cancelBtn.removeEventListener('click', onCancel);
    }
    function onHidden() {
      // Resolve null only if neither continue nor explicit cancel resolved already.
      cleanup();
      resolve(null);
    }

    if (passInput) passInput.addEventListener('input', onInput);
    if (continueBtn) continueBtn.addEventListener('click', onContinue);
    const cancelBtn = document.getElementById('privacy-import-cancel');
    if (cancelBtn) cancelBtn.addEventListener('click', onCancel);
    modalEl.addEventListener('hidden.bs.modal', onHidden, { once: true });

    modal.show();
    setTimeout(function () { if (passInput) passInput.focus(); }, 200);
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
  const modal = $id(modalId);
  const focusElement = $id(focusElementId);
  
  if (!modal || !focusElement) return;
  
  // Show the modal using Bootstrap API
  const bsModal = bootstrap.Modal.getOrCreateInstance(modal);
  bsModal.show();

  // Use a clean approach to focus management
  const timerKey = 'focusTimer';

  // Clear any existing timer
  const existingTimer = modal.dataset[timerKey];
  if (existingTimer) {
    clearTimeout(Number(existingTimer));
    delete modal.dataset[timerKey];
  }

  // Set new timer and store reference
  modal.dataset[timerKey] = setTimeout(function() {
    focusElement.focus();
    delete modal.dataset[timerKey];
  }, 500);

  // Set up cleanup for when modal is hidden
  if (typeof cleanupFn === 'function') {
    // Use once option to ensure this only happens once
    modal.addEventListener('hidden.bs.modal', function onHidden() {
      modal.removeEventListener('hidden.bs.modal', onHidden);
      cleanupFn();

      // Also clean up any timers
      const remainingTimer = modal.dataset[timerKey];
      if (remainingTimer) {
        clearTimeout(Number(remainingTimer));
        delete modal.dataset[timerKey];
      }
    });
  }
}

/**
 * Uploads an audio or MIDI file for analysis
 * @param {File} file - The audio/MIDI file to upload
 * @returns {Promise} - Promise resolving to the upload response
 */
async function uploadAudioFile(file) {
  if (!file) {
    throw new Error("Please select an audio or MIDI file");
  }
  const formData = new FormData();
  formData.append("audioFile", file);
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 60000);
  try {
    const res = await fetch("/upload_audio", { method: "POST", body: formData, signal: controller.signal });
    clearTimeout(timer);
    if (!res.ok) throw new Error(`Audio upload failed: ${res.status}`);
    return await res.json();
  } catch (e) {
    clearTimeout(timer);
    throw e;
  }
}

// Export functions to window for browser environment
window.formHandlers = {
  uploadPdf,
  convertDocument,
  fetchWebpage,
  importSession,
  uploadAudioFile,
  setupUrlValidation,
  setupFileValidation,
  showModalWithFocus
};

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = window.formHandlers;
}
