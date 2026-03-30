/**
 * Tests for UI Configuration Module
 */

const { loadModule, cleanupModule } = require('../module-loader');

describe('UI Configuration', () => {
  let UIConfig;
  let moduleWindow;

  beforeEach(() => {
    // Load the module - source uses window.innerWidth (not jQuery)
    moduleWindow = loadModule('docker/services/ruby/public/js/monadic/ui-config.js', {
      innerWidth: 1024
    });
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
      moduleWindow.innerWidth = 500;
      expect(UIConfig.isMobileView()).toBe(true);

      moduleWindow.innerWidth = 700;
      expect(UIConfig.isMobileView()).toBe(false);
    });

    test('should detect tablet view', () => {
      moduleWindow.innerWidth = 700;
      expect(UIConfig.isTabletView()).toBe(true);

      moduleWindow.innerWidth = 800;
      expect(UIConfig.isTabletView()).toBe(false);
    });

    test('should detect desktop view', () => {
      moduleWindow.innerWidth = 800;
      expect(UIConfig.isDesktopView()).toBe(true);

      moduleWindow.innerWidth = 500;
      expect(UIConfig.isDesktopView()).toBe(false);
    });
  });

  describe('Breakpoint Detection', () => {
    test('should return correct breakpoint name', () => {
      moduleWindow.innerWidth = 500;
      expect(UIConfig.getCurrentBreakpoint()).toBe('mobile');

      moduleWindow.innerWidth = 700;
      expect(UIConfig.getCurrentBreakpoint()).toBe('tablet');

      moduleWindow.innerWidth = 1000;
      expect(UIConfig.getCurrentBreakpoint()).toBe('desktop-lg');

      moduleWindow.innerWidth = 1300;
      expect(UIConfig.getCurrentBreakpoint()).toBe('wide');
    });
  });
});
