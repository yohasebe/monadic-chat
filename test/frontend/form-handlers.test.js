/**
 * @jest-environment jsdom
 */

// monadic-fetch is a dependency of form-handlers since H5-1 migration;
// load it before form-handlers so window.monadicFetch is wired up.
require('../../docker/services/ruby/public/js/monadic/monadic-fetch.js');

// Mock DOM APIs
// Create a proper FormData mock with better tracking
const mockAppend = jest.fn();
const mockFormDataInstance = { append: mockAppend };

// Add tracking capability to FormData
const FormDataMock = jest.fn().mockImplementation(() => {
  return mockFormDataInstance;
});

// Set mock properties directly on the constructor function
FormDataMock.mock = {
  instances: [mockFormDataInstance],
  calls: [[]]
};

// Explicitly set append method on the instances array for test checks
mockFormDataInstance.append.mockImplementation = jest.fn();
mockFormDataInstance.append.mock = { calls: [] };

// Assign to global and ensure it has the mock structure tests expect
global.FormData = FormDataMock;

// Mock EventTarget
class MockEventTarget {
  constructor() {
    this.listeners = {};
  }

  addEventListener(event, handler) {
    if (!this.listeners[event]) this.listeners[event] = [];
    this.listeners[event].push(handler);
  }

  dispatchEvent(event) {
    const handlers = this.listeners[event.type] || [];
    handlers.forEach(handler => handler(event));
  }
}

// Mock AbortController for jsdom
global.AbortController = class {
  constructor() {
    this.signal = { aborted: false };
  }
  abort() {
    this.signal.aborted = true;
  }
};

// Mock document object
document.getElementById = jest.fn();

// Import the module under test
const formHandlers = require('../../docker/services/ruby/public/js/monadic/form-handlers');

// Helper: create a mock fetch that returns a JSON success response.
// Shape matches what monadicFetch reads: ok / status / headers.get /
// text(). The text() body must be a JSON string so monadicFetch's
// internal JSON.parse succeeds.
function createFetchMock(responseData = { success: true }) {
  return jest.fn().mockImplementation(() => Promise.resolve({
    ok: true,
    status: 200,
    statusText: 'OK',
    headers: {
      get(name) {
        return name.toLowerCase() === 'content-type' ? 'application/json' : null;
      }
    },
    text: () => Promise.resolve(JSON.stringify(responseData)),
    json: () => Promise.resolve(responseData)
  }));
}

// Reset mocks before each test
beforeEach(() => {
  jest.clearAllMocks();
  // Reset fetch mock
  delete global.fetch;
});

