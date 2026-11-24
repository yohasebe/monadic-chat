/**
 * Form handling utility functions for Monadic Chat
 * This module contains functions related to form validation, submission, and state management
 */

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

  const formData = new FormData();
  formData.append("docFile", doc);
  formData.append("docLabel", docLabel || "");

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 60000);
  try {
    return await window.monadicFetch.postJson("/document", formData, {
      signal: controller.signal
    });
  } finally {
    clearTimeout(timer);
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

  if (!url.match(/^(http|https):\/\/[^ "]+$/)) {
    throw new Error("Please enter a valid URL");
  }

  const formData = new FormData();
  formData.append("pageURL", url);
  formData.append("urlLabel", urlLabel || "");

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 30000);
  try {
    return await window.monadicFetch.postJson("/fetch_webpage", formData, {
      signal: controller.signal
    });
  } finally {
    clearTimeout(timer);
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
  if (typeof window.getMonadicTabId === 'function' && window.getMonadicTabId()) {
    formData.append('tab_id', window.getMonadicTabId());
  }

  return await postLoadWithPassphraseRetry(formData, file);
}

/**
 * POST /load with optional retry when the backend reports that an encrypted
 * export requires a passphrase. The user is prompted via the
 * #privacyImportPassphraseModal; on confirm we re-send the same file plus
 * the passphrase. Wrong passphrase loops back to the prompt with an error.
 */
async function postLoadWithPassphraseRetry(formData, file, lastError) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 30000);
  let data;
  try {
    data = await window.monadicFetch.postJson("/load", formData, {
      signal: controller.signal
    });
  } finally {
    clearTimeout(timer);
  }
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
    if (typeof window.getMonadicTabId === 'function' && window.getMonadicTabId()) {
      retryForm.append('tab_id', window.getMonadicTabId());
    }
    return await postLoadWithPassphraseRetry(retryForm, file, data.error || null);
  }
  return data;
}

// The dialog (MonadicDialog) of an element, when there are both.
function dialogOf(el) {
  return el && typeof window.MonadicDialog !== 'undefined' ? window.MonadicDialog.of(el) : null;
}

function suspendLoadModalForPassphrase() {
  const load = dialogOf(document.getElementById('loadModal'));
  if (load && load.isOpen) load.close('done');
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
  const load = dialogOf(document.getElementById('loadModal'));
  if (load && load.isOpen) load.close('done');
  const spinner = document.getElementById('monadic-spinner');
  if (spinner) spinner.style.display = 'none';
  const loadSpinner = document.getElementById('load-spinner');
  if (loadSpinner) loadSpinner.style.display = 'none';
  document.querySelectorAll('#loadModal button').forEach(function (b) { b.disabled = false; });
}

function promptPrivacyImportPassphrase(serverData, lastError) {
  return new Promise(function (resolve) {
    const modalEl = document.getElementById('privacyImportPassphraseModal');
    const dialog = dialogOf(modalEl);
    if (!dialog) {
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

    let settled = false;
    function settle(value) {
      if (settled) return;
      settled = true;
      cleanup();
      // The passphrase does not stay on the page once it is taken.
      if (passInput) passInput.value = '';
      resolve(value);
    }

    function onInput() {
      if (continueBtn) continueBtn.disabled = !passInput || passInput.value.length === 0;
    }
    function onContinue() {
      const value = passInput ? passInput.value : '';
      settle(value);
      dialog.close('done');
    }
    // Cancel (its data-dialog-close closes the dialog), or the dialog
    // closing in any other way: no passphrase.
    function onCancel() { settle(null); }
    function onHidden() { settle(null); }
    // Listened to only once this prompt's dialog is open, so the closing of
    // the one before (a wrong passphrase, asked again) does not end it.
    function onShown() { modalEl.addEventListener('mdialog:hidden', onHidden); }
    function cleanup() {
      if (passInput) passInput.removeEventListener('input', onInput);
      if (continueBtn) continueBtn.removeEventListener('click', onContinue);
      modalEl.removeEventListener('mdialog:shown', onShown);
      modalEl.removeEventListener('mdialog:hidden', onHidden);
      const cancelBtn = document.getElementById('privacy-import-cancel');
      if (cancelBtn) cancelBtn.removeEventListener('click', onCancel);
    }

    if (passInput) passInput.addEventListener('input', onInput);
    if (continueBtn) continueBtn.addEventListener('click', onContinue);
    const cancelBtn = document.getElementById('privacy-import-cancel');
    if (cancelBtn) cancelBtn.addEventListener('click', onCancel);
    modalEl.addEventListener('mdialog:shown', onShown);

    dialog.open();
    if (passInput) passInput.focus();
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
  
  const dialog = dialogOf(modal);
  if (!dialog) return;
  // Its field is focused as it opens (no timer to take the focus later from
  // another dialog).
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

// What the page says when an import is done: that it was imported, and,
// when the file held app state that did not fit, how many entries of it
// were left out (state_dropped from the import route). t: the translator.
function importNotice(response, t) {
  const say = typeof t === 'function' ? t : null;
  const done = say ? say('ui.messages.sessionImported') : 'Session imported successfully';
  const dropped = response && Number(response.state_dropped) > 0 ? Number(response.state_dropped) : 0;
  if (!dropped) return done;
  const left = say ? say('ui.messages.stateDropped') : "{n} entries of the app's saved state did not fit and were left out.";
  return done + ' ' + String(left).replace('{n}', String(dropped));
}

// Export functions to window for browser environment
window.formHandlers = {
  convertDocument,
  fetchWebpage,
  importSession,
  importNotice,
  setupUrlValidation,
  setupFileValidation,
  showModalWithFocus,
  promptPrivacyImportPassphrase
};

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = window.formHandlers;
}
