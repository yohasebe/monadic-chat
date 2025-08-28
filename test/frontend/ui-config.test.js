/**
 * Tests for UI Configuration Module
 */

const { loadModule, cleanupModule } = require('../module-loader');

describe('UI Configuration', () => {
  let UIConfig;
  let mockWindow;
  
  beforeEach(() => {
    // Mock jQuery
    const jQueryMock = jest.fn((selector) => ({
      width: jest.fn(() => {
        if (selector === window) return 1024;
        return 100;
      })
    }));
    jQueryMock.fn = {};
    
    // Create mock window
    mockWindow = {
      $: jQueryMock,
      jQuery: jQueryMock
    };
    
    // Load the module
    const moduleWindow = loadModule('docker/services/ruby/public/js/monadic/ui-config.js', mockWindow);
    UIConfig = moduleWindow.UIConfig;
  });
  
  afterEach(() => {
    cleanupModule('UIConfig');
    jest.clearAllMocks();
  });
  
  describe('Configuration Constants', () => {
    test('should define breakpoints', () => {
      expect(UIConfig.BREAKPOINTS).toBeDefined();
      expect(UIConfig.BREAKPOINTS.MOBILE).toBe(600);
      expect(UIConfig.BREAKPOINTS.TABLET).toBe(768);
      expect(UIConfig.BREAKPOINTS.DESKTOP).toBe(992);
      expect(UIConfig.BREAKPOINTS.WIDE).toBe(1200);
    });
    
    test('should define timing constants', () => {
      expect(UIConfig.TIMING).toBeDefined();
      expect(UIConfig.TIMING.SCROLL_THRESHOLD).toBe(100);
      expect(UIConfig.TIMING.RESIZE_DEBOUNCE).toBe(250);
      expect(UIConfig.TIMING.TOGGLE_ANIMATION).toBe(200);
      expect(UIConfig.TIMING.SCROLL_ANIMATION).toBe(500);
    });
    
    test('should define z-index hierarchy', () => {
      expect(UIConfig.ZINDEX).toBeDefined();
      expect(UIConfig.ZINDEX.BASE).toBeLessThan(UIConfig.ZINDEX.OVERLAY_BACKDROP);
      expect(UIConfig.ZINDEX.OVERLAY_BACKDROP).toBeLessThan(UIConfig.ZINDEX.MODAL);
      expect(UIConfig.ZINDEX.MODAL).toBeLessThan(UIConfig.ZINDEX.TOOLTIP);
    });
  });
  
  describe('Viewport Detection', () => {
    test('should detect mobile view', () => {
      mockWindow.$.mockReturnValue({ width: () => 500 });
      expect(UIConfig.isMobileView()).toBe(true);
      
      mockWindow.$.mockReturnValue({ width: () => 700 });
      expect(UIConfig.isMobileView()).toBe(false);
    });
    
    test('should detect tablet view', () => {
      mockWindow.$.mockReturnValue({ width: () => 700 });
      expect(UIConfig.isTabletView()).toBe(true);
      
      mockWindow.$.mockReturnValue({ width: () => 800 });
      expect(UIConfig.isTabletView()).toBe(false);
    });
    
    test('should detect desktop view', () => {
      mockWindow.$.mockReturnValue({ width: () => 800 });
      expect(UIConfig.isDesktopView()).toBe(true);
      
      mockWindow.$.mockReturnValue({ width: () => 500 });
      expect(UIConfig.isDesktopView()).toBe(false);
    });
  });
  
  describe('Breakpoint Detection', () => {
    test('should return correct breakpoint name', () => {
      mockWindow.$.mockReturnValue({ width: () => 500 });
      expect(UIConfig.getCurrentBreakpoint()).toBe('mobile');
      
      mockWindow.$.mockReturnValue({ width: () => 700 });
      expect(UIConfig.getCurrentBreakpoint()).toBe('tablet');
      
      mockWindow.$.mockReturnValue({ width: () => 1000 });
      expect(UIConfig.getCurrentBreakpoint()).toBe('desktop-lg');
      
      mockWindow.$.mockReturnValue({ width: () => 1300 });
      expect(UIConfig.getCurrentBreakpoint()).toBe('wide');
    });
  });
});