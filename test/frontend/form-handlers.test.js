/**
 * @jest-environment jsdom
 */

// Mock DOM APIs - Note: jQuery is mocked in setup.js
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

// Helper: create a mock fetch that returns JSON responses based on URL
function createFetchMock(responseData = { success: true }) {
  return jest.fn().mockImplementation((url) => {
    // For uploadPdf: /api/pdf_storage_defaults returns storage mode
    if (url === '/api/pdf_storage_defaults') {
      return Promise.resolve({
        ok: true,
        json: () => Promise.resolve({ default_storage: 'local' })
      });
    }
    // Default: return success JSON
    return Promise.resolve({
      ok: true,
      json: () => Promise.resolve(responseData)
    });
  });
}

// Reset mocks before each test
beforeEach(() => {
  jest.clearAllMocks();
  // Reset fetch mock
  delete global.fetch;
});

describe('Form Handlers', () => {
  describe('uploadPdf', () => {
    it('should validate PDF file type', async () => {
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

      // Create a mock PDF file
      const pdfFile = { type: 'application/pdf' };

      // Call the function
      await formHandlers.uploadPdf(pdfFile, 'Test PDF');

      // Verify FormData was created and append was called
      expect(formAppendMock).toHaveBeenCalledWith('pdfFile', pdfFile);
      expect(formAppendMock).toHaveBeenCalledWith('pdfTitle', 'Test PDF');

      // Verify fetch was called — first for storage defaults, then for /pdf
      expect(global.fetch).toHaveBeenCalled();
      const fetchCalls = global.fetch.mock.calls;
      // Should have called /api/pdf_storage_defaults first
      expect(fetchCalls[0][0]).toBe('/api/pdf_storage_defaults');
      // Then /pdf for the actual upload
      expect(fetchCalls[1][0]).toBe('/pdf');
      expect(fetchCalls[1][1].method).toBe('POST');

      // Restore original FormData
      global.FormData = origFormData;
    });

    it('should reject non-PDF files', async () => {
      // Create a mock non-PDF file
      const textFile = { type: 'text/plain' };

      // Use a try-catch block instead of expecting a rejection
      try {
        await formHandlers.uploadPdf(textFile, 'Invalid file');
        // If we reach here, the test should fail
        expect('this should not be reached').toBe('test should have thrown');
      } catch (error) {
        // Verify the error message
        expect(error.message).toBe('Please select a PDF file');
      }
    });

    it('should reject null file input', async () => {
      // Use a try-catch block instead of expecting a rejection
      try {
        await formHandlers.uploadPdf(null, 'Missing file');
        // If we reach here, the test should fail
        expect('this should not be reached').toBe('test should have thrown');
      } catch (error) {
        // Verify the error message
        expect(error.message).toBe('Please select a PDF file to upload');
      }
    });
  });

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

      // Mock window.tabId
      const origTabId = window.tabId;
      window.tabId = 'test-tab-id-12345';

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
      expect(global.fetch.mock.calls[0][0]).toBe('/load');
      expect(global.fetch.mock.calls[0][1].method).toBe('POST');

      // Restore originals
      global.FormData = origFormData;
      window.tabId = origTabId;
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

  describe('uploadAudioFile', () => {
    it('should upload audio file with correct parameters', async () => {
      const origFormData = global.FormData;
      const formAppendMock = jest.fn();

      class MockFormData {
        constructor() {
          this.append = formAppendMock;
        }
      }

      global.FormData = MockFormData;

      // Mock fetch to resolve with success
      global.fetch = createFetchMock({ success: true, filename: 'song.mp3' });

      const audioFile = { name: 'song.mp3', type: 'audio/mpeg' };
      await formHandlers.uploadAudioFile(audioFile);

      expect(formAppendMock).toHaveBeenCalledWith('audioFile', audioFile);
      expect(global.fetch).toHaveBeenCalled();
      expect(global.fetch.mock.calls[0][0]).toBe('/upload_audio');
      expect(global.fetch.mock.calls[0][1].method).toBe('POST');

      global.FormData = origFormData;
    });

    it('should upload MIDI file', async () => {
      const origFormData = global.FormData;
      const formAppendMock = jest.fn();

      class MockFormData {
        constructor() {
          this.append = formAppendMock;
        }
      }

      global.FormData = MockFormData;

      // Mock fetch to resolve with success
      global.fetch = createFetchMock({ success: true, filename: 'piece.mid' });

      const midiFile = { name: 'piece.mid', type: 'audio/midi' };
      await formHandlers.uploadAudioFile(midiFile);

      expect(formAppendMock).toHaveBeenCalledWith('audioFile', midiFile);
      expect(global.fetch).toHaveBeenCalled();

      global.FormData = origFormData;
    });

    it('should reject null file input', async () => {
      try {
        await formHandlers.uploadAudioFile(null);
        expect('this should not be reached').toBe('test should have thrown');
      } catch (error) {
        expect(error.message).toBe('Please select an audio or MIDI file');
      }
    });

    it('should use AbortController for timeout', async () => {
      const origFormData = global.FormData;
      class MockFormData {
        constructor() { this.append = jest.fn(); }
      }
      global.FormData = MockFormData;

      // Mock fetch and capture the signal option
      global.fetch = jest.fn().mockImplementation((url, options) => {
        // Verify that an AbortController signal was passed
        expect(options.signal).toBeDefined();
        return Promise.resolve({
          ok: true,
          json: () => Promise.resolve({ success: true, filename: 'test.wav' })
        });
      });

      const audioFile = { name: 'test.wav', type: 'audio/wav' };
      await formHandlers.uploadAudioFile(audioFile);

      expect(global.fetch).toHaveBeenCalled();

      global.FormData = origFormData;
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
    beforeEach(() => {
      // Mock setTimeout to execute immediately
      jest.useFakeTimers();

      // Mock bootstrap.Modal
      global.bootstrap = {
        Modal: {
          getOrCreateInstance: jest.fn().mockReturnValue({
            show: jest.fn()
          })
        }
      };
    });

    afterEach(() => {
      jest.useRealTimers();
      delete global.bootstrap;
    });

    it('should show modal and set focus', () => {
      // Create mocks
      const focusElement = { focus: jest.fn() };
      const modalElement = document.createElement('div');
      modalElement.dataset = {};

      // Mock getElementById to return our mocks
      document.getElementById = jest.fn().mockImplementation(id => {
        if (id === 'testModal') return modalElement;
        if (id === 'focusInput') return focusElement;
        return null;
      });

      // Call the function we're testing
      formHandlers.showModalWithFocus('testModal', 'focusInput');

      // Run all pending timers immediately
      jest.runAllTimers();

      // Verify behavior
      expect(document.getElementById).toHaveBeenCalledWith('testModal');
      expect(document.getElementById).toHaveBeenCalledWith('focusInput');
      expect(global.bootstrap.Modal.getOrCreateInstance).toHaveBeenCalledWith(modalElement);

      // Verify focus is set (after timer)
      expect(focusElement.focus).toHaveBeenCalled();
    });

    it('should handle cleanup function when modal is hidden', () => {
      // Create mocks
      const focusElement = { focus: jest.fn() };
      const modalElement = document.createElement('div');
      modalElement.dataset = {};

      // Make addEventListener immediately call the callback for hidden.bs.modal
      const origAddEventListener = modalElement.addEventListener.bind(modalElement);
      modalElement.addEventListener = jest.fn().mockImplementation((event, callback) => {
        if (event === 'hidden.bs.modal' && callback) {
          // Immediately invoke the callback to simulate modal hidden
          callback();
        }
        origAddEventListener(event, callback);
      });

      // Mock getElementById to return our mocks
      document.getElementById = jest.fn().mockImplementation(id => {
        if (id === 'testModal') return modalElement;
        if (id === 'focusInput') return focusElement;
        return null;
      });

      // Create cleanup function
      const cleanupFn = jest.fn();

      // Call the function we're testing
      formHandlers.showModalWithFocus('testModal', 'focusInput', cleanupFn);

      // Run all pending timers
      jest.runAllTimers();

      // Verify cleanup was called
      expect(cleanupFn).toHaveBeenCalled();
    });
  });
});
