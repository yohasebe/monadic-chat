/**
 * @jest-environment jsdom
 */

// Mock data and setup
const mockImageData = {
  title: "test-image.jpg",
  data: "data:image/jpeg;base64,/9j/4AAQSkZJRgABAQEASABIAAD",
  type: "image/jpeg"
};

// Mock bootstrap
const mockModalInstance = { show: jest.fn(), hide: jest.fn() };
global.bootstrap = {
  Modal: {
    getOrCreateInstance: jest.fn().mockReturnValue(mockModalInstance)
  }
};

// Mock canvas context
const mockCtx = {
  fillStyle: "",
  fillRect: jest.fn(),
  drawImage: jest.fn(),
  beginPath: jest.fn(),
  arc: jest.fn(),
  fill: jest.fn(),
  globalAlpha: 1.0,
  save: jest.fn(),
  restore: jest.fn(),
  clip: jest.fn(),
  getImageData: jest.fn().mockReturnValue({
    data: new Uint8Array(400)
  }),
  putImageData: jest.fn()
};

// Global utility functions
global.setAlert = jest.fn();
global.updateFileDisplay = jest.fn();
global.images = [];

// Proper Image mock
global.Image = function() {
  this.src = "";
  this.width = 200;
  this.height = 150;

  let onloadFn = null;
  Object.defineProperty(this, 'onload', {
    get: function() { return onloadFn; },
    set: function(fn) {
      onloadFn = fn;
      if (this.src) {
        setTimeout(() => { if (onloadFn) onloadFn(); }, 0);
      }
    }
  });
};

// Import the module under test
const maskEditor = require('../../docker/services/ruby/public/js/monadic/mask_editor');

describe('Mask Editor', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    global.images = [];
    window.currentMaskData = null;

    // Setup DOM for each test - mask_editor creates the modal via insertAdjacentHTML
    document.body.innerHTML = '';

    // Mock getElementById for canvas
    const origGetById = document.getElementById.bind(document);
    jest.spyOn(document, 'getElementById').mockImplementation(function(id) {
      if (id === 'maskCanvas') {
        return {
          getContext: jest.fn().mockReturnValue(mockCtx),
          addEventListener: jest.fn(),
          getBoundingClientRect: jest.fn().mockReturnValue({
            left: 0, top: 0, width: 200, height: 200
          }),
          width: 200,
          height: 200,
          style: { width: "", height: "" }
        };
      }
      // For modal and other elements, check the real DOM first
      var el = origGetById(id);
      return el;
    });

    // Mock querySelector for .modal-body .col-md-8
    jest.spyOn(document, 'querySelector').mockImplementation(function(selector) {
      if (selector === '.modal-body .col-md-8') {
        return { clientWidth: 620 };
      }
      return null;
    });
  });

  afterEach(() => {
    jest.restoreAllMocks();
    document.body.innerHTML = '';
  });

  describe('openMaskEditor', () => {
    it('should create and display the modal properly', () => {
      maskEditor.openMaskEditor(mockImageData);

      // Modal HTML should be inserted into body
      expect(document.body.innerHTML).toContain('maskEditorModal');
      // Bootstrap modal show should be called
      expect(bootstrap.Modal.getOrCreateInstance).toHaveBeenCalled();
      expect(mockModalInstance.show).toHaveBeenCalled();
    });

    it('should register canvas event listeners', () => {
      maskEditor.openMaskEditor(mockImageData);

      // getElementById('maskCanvas') should have been called
      expect(document.getElementById).toHaveBeenCalledWith('maskCanvas');
    });
  });
});