describe('Form Handlers', () => {
  describe('convertDocument', () => {
    it('should process document conversion', async () => {
      // Override FormData implementation for this test
      const origFormData = global.FormData;
      const formAppendMock = jest.fn();

      class MockFormData {
        constructor() {
          this.append = formAppendMock;
        }
      }

      global.FormData = MockFormData;

      // Mock fetch to resolve with success
      global.fetch = createFetchMock();

      // Create a mock document file
      const docFile = { type: 'application/msword' };

      // Call the function
      await formHandlers.convertDocument(docFile, 'Test Document');

      // Verify FormData was created and append was called
      expect(formAppendMock).toHaveBeenCalledWith('docFile', docFile);
      expect(formAppendMock).toHaveBeenCalledWith('docLabel', 'Test Document');

      // Verify fetch was called with correct parameters
      expect(global.fetch).toHaveBeenCalled();
      expect(global.fetch.mock.calls[0][0]).toBe('/document');
      expect(global.fetch.mock.calls[0][1].method).toBe('POST');

      // Restore original FormData
      global.FormData = origFormData;
    });

    it('should reject unsupported file types', async () => {
      // Create a mock binary file
      const binaryFile = { type: 'application/octet-stream' };

      // Use a try-catch block instead of expecting a rejection
      try {
        await formHandlers.convertDocument(binaryFile, 'Invalid file');
        // If we reach here, the test should fail
        expect('this should not be reached').toBe('test should have thrown');
      } catch (error) {
        // Verify the error message
        expect(error.message).toBe('Unsupported file type');
      }
    });

    it('should reject null file input', async () => {
      // Use a try-catch block instead of expecting a rejection
      try {
        await formHandlers.convertDocument(null, 'Missing file');
        // If we reach here, the test should fail
        expect('this should not be reached').toBe('test should have thrown');
      } catch (error) {
        // Verify the error message
        expect(error.message).toBe('Please select a document file to convert');
      }
    });
  });

  describe('fetchWebpage', () => {
    it('should process valid URLs', async () => {
      // Override FormData implementation for this test
      const origFormData = global.FormData;
      const formAppendMock = jest.fn();

      class MockFormData {
        constructor() {
          this.append = formAppendMock;
        }
      }

      global.FormData = MockFormData;

      // Mock fetch to resolve with success
      global.fetch = createFetchMock();

      // Call the function with a valid URL
      await formHandlers.fetchWebpage('https://example.com', 'Example site');

      // Verify FormData was created and append was called
      expect(formAppendMock).toHaveBeenCalledWith('pageURL', 'https://example.com');
      expect(formAppendMock).toHaveBeenCalledWith('urlLabel', 'Example site');

      // Verify fetch was called with correct parameters
      expect(global.fetch).toHaveBeenCalled();
      expect(global.fetch.mock.calls[0][0]).toBe('/fetch_webpage');
      expect(global.fetch.mock.calls[0][1].method).toBe('POST');

      // Restore original FormData
      global.FormData = origFormData;
    });

    it('should reject invalid URLs', async () => {
      // Call the function with an invalid URL and verify error
      try {
        await formHandlers.fetchWebpage('invalid-url', 'Invalid URL');
        expect('this should not be reached').toBe('test should have thrown');
      } catch (error) {
        expect(error.message).toBe('Please enter a valid URL');
      }
    });

    it('should reject empty URLs', async () => {
      // Should reject an empty URL
      try {
        await formHandlers.fetchWebpage('', 'Empty URL');
        expect('this should not be reached').toBe('test should have thrown');
      } catch (error) {
        expect(error.message).toBe('Please specify the URL of the page to fetch');
      }
    });

    it('should reject null URLs', async () => {
      // Should reject null URL
      try {
        await formHandlers.fetchWebpage(null, 'Null URL');
        expect('this should not be reached').toBe('test should have thrown');
      } catch (error) {
        expect(error.message).toBe('Please specify the URL of the page to fetch');
      }
    });

    it('should handle URLs with or without label', async () => {
      // Override FormData implementation for this test
      const origFormData = global.FormData;
      const formAppendMock = jest.fn();

      class MockFormData {
        constructor() {
          this.append = formAppendMock;
        }
      }

      global.FormData = MockFormData;

      // Mock fetch to resolve with success
      global.fetch = createFetchMock();

      // Without label
      await formHandlers.fetchWebpage('https://example.com');
      expect(formAppendMock).toHaveBeenCalledWith('urlLabel', '');

      // Clear mocks between calls
      formAppendMock.mockClear();

      // With label
      await formHandlers.fetchWebpage('https://example.com', 'Example');
      expect(formAppendMock).toHaveBeenCalledWith('urlLabel', 'Example');

      // Restore original FormData
      global.FormData = origFormData;
    });
  });

  describe('importSession', () => {
    it('should process session import with tab_id', async () => {
      // Override FormData implementation for this test
      const origFormData = global.FormData;
      const formAppendMock = jest.fn();

      class MockFormData {
        constructor() {
          this.append = formAppendMock;
        }
      }

      global.FormData = MockFormData;

      // The tab id as ws-tab-id.js provides it (the WebSocket's own)
      const origGetTabId = window.getMonadicTabId;
      window.getMonadicTabId = () => 'test-tab-id-12345';

      // Mock fetch to resolve with success
      global.fetch = createFetchMock();

      // Create a mock JSON file
      const jsonFile = { name: 'session.json', type: 'application/json' };

      // Call the function
      await formHandlers.importSession(jsonFile);

      // Verify FormData was created and append was called with file
      expect(formAppendMock).toHaveBeenCalledWith('file', jsonFile);

      // Verify tab_id was appended for WebSocket session routing
      expect(formAppendMock).toHaveBeenCalledWith('tab_id', 'test-tab-id-12345');

      // Verify fetch was called with correct parameters
      expect(global.fetch).toHaveBeenCalled();
      expect(global.fetch.mock.calls[0][0]).toBe('/load?tab_id=test-tab-id-12345');
      expect(global.fetch.mock.calls[0][1].method).toBe('POST');

      // Restore originals
      global.FormData = origFormData;
      window.getMonadicTabId = origGetTabId;
    });

    it('should reject null file input', async () => {
      // Use a try-catch block instead of expecting a rejection
      try {
        await formHandlers.importSession(null);
        expect('this should not be reached').toBe('test should have thrown');
      } catch (error) {
        expect(error.message).toBe('Please select a file to import');
      }
    });
  });

  describe('setupUrlValidation', () => {
    it('should add validators to URL inputs', () => {
      // Create mock elements
      const urlInput = new MockEventTarget();
      urlInput.value = '';
      const submitButton = { disabled: true };

      // Call the function
      formHandlers.setupUrlValidation(urlInput, submitButton);

      // Verify event listeners were added
      expect(urlInput.listeners.change).toBeDefined();
      expect(urlInput.listeners.keyup).toBeDefined();
      expect(urlInput.listeners.input).toBeDefined();

      // Test validation with invalid URL
      urlInput.value = 'invalid-url';
      urlInput.dispatchEvent({ type: 'input' });
      expect(submitButton.disabled).toBe(true);

      // Test validation with valid URL
      urlInput.value = 'https://example.com';
      urlInput.dispatchEvent({ type: 'input' });
      expect(submitButton.disabled).toBe(false);
    });
  });

  describe('setupFileValidation', () => {
    it('should add validators to file inputs', () => {
      // Create mock elements
      const fileInput = new MockEventTarget();
      fileInput.files = [];
      const submitButton = { disabled: true };

      // Call the function
      formHandlers.setupFileValidation(fileInput, submitButton);

      // Verify event listener was added
      expect(fileInput.listeners.change).toBeDefined();

      // Test validation with no files
      fileInput.dispatchEvent({ type: 'change' });
      expect(submitButton.disabled).toBe(true);

      // Test validation with a file
      fileInput.files = [{ name: 'test.pdf' }];
      fileInput.dispatchEvent({ type: 'change' });
      expect(submitButton.disabled).toBe(false);
    });
  });

  describe('showModalWithFocus', () => {
    // A fake MonadicDialog: open() tells mdialog:shown at once, close()
    // tells mdialog:hidden after it, as the real one does.
    beforeEach(() => {
      // The document's own lookup (tests above replace it).
      delete document.getElementById;
      window.MonadicDialog = {
        of: (el) => ({
          open: jest.fn(() => { el.dispatchEvent(new CustomEvent('mdialog:shown')); return true; }),
          close: () => Promise.resolve(true).then(() => { el.dispatchEvent(new CustomEvent('mdialog:hidden')); return true; })
        })
      };
    });

    afterEach(() => {
      delete window.MonadicDialog;
      document.body.innerHTML = '';
    });

    it('opens the dialog and focuses its field at once (no timer to take the focus later)', () => {
      document.body.innerHTML = '<dialog id="testModal"><input id="focusInput"></dialog>';
      jest.useFakeTimers();
      formHandlers.showModalWithFocus('testModal', 'focusInput');
      expect(document.activeElement.id).toBe('focusInput');
      expect(jest.getTimerCount()).toBe(0);
      jest.useRealTimers();
    });

    it('runs its cleanup once the dialog it opened has closed, and only then', async () => {
      document.body.innerHTML = '<dialog id="testModal"><input id="focusInput"></dialog>';
      const modal = document.getElementById('testModal');
      const cleanupFn = jest.fn();
      formHandlers.showModalWithFocus('testModal', 'focusInput', cleanupFn);
      expect(cleanupFn).not.toHaveBeenCalled();
      await window.MonadicDialog.of(modal).close();
      expect(cleanupFn).toHaveBeenCalledTimes(1);
      modal.dispatchEvent(new CustomEvent('mdialog:hidden'));
      expect(cleanupFn).toHaveBeenCalledTimes(1);
    });
  });

  describe('promptPrivacyImportPassphrase', () => {
    const VIEW = `<dialog id="privacyImportPassphraseModal">
      <div id="privacy-import-error"></div><div id="privacy-import-header-info"></div>
      <input id="privacy-import-passphrase"><button id="privacy-import-cancel" data-dialog-close>Cancel</button>
      <button id="privacy-import-continue">Continue</button></dialog>`;
    let closings;

    beforeEach(() => {
      delete document.getElementById;
      document.body.innerHTML = VIEW;
      closings = [];
      const el = document.getElementById('privacyImportPassphraseModal');
      // As the real one: its closing tells mdialog:hidden later (a task),
      // and opened again meanwhile it opens once it has closed.
      let closing = null;
      const fake = {
        open: () => {
          if (closing) { closing.then(() => fake.open()); return true; }
          el.dispatchEvent(new CustomEvent('mdialog:shown'));
          return true;
        },
        close: () => {
          closing = new Promise((r) => setTimeout(r, 0)).then(() => {
            closing = null;
            el.dispatchEvent(new CustomEvent('mdialog:hidden'));
            return true;
          });
          closings.push(closing);
          return closing;
        }
      };
      window.MonadicDialog = { of: () => fake };
    });

    afterEach(() => { delete window.MonadicDialog; });

    const type = (text) => {
      const input = document.getElementById('privacy-import-passphrase');
      input.value = text;
      input.dispatchEvent(new Event('input'));
    };

    it('gives what was typed on Continue, and null on Cancel', async () => {
      const first = formHandlers.promptPrivacyImportPassphrase({}, null);
      expect(document.activeElement.id).toBe('privacy-import-passphrase');
      type('secret');
      document.getElementById('privacy-import-continue').click();
      await expect(first).resolves.toBe('secret');

      const second = formHandlers.promptPrivacyImportPassphrase({}, null);
      document.getElementById('privacy-import-cancel').click();
      await expect(second).resolves.toBeNull();
    });

    it('asked again after a wrong passphrase, the closing of the one before does not end the new one', async () => {
      const first = formHandlers.promptPrivacyImportPassphrase({}, null);
      type('wrong');
      document.getElementById('privacy-import-continue').click();
      await expect(first).resolves.toBe('wrong');
      // Asked again before the first dialog has told that it closed.
      const again = formHandlers.promptPrivacyImportPassphrase({}, 'wrong_passphrase');
      await Promise.all(closings);
      type('right');
      document.getElementById('privacy-import-continue').click();
      await expect(again).resolves.toBe('right');
      expect(document.getElementById('privacy-import-error').textContent).toMatch(/Wrong passphrase/);
    });
  });
});

