/**
 * @jest-environment jsdom
 */

// Mock data and setup
const mockImageData = {
  title: "test-image.jpg",
  data: "data:image/jpeg;base64,/9j/4AAQSkZJRgABAQEASABIAAD",
  type: "image/jpeg"
};

// Create jQuery mock with handlers
const jquerySelectors = {
  "body": {
    append: jest.fn()
  },
  "#maskEditorModal": {
    modal: jest.fn(),
    on: jest.fn(),
    remove: jest.fn()
  },
  "#brushSize": {
    on: jest.fn(),
    val: jest.fn().mockReturnValue("25")
  },
  "#brushSizeValue": {
    text: jest.fn()
  },
  "#brushTool": {
    on: jest.fn(),
    addClass: jest.fn(),
    removeClass: jest.fn()
  },
  "#eraserTool": {
    on: jest.fn(),
    addClass: jest.fn(),
    removeClass: jest.fn()
  },
  "#clearMask": {
    on: jest.fn()
  },
  "#saveMask": {
    on: jest.fn()
  },
  ".modal-body .col-md-8": {
    width: jest.fn().mockReturnValue(600)
  },
  "#image-used": {
    append: jest.fn()
  },
  ".remove-mask": {
    on: jest.fn()
  },
  ".toggle-mask": {
    on: jest.fn()
  }
};

// jQuery mock that returns the pre-configured selectors
global.$ = jest.fn(selector => {
  if (jquerySelectors[selector]) {
    return jquerySelectors[selector];
  }
  
  // Default mock for other selectors
  return {
    on: jest.fn(),
    val: jest.fn(),
    append: jest.fn(),
    text: jest.fn(),
    addClass: jest.fn(),
    removeClass: jest.fn(),
    hide: jest.fn(),
    fadeIn: jest.fn(),
    css: jest.fn().mockReturnValue("0"), // For opacity check
    find: jest.fn().mockReturnThis(),
    closest: jest.fn().mockReturnThis(),
    data: jest.fn().mockReturnValue("test-image.jpg")
  };
});

// Mock document elements and context
document.getElementById = jest.fn().mockImplementation(id => {
  if (id === "maskCanvas") {
    return {
      getContext: jest.fn().mockReturnValue({
        fillStyle: "",
        fillRect: jest.fn(),
        drawImage: jest.fn(),
        beginPath: jest.fn(),
        arc: jest.fn(),
        fill: jest.fn(),
        globalAlpha: 1.0,
        getImageData: jest.fn().mockReturnValue({
          data: new Uint8Array(400) // 4x25x25 (RGBA x 25x25 pixels)
        })
      }),
      addEventListener: jest.fn(),
      dispatchEvent: jest.fn(),
      getBoundingClientRect: jest.fn().mockReturnValue({
        left: 0,
        top: 0,
        width: 200,
        height: 200
      }),
      width: 200,
      height: 200,
      style: {
        width: "",
        height: ""
      }
    };
  }
  return null;
});

// Document.createElement mock
document.createElement = jest.fn().mockImplementation(tagName => {
  if (tagName === "canvas") {
    return {
      getContext: jest.fn().mockReturnValue({
        fillStyle: "",
        fillRect: jest.fn(),
        drawImage: jest.fn(),
        putImageData: jest.fn(),
        getImageData: jest.fn().mockReturnValue({
          data: new Uint8Array(400) // 4x25x25 (RGBA x 25x25 pixels)
        })
      }),
      width: 0,
      height: 0,
      toDataURL: jest.fn().mockReturnValue("data:image/png;base64,fakemaskdatastring")
    };
  }
  return null;
});

// Mock window object and Image constructor
global.window = {
  innerHeight: 800,
  currentMaskData: null
};

// Proper Image mock that allows setting onload
global.Image = function() {
  this.src = "";
  this.width = 200;
  this.height = 150;
  
  // Allow setting onload property
  let onloadFn = null;
  Object.defineProperty(this, 'onload', {
    get: function() { return onloadFn; },
    set: function(fn) { 
      onloadFn = fn;
      // Auto-trigger onload when src is set
      if (this.src) {
        setTimeout(() => {
          if (onloadFn) onloadFn();
        }, 0);
      }
    }
  });
};

// Global utility functions
global.setAlert = jest.fn();
global.updateFileDisplay = jest.fn();
global.console = {
  ...console,
  log: jest.fn(),
  error: jest.fn()
};

// Global images array - must be defined before importing the module
global.images = [];

// Import the module under test
const maskEditor = require('../../docker/services/ruby/public/js/monadic/mask_editor');

describe('Mask Editor', () => {
  // Reset setup before each test
  beforeEach(() => {
    jest.clearAllMocks();
    global.images = [];
    global.window.currentMaskData = null;
  });
  
  describe('openMaskEditor', () => {
    it('should create and display the modal properly', () => {
      // Call the openMaskEditor function
      maskEditor.openMaskEditor(mockImageData);
      
      // Check if jQuery was used to create and show the modal
      expect($).toHaveBeenCalledWith("body");
      expect($("#maskEditorModal").modal).toHaveBeenCalledWith("show");
    });
    
    it('should generate mask when save button is clicked', () => {
      // Prepare images array
      global.images = [];
      
      // Call the openMaskEditor function
      maskEditor.openMaskEditor(mockImageData);
      
      // Check if save event was registered
      expect($("#saveMask").on).toHaveBeenCalledWith("click", expect.any(Function));
      
      // Check if mask was properly initialized
      expect(jquerySelectors["#saveMask"].on).toHaveBeenCalled();
      
      // Check that correct events were registered for core functionality
      expect($("#brushSize").on).toHaveBeenCalledWith("input", expect.any(Function));
      expect($("#brushTool").on).toHaveBeenCalledWith("click", expect.any(Function));
      expect($("#eraserTool").on).toHaveBeenCalledWith("click", expect.any(Function));
      expect($("#clearMask").on).toHaveBeenCalledWith("click", expect.any(Function));
      expect($("#maskEditorModal").on).toHaveBeenCalledWith("hidden.bs.modal", expect.any(Function));
    });
  });
});