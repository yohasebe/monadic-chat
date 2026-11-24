/**
 * @jest-environment jsdom
 */

// Mock data and setup
const mockImageData = {
  title: "test-image.jpg",
  data: "data:image/jpeg;base64,/9j/4AAQSkZJRgABAQEASABIAAD",
  type: "image/jpeg"
};

// A fake MonadicDialog, as the real one: open() opens at once; close()
// tells mdialog:hidden later (a task).
const opened = [];
global.MonadicDialog = window.MonadicDialog = {
  of: (el) => ({
    open: () => { opened.push(el); return true; },
    close: () => new Promise((r) => setTimeout(r, 0)).then(() => {
      el.dispatchEvent(new CustomEvent('mdialog:hidden'));
      return true;
    })
  })
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

      // A <dialog> named by its title, opened
      const dialog = document.body.lastElementChild;
      expect(dialog.tagName).toBe('DIALOG');
      expect(dialog.id).toBe('maskEditorModal');
      expect(document.getElementById(dialog.getAttribute('aria-labelledby')).textContent).toContain('Create Mask');
      expect(opened[opened.length - 1]).toBe(dialog);
      expect(dialog.querySelectorAll('[data-bs-dismiss]')).toHaveLength(0);
      expect(dialog.querySelectorAll('[data-dialog-close]')).toHaveLength(2);
    });

    it('opened again while the one before closes, the new editor stays and the one before goes', async () => {
      maskEditor.openMaskEditor(mockImageData);
      const before = document.body.lastElementChild;
      before.dataset.which = 'before';
      const closing = window.MonadicDialog.of(before).close('done');
      maskEditor.openMaskEditor(mockImageData);
      const after = document.body.lastElementChild;
      await closing;
      await new Promise((r) => setTimeout(r, 0));
      const left = document.querySelectorAll('dialog#maskEditorModal');
      expect(left).toHaveLength(1);
      expect(left[0]).toBe(after);
      expect(left[0].dataset.which).toBeUndefined();
    });

    it('should register canvas event listeners', () => {
      maskEditor.openMaskEditor(mockImageData);

      // getElementById('maskCanvas') should have been called
      expect(document.getElementById).toHaveBeenCalledWith('maskCanvas');
    });

    it('follows the Web UI modal rules: small footer buttons, a grey Undo and a red Clear', () => {
      maskEditor.openMaskEditor(mockImageData);
      const footer = document.querySelectorAll('#maskEditorModal .modal-footer .btn');
      expect([...footer].map((b) => b.className)).toEqual(['btn btn-sm btn-secondary', 'btn btn-sm btn-primary']);
      expect(document.getElementById('undoMask').className).toBe('btn btn-secondary w-50');
      expect(document.getElementById('clearMask').className).toBe('btn btn-danger w-50');
    });

    it('shows which drawing tool is selected', () => {
      maskEditor.openMaskEditor(mockImageData);
      const brush = document.getElementById('brushTool');
      const eraser = document.getElementById('eraserTool');
      const state = () => [brush, eraser].map((b) => [b.classList.contains('active'), b.getAttribute('aria-pressed')]);
      // Both share one style, so only the selected one is filled.
      expect(brush.className.replace(' active', '')).toBe(eraser.className);
      expect(state()).toEqual([[true, 'true'], [false, 'false']]);
      eraser.click();
      expect(state()).toEqual([[false, 'false'], [true, 'true']]);
      brush.click();
      expect(state()).toEqual([[true, 'true'], [false, 'false']]);
    });
  });
});
