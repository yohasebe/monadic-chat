/**
 * @jest-environment jsdom
 */

/**
 * Tests for ui-utilities.js (vanilla JS version)
 */

// Setup DOM elements needed by the module
document.body.innerHTML = `
  <div id="main" style="height: 500px; overflow: auto;"></div>
  <div id="toggle-menu" class="menu-hidden"></div>
  <div id="back_to_top" style="display: none;"></div>
  <div id="back_to_bottom" style="display: none;"></div>
  <div id="image-file"></div>
  <div id="imageFile"></div>
  <select id="apps"><option value="chat">Chat</option></select>
`;

// Mock bootstrap
global.bootstrap = {
  Tooltip: function(el, opts) {
    this.el = el;
    this.opts = opts;
  }
};
global.bootstrap.Tooltip.getInstance = jest.fn().mockReturnValue(null);

// Import the module under test
const uiUtils = require('../../docker/services/ruby/public/js/monadic/ui-utilities');

// Reset all mocks before each test
beforeEach(() => {
  jest.clearAllMocks();
});

describe('UI Utilities', () => {
  describe('autoResize', () => {
    it('should resize textarea based on content', () => {
      const textarea = {
        style: { height: '50px' },
        scrollHeight: 150
      };

      uiUtils.autoResize(textarea, 100);

      expect(textarea.style.height).toBe('150px');
    });

    it('should respect minimum height', () => {
      const textarea = {
        style: { height: '50px' },
        scrollHeight: 80
      };

      uiUtils.autoResize(textarea, 100);

      expect(textarea.style.height).toBe('100px');
    });
  });

  describe('setupTextarea', () => {
    it('should set up event listeners for a textarea', () => {
      const textarea = {
        style: { height: '' },
        scrollHeight: 120,
        addEventListener: jest.fn()
      };

      uiUtils.setupTextarea(textarea, 100);

      expect(textarea.addEventListener).toHaveBeenCalledWith('compositionstart', expect.any(Function));
      expect(textarea.addEventListener).toHaveBeenCalledWith('compositionend', expect.any(Function));
      expect(textarea.addEventListener).toHaveBeenCalledWith('input', expect.any(Function));
      expect(textarea.addEventListener).toHaveBeenCalledWith('focus', expect.any(Function));
    });

    it('should handle IME input correctly', () => {
      const textarea = {
        style: { height: '' },
        scrollHeight: 120,
        addEventListener: jest.fn()
      };

      uiUtils.setupTextarea(textarea, 100);

      const handlers = {};
      textarea.addEventListener.mock.calls.forEach(call => {
        handlers[call[0]] = call[1];
      });

      // Simulate IME composition sequence
      handlers.compositionstart();
      handlers.input();
      handlers.compositionend();

      // No error means it worked
      expect(true).toBe(true);
    });
  });

  describe('adjustScrollButtons', () => {
    it('should show top button when scrolled down', () => {
      const mainEl = document.getElementById('main');
      // Mock scroll properties
      Object.defineProperty(mainEl, 'scrollHeight', { value: 2000, configurable: true });
      Object.defineProperty(mainEl, 'clientHeight', { value: 500, configurable: true });
      Object.defineProperty(mainEl, 'scrollTop', { value: 300, configurable: true, writable: true });
      Object.defineProperty(mainEl, 'clientWidth', { value: 800, configurable: true });

      // Ensure toggle-menu has menu-hidden class (main is visible)
      document.getElementById('toggle-menu').classList.add('menu-hidden');

      // Mock window.innerWidth
      Object.defineProperty(window, 'innerWidth', { value: 1920, configurable: true });

      uiUtils.adjustScrollButtons();

      // Top button should be visible (not display:none)
      expect(document.getElementById('back_to_top').style.display).not.toBe('none');
      // Bottom button should be visible
      expect(document.getElementById('back_to_bottom').style.display).not.toBe('none');
    });

    it('should hide bottom button when at the bottom', () => {
      const mainEl = document.getElementById('main');
      Object.defineProperty(mainEl, 'scrollHeight', { value: 1000, configurable: true });
      Object.defineProperty(mainEl, 'clientHeight', { value: 500, configurable: true });
      Object.defineProperty(mainEl, 'scrollTop', { value: 500, configurable: true, writable: true });
      Object.defineProperty(mainEl, 'clientWidth', { value: 800, configurable: true });

      document.getElementById('toggle-menu').classList.add('menu-hidden');
      Object.defineProperty(window, 'innerWidth', { value: 1920, configurable: true });

      uiUtils.adjustScrollButtons();

      // Top button should be visible (scrollTop > 100)
      expect(document.getElementById('back_to_top').style.display).not.toBe('none');
      // Bottom button should be hidden (distance from bottom = 0)
      expect(document.getElementById('back_to_bottom').style.display).toBe('none');
    });
  });

  describe('setupTooltips', () => {
    it('should set up tooltips for card header elements with title', () => {
      const container = document.createElement('div');
      container.innerHTML = '<div class="card-header"><span title="Test">Hover</span></div>';

      var tooltipSpy = jest.fn();
      global.bootstrap.Tooltip = tooltipSpy;
      global.bootstrap.Tooltip.getInstance = jest.fn();

      uiUtils.setupTooltips(container);

      expect(tooltipSpy).toHaveBeenCalledWith(
        expect.any(HTMLElement),
        expect.objectContaining({
          trigger: 'hover',
          delay: { show: 0, hide: 0 },
          container: 'body'
        })
      );
    });
  });

  describe('cleanupAllTooltips', () => {
    it('should remove all tooltip elements and dispose instances', () => {
      // Add a tooltip element
      var tooltipEl = document.createElement('div');
      tooltipEl.classList.add('tooltip');
      document.body.appendChild(tooltipEl);

      // Add elements with tooltip attribute
      var bsEl = document.createElement('div');
      bsEl.setAttribute('data-bs-original-title', 'test');
      document.body.appendChild(bsEl);

      var disposeMock = jest.fn();
      global.bootstrap = {
        Tooltip: {
          getInstance: jest.fn().mockReturnValue({ dispose: disposeMock })
        }
      };

      uiUtils.cleanupAllTooltips();

      expect(document.querySelectorAll('.tooltip').length).toBe(0);
      expect(disposeMock).toHaveBeenCalled();

      // Cleanup
      bsEl.remove();
    });
  });

  describe('adjustImageUploadButton', () => {
    global.modelSpec = {
      'gpt-4.1': { vision_capability: true },
      'gpt-3.5-turbo': { vision_capability: false }
    };

    it('should enable image upload button for models with vision capability', () => {
      var imageBtn = document.getElementById('image-file');

      uiUtils.adjustImageUploadButton('gpt-4.1');

      expect(imageBtn.disabled).toBe(false);
      expect(imageBtn.innerHTML).toContain('Image');
      expect(imageBtn.style.display).not.toBe('none');
    });

    it('should disable image upload button for models without vision capability', () => {
      var imageBtn = document.getElementById('image-file');

      uiUtils.adjustImageUploadButton('gpt-3.5-turbo');

      expect(imageBtn.disabled).toBe(true);
      expect(imageBtn.style.display).toBe('none');
    });

    it('should handle undefined modelSpec gracefully', () => {
      const originalModelSpec = global.modelSpec;
      global.modelSpec = undefined;

      expect(() => uiUtils.adjustImageUploadButton('gpt-4.1')).not.toThrow();

      global.modelSpec = originalModelSpec;
    });
  });
});