describe('importNotice', () => {
  const formHandlers = require('../../docker/services/ruby/public/js/monadic/form-handlers.js');
  const t = (key) => ({
    'ui.messages.sessionImported': 'Imported.',
    'ui.messages.stateDropped': '{n} entries were left out.'
  })[key];

  it('says the session was imported', () => {
    expect(formHandlers.importNotice({ success: true, state_dropped: 0 }, t)).toBe('Imported.');
    expect(formHandlers.importNotice({ success: true }, t)).toBe('Imported.');
  });

  it('says how many entries of the app state were left out', () => {
    expect(formHandlers.importNotice({ success: true, state_dropped: 2 }, t)).toBe('Imported. 2 entries were left out.');
  });

  it('has its own words without a translator', () => {
    expect(formHandlers.importNotice({ state_dropped: 1 }, null)).toContain('1 entries');
  });
});

describe('the dropped-state notice in every language', () => {
  const fs = require('fs');
  const path = require('path');
  const text = fs.readFileSync(path.join(__dirname, '../../docker/services/ruby/public/js/i18n/translations.js'), 'utf8');
  const blocks = text.split(/\n {2}(?=\w\w: \{\n {4}ui: \{)/).slice(1);

  it('names the count in each of the seven languages', () => {
    expect(blocks.map((b) => b.slice(0, 2))).toEqual(['en', 'ja', 'zh', 'ko', 'es', 'fr', 'de']);
    blocks.forEach((block) => {
      expect(block).toMatch(/stateDropped: "[^"]*\{n\}[^"]*"/);
    });
  });
});
