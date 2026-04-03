/**
 * @jest-environment jsdom
 */

// Import helpers from the shared utilities file
const { setupTestEnvironment } = require('../helpers');

describe('Select Image Module', () => {
  // Keep track of test environment for cleanup
  let testEnv;

  // Define shared mock objects for tests
  let mockCanvas;
  let mockContext;
  let mockImage;

  // Setup before each test
  beforeEach(() => {
    // Setup fake timers
    jest.useFakeTimers();

    // Create a standard test environment
    testEnv = setupTestEnvironment({
      bodyHtml: `
        <div id="image-used"></div>
        <button id="image-file" class="btn btn-primary">Select Image</button>
        <div id="imageModal" class="modal">
          <div class="modal-content">
            <h5 id="imageModalLabel">Select Image File</h5>
            <input type="file" id="imageFile" accept=".jpg,.jpeg,.png,.gif">
            <label for="imageFile">File to import (.jpg, .jpeg, .png, .gif)</label>
            <div id="select_image_error"></div>
            <button id="uploadImage" class="btn btn-primary" disabled>Upload</button>
          </div>
        </div>
        <select id="model">
          <option value="gpt-4.1">GPT-4.1</option>
          <option value="gpt-3.5-turbo">GPT-3.5</option>
        </select>
      `,
      messages: []
    });

    // Mock setAlert function
    global.setAlert = jest.fn();

    // Mock Image object
    mockImage = {
      onload: null,
      onerror: null,
      width: 800,
      height: 600,
      src: ''
    };

    global.Image = jest.fn(() => mockImage);

    // Mock canvas elements
    mockContext = {
      drawImage: jest.fn()
    };

    mockCanvas = {
      getContext: jest.fn().mockReturnValue(mockContext),
      toDataURL: jest.fn().mockReturnValue('data:image/jpeg;base64,mockBase64Data'),
      width: 0,
      height: 0
    };

    // Mock document.createElement
    document.createElement = jest.fn(type => {
      if (type === 'canvas') {
        return mockCanvas;
      }
      return document.implementation.createHTMLDocument().createElement(type);
    });

    // Mock FileReader
    global.FileReader = jest.fn().mockImplementation(() => ({
      onload: null,
      onerror: null,
      readAsDataURL: jest.fn(function(blob) {
        if (this.onload) {
          this.result = `data:${blob.type};base64,mockBase64Data`;
          this.onload();
        }
      })
    }));

    // Define global variables and functions from the module
    global.images = [];
    global.currentPdfData = null;
    global.MAX_PDF_SIZE = 35;
    global.MAX_IMAGES = 5;

    // Define the functions being tested
    global.limitImageCount = function() {
      // Keep only the last MAX_IMAGES images
      if (images.length > MAX_IMAGES) {
        // Remove oldest non-PDF images first (keep PDFs as they're often needed for context)
        const nonPdfImages = images.filter(img => img.type !== 'application/pdf');
        const pdfImages = images.filter(img => img.type === 'application/pdf');

        if (nonPdfImages.length > 0) {
          // Keep newest non-PDF images plus all PDFs
          const newestNonPdfImages = nonPdfImages.slice(-MAX_IMAGES);
          images = [...pdfImages, ...newestNonPdfImages].slice(-MAX_IMAGES);
        } else {
          // If only PDFs, just keep the newest MAX_IMAGES
          images = images.slice(-MAX_IMAGES);
        }

        // Update the display to reflect the limited images
        updateFileDisplay(images);
      }
    };

    global.fileToBase64 = function(blob, callback) {
      // Legacy callback version for backward compatibility
      if (typeof callback === 'function') {
        const reader = new FileReader();
        reader.onload = function() {
          const base64 = reader.result.split(',')[1];
          callback(base64);
        };
        reader.onerror = function(error) {
          console.error('Error reading file:', error);
          callback(null);
        };
        reader.readAsDataURL(blob);
        return;
      }

      // Return a promise for modern usage
      return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = function() {
          const base64 = reader.result.split(',')[1];
          resolve(base64);
        };
        reader.onerror = function(error) {
          console.error('Error reading file:', error);
          reject(error);
        };
        reader.readAsDataURL(blob);
      });
    };

    global.imageToBase64 = function(blob, callback) {
      // Legacy callback version for backward compatibility
      if (typeof callback === 'function') {
        const reader = new FileReader();
        reader.onload = function (e) {
          const dataUrl = reader.result;
          const image = new Image();

          image.onload = function () {
            try {
              let width = image.width;
              let height = image.height;
              const MAX_LONG_SIDE = 2000;
              const MAX_SHORT_SIDE = 768;

              // Determine the long and short sides
              const longSide = Math.max(width, height);
              const shortSide = Math.min(width, height);

              // Check if the image needs resizing
              if (longSide > MAX_LONG_SIDE || shortSide > MAX_SHORT_SIDE) {
                const longSideScale = MAX_LONG_SIDE / longSide;
                const shortSideScale = MAX_SHORT_SIDE / shortSide;
                const scale = Math.min(longSideScale, shortSideScale);
                width = width * scale;
                height = height * scale;

                // Resize the image using canvas
                const canvas = document.createElement('canvas');
                canvas.width = width;
                canvas.height = height;
                const ctx = canvas.getContext('2d');
                ctx.drawImage(image, 0, 0, width, height);
                const resizedDataUrl = canvas.toDataURL(blob.type);
                const base64 = resizedDataUrl.split(',')[1];
                callback(base64);
              } else {
                // Use original base64 if no resizing needed
                const base64 = dataUrl.split(',')[1];
                callback(base64);
              }
            } catch (error) {
              console.error('Error processing image:', error);
              callback(null);
            }
          };

          image.onerror = function(error) {
            console.error('Error loading image:', error);
            callback(null);
          };

          image.src = dataUrl;
        };

        reader.onerror = function(error) {
          console.error('Error reading file:', error);
          callback(null);
        };

        reader.readAsDataURL(blob);
        return;
      }

      // Promise version implementation omitted for test simplicity
    };

    global.updateFileDisplay = function(files) {
      const imageUsed = document.getElementById("image-used");
      if (imageUsed) imageUsed.innerHTML = ""; // Clear current display

      // Create display elements for each file
      files.forEach((file, index) => {
        if (file.type === 'application/pdf') {
          if (imageUsed) imageUsed.insertAdjacentHTML('beforeend', `
            <div class="file-container">
              <i class="fas fa-file-pdf"></i> ${file.title}
              <button class='btn btn-secondary btn-sm remove-file' data-index='${index}' tabindex="99">
                <i class="fas fa-times"></i>
              </button>
            </div>
          `);
        } else {
          if (imageUsed) imageUsed.insertAdjacentHTML('beforeend', `
            <div class="image-container">
              <img class='base64-image' alt='${file.title}' src='${file.data}' data-type='${file.type}' />
              <button class='btn btn-secondary btn-sm remove-file' data-index='${index}' tabindex="99">
                <i class="fas fa-times"></i>
              </button>
            </div>
          `);
        }
      });
    };
  });

  // Cleanup after each test
  afterEach(() => {
    testEnv.cleanup();
    jest.resetAllMocks();

    // Reset global variables
    global.images = [];
    global.currentPdfData = null;

    // Clear any timers
    jest.clearAllTimers();
  });

  describe('limitImageCount function', () => {
    it('should not modify images array when under the limit', () => {
      // Create test images
      const testImages = [
        { title: 'image1.jpg', data: 'data:image/jpeg;base64,test', type: 'image/jpeg' },
        { title: 'image2.jpg', data: 'data:image/jpeg;base64,test', type: 'image/jpeg' }
      ];

      // Set up the test
      global.images = [...testImages];

      // Run the function
      limitImageCount();

      // Verify images were not modified
      expect(global.images.length).toBe(2);
      expect(global.images).toEqual(testImages);
      // Verify updateFileDisplay was not called (no DOM change)
      const imageUsed = document.getElementById("image-used");
      expect(imageUsed.innerHTML).toBe('');
    });

    it('should keep only the most recent images when over the limit', () => {
      // Create more test images than the limit
      const testImages = [];
      for (let i = 1; i <= MAX_IMAGES + 3; i++) {
        testImages.push({
          title: `image${i}.jpg`,
          data: `data:image/jpeg;base64,test${i}`,
          type: 'image/jpeg'
        });
      }

      // Set up the test
      global.images = [...testImages];

      // Mock updateFileDisplay with jest.fn() for this test
      const originalFunction = global.updateFileDisplay;
      global.updateFileDisplay = jest.fn();

      // Run the function
      limitImageCount();

      // Restore original function
      global.updateFileDisplay = originalFunction;

      // Verify the right images were kept
      expect(global.images.length).toBe(MAX_IMAGES);

      // Should keep the last MAX_IMAGES images
      const expectedFirstImage = `image${testImages.length - MAX_IMAGES + 1}.jpg`;
      const expectedLastImage = `image${testImages.length}.jpg`;

      expect(global.images[0].title).toBe(expectedFirstImage);
      expect(global.images[MAX_IMAGES - 1].title).toBe(expectedLastImage);
    });
  });

  describe('fileToBase64 function', () => {
    it('should convert a file to base64 using callback', done => {
      // Create a mock blob
      const mockBlob = new Blob(['test'], { type: 'text/plain' });

      // Call the function with callback
      fileToBase64(mockBlob, base64 => {
        expect(base64).toBe('mockBase64Data');
        done();
      });
    });

    it('should handle FileReader errors with callback', done => {
      // Create a mock blob
      const mockBlob = new Blob(['test'], { type: 'text/plain' });

      // Mock FileReader to cause an error
      global.FileReader = jest.fn().mockImplementation(() => ({
        onload: null,
        onerror: null,
        readAsDataURL: jest.fn(function(blob) {
          if (this.onerror) {
            this.onerror(new Error('Mock error'));
          }
        })
      }));

      // Spy on console.error
      console.error = jest.fn();

      // Call the function with callback
      fileToBase64(mockBlob, base64 => {
        expect(base64).toBeNull();
        expect(console.error).toHaveBeenCalled();
        done();
      });
    });

    it('should return a promise when no callback is provided', async () => {
      // Create a mock blob
      const mockBlob = new Blob(['test'], { type: 'text/plain' });

      // Call the function without callback
      const resultPromise = fileToBase64(mockBlob);

      // Verify it returns a promise
      expect(resultPromise).toBeInstanceOf(Promise);

      // Verify the promise resolves with the correct value
      const base64 = await resultPromise;
      expect(base64).toBe('mockBase64Data');
    });
  });

  describe('imageToBase64 function', () => {
    it('should convert an image to base64 without resizing if under limits', done => {
      // Create a mock blob
      const mockBlob = new Blob(['test'], { type: 'image/jpeg' });

      // Set mock image dimensions to be under limits
      mockImage.width = 800;
      mockImage.height = 600;

      // Call the function
      imageToBase64(mockBlob, base64 => {
        expect(base64).toBe('mockBase64Data');
        // Canvas should not be created for resizing
        expect(document.createElement).not.toHaveBeenCalledWith('canvas');
        done();
      });

      // Trigger the image onload handler
      mockImage.onload();
    });

    it('should resize an image when over dimension limits', done => {
      // Create a mock blob
      const mockBlob = new Blob(['test'], { type: 'image/jpeg' });

      // Set mock image dimensions to exceed limits
      mockImage.width = 3000;
      mockImage.height = 2000;

      // Call the function
      imageToBase64(mockBlob, base64 => {
        expect(base64).toBe('mockBase64Data');
        // Canvas should be created for resizing
        expect(document.createElement).toHaveBeenCalledWith('canvas');
        expect(mockContext.drawImage).toHaveBeenCalled();
        done();
      });

      // Trigger the image onload handler
      mockImage.onload();
    });

    it('should handle errors during image processing', done => {
      // Create a mock blob
      const mockBlob = new Blob(['test'], { type: 'image/jpeg' });

      // Mock canvas to throw an error
      mockContext.drawImage = jest.fn(() => {
        throw new Error('Canvas error');
      });

      // Spy on console.error
      console.error = jest.fn();

      // Call the function
      imageToBase64(mockBlob, base64 => {
        expect(base64).toBeNull();
        expect(console.error).toHaveBeenCalled();
        done();
      });

      // Trigger the image onload handler
      mockImage.onload();
    });
  });

  describe('updateFileDisplay function', () => {
    // Use the simpler approach to test basic functionality
    it('should be defined as a function', () => {
      expect(typeof updateFileDisplay).toBe('function');

      // Simple test with empty array
      updateFileDisplay([]);
      // No assertion needed, just verifying it doesn't throw
    });
  });

  // Additional test sections for modal interactions would be added here
  // These tests might require more complex setup and are omitted for brevity

  describe('File Inputs API helpers', () => {
    // These functions are defined directly (not requiring the module)
    // Mirror the pure functions from select_image.js for unit testing

    function getDocumentIcon(mimeType) {
      const icons = {
        'application/pdf': 'fa-file-pdf',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'fa-file-excel',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'fa-file-word',
        'application/vnd.openxmlformats-officedocument.presentationml.presentation': 'fa-file-powerpoint',
        'text/csv': 'fa-file-csv',
        'text/plain': 'fa-file-lines',
        'text/markdown': 'fa-file-lines',
        'text/html': 'fa-file-code',
        'text/xml': 'fa-file-code',
        'application/json': 'fa-file-code'
      };
      return icons[mimeType] || 'fa-file';
    }

    function isDocumentType(mimeType) {
      return mimeType && !mimeType.startsWith('image/') && mimeType !== 'application/pdf';
    }

    function getMimeTypeFromExtension(ext) {
      const map = {
        'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        'csv': 'text/csv', 'txt': 'text/plain', 'md': 'text/markdown',
        'json': 'application/json', 'html': 'text/html', 'xml': 'text/xml',
        'pdf': 'application/pdf', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg',
        'png': 'image/png', 'gif': 'image/gif', 'webp': 'image/webp'
      };
      return map[(ext || '').toLowerCase()] || 'application/octet-stream';
    }

    describe('getDocumentIcon', () => {
      it('returns fa-file-pdf for PDF MIME type', () => {
        expect(getDocumentIcon('application/pdf')).toBe('fa-file-pdf');
      });

      it('returns fa-file-excel for XLSX MIME type', () => {
        expect(getDocumentIcon('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')).toBe('fa-file-excel');
      });

      it('returns fa-file-word for DOCX MIME type', () => {
        expect(getDocumentIcon('application/vnd.openxmlformats-officedocument.wordprocessingml.document')).toBe('fa-file-word');
      });

      it('returns fa-file-powerpoint for PPTX MIME type', () => {
        expect(getDocumentIcon('application/vnd.openxmlformats-officedocument.presentationml.presentation')).toBe('fa-file-powerpoint');
      });

      it('returns fa-file-csv for CSV MIME type', () => {
        expect(getDocumentIcon('text/csv')).toBe('fa-file-csv');
      });

      it('returns fa-file-code for JSON MIME type', () => {
        expect(getDocumentIcon('application/json')).toBe('fa-file-code');
      });

      it('returns fa-file for unknown MIME type', () => {
        expect(getDocumentIcon('application/unknown')).toBe('fa-file');
      });
    });

    describe('isDocumentType', () => {
      it('returns true for XLSX', () => {
        expect(isDocumentType('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')).toBe(true);
      });

      it('returns true for CSV', () => {
        expect(isDocumentType('text/csv')).toBe(true);
      });

      it('returns true for plain text', () => {
        expect(isDocumentType('text/plain')).toBe(true);
      });

      it('returns false for images', () => {
        expect(isDocumentType('image/jpeg')).toBe(false);
        expect(isDocumentType('image/png')).toBe(false);
      });

      it('returns false for PDF (PDF has its own handling)', () => {
        expect(isDocumentType('application/pdf')).toBe(false);
      });

      it('returns false for null/undefined', () => {
        expect(isDocumentType(null)).toBeFalsy();
        expect(isDocumentType(undefined)).toBeFalsy();
      });
    });

    describe('getMimeTypeFromExtension', () => {
      it('maps xlsx to correct MIME type', () => {
        expect(getMimeTypeFromExtension('xlsx'))
          .toBe('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      });

      it('maps docx to correct MIME type', () => {
        expect(getMimeTypeFromExtension('docx'))
          .toBe('application/vnd.openxmlformats-officedocument.wordprocessingml.document');
      });

      it('maps csv to text/csv', () => {
        expect(getMimeTypeFromExtension('csv')).toBe('text/csv');
      });

      it('maps json to application/json', () => {
        expect(getMimeTypeFromExtension('json')).toBe('application/json');
      });

      it('returns octet-stream for unknown extensions', () => {
        expect(getMimeTypeFromExtension('xyz')).toBe('application/octet-stream');
      });

      it('is case-insensitive', () => {
        expect(getMimeTypeFromExtension('XLSX'))
          .toBe('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      });
    });

    describe('URL protocol validation', () => {
      // Use Node's built-in URL (not jsdom's potentially overridden version)
      const NodeURL = require('url').URL;

      // Mirrors the validation logic in select_image.js URL handler
      function isValidFileUrl(urlString) {
        try {
          const url = new NodeURL(urlString);
          return url.protocol.startsWith('http');
        } catch {
          return false;
        }
      }

      it('accepts https:// URLs', () => {
        expect(isValidFileUrl('https://example.com/data.csv')).toBe(true);
      });

      it('accepts http:// URLs', () => {
        expect(isValidFileUrl('http://example.com/report.xlsx')).toBe(true);
      });

      it('rejects javascript: protocol', () => {
        expect(isValidFileUrl('javascript:alert(1)')).toBe(false);
      });

      it('rejects data: protocol', () => {
        expect(isValidFileUrl('data:text/html,<script>alert(1)</script>')).toBe(false);
      });

      it('rejects ftp: protocol', () => {
        expect(isValidFileUrl('ftp://files.example.com/doc.pdf')).toBe(false);
      });

      it('rejects invalid URLs', () => {
        expect(isValidFileUrl('not-a-url')).toBe(false);
      });
    });
  });
});
