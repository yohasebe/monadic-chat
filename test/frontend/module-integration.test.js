/**
 * Integration Tests for Module Interactions
 */

const { loadModule, cleanupModule } = require('../module-loader');

describe('Module Integration Tests', () => {
  let UIConfig, UIState, ErrorHandler;
  let moduleWindow;
  
  beforeEach(() => {
    // Create a jQuery mock that doesn't cause circular references
    const jQueryMock = jest.fn((selector) => {
      if (selector === window) {
        return { width: () => 1024 };
      }
      // Return mock jQuery object
      const mockObj = {
        width: () => 100,
        height: () => 100,
        offset: () => ({ top: 0, left: 0 }),
        length: 1,
        get: () => document.createElement('div'),
        each: jest.fn(),
        find: jest.fn(() => mockObj)
      };
      return mockObj;
    });
    
    jQueryMock.fn = {};
    
    // Create a shared mock window for all modules
    const mockWindow = {
      addEventListener: jest.fn(),
      DEBUG_MODE: false,
      document: {
        readyState: 'complete',
        addEventListener: jest.fn()
      },
      $: jQueryMock,
      jQuery: jQueryMock
    };
    
    // Set global $ for modules that use it directly
    global.$ = jQueryMock;
    global.jQuery = jQueryMock;
    
    // Load core modules in order (dependencies first)
    const configWindow = loadModule('docker/services/ruby/public/js/monadic/ui-config.js', mockWindow);
    UIConfig = configWindow.UIConfig;
    mockWindow.UIConfig = UIConfig;
    
    const stateWindow = loadModule('docker/services/ruby/public/js/monadic/ui-state.js', mockWindow);
    UIState = stateWindow.UIState;
    mockWindow.UIState = UIState;
    
    const errorWindow = loadModule('docker/services/ruby/public/js/monadic/error-handler.js', mockWindow);
    ErrorHandler = errorWindow.ErrorHandler;
    mockWindow.ErrorHandler = ErrorHandler;
    
    moduleWindow = mockWindow;
  });
  
  afterEach(() => {
    // Clean up all modules
    ['UIConfig', 'UIState', 'ErrorHandler'].forEach(cleanupModule);
    // Clean up global mocks
    delete global.$;
    delete global.jQuery;
    jest.clearAllMocks();
  });
  
  describe('UIConfig and UIState Integration', () => {
    test('UIState can use UIConfig breakpoints', () => {
      // Set window width to tablet size
      moduleWindow.$.mockReturnValue({ width: () => 700 });
      
      // UIConfig should detect tablet view
      expect(UIConfig.isTabletView()).toBe(true);
      expect(UIConfig.getCurrentBreakpoint()).toBe('tablet');
      
      // Store this in UIState
      UIState.set('currentBreakpoint', UIConfig.getCurrentBreakpoint());
      expect(UIState.get('currentBreakpoint')).toBe('tablet');
    });
    
    test('UIState updates trigger callbacks', () => {
      const callback = jest.fn();
      
      // Subscribe to state changes
      const unsubscribe = UIState.subscribe('testValue', callback);
      expect(typeof unsubscribe).toBe('function');
      
      // Set initial value (this creates the key but may not trigger callback)
      UIState.set('testValue', 'initial');
      
      // Clear any calls from initialization
      callback.mockClear();
      
      // Update value and check callback was called
      UIState.set('testValue', 'updated');
      
      // Verify callback was called at least once
      expect(callback).toHaveBeenCalled();
      
      // Clean up
      unsubscribe();
    });
  });
  
  describe('ErrorHandler and UIState Integration', () => {
    test('ErrorHandler stores errors in UIState', () => {
      // Spy on UIState.set
      const setSpy = jest.spyOn(UIState, 'set');
      
      // Log an error
      ErrorHandler.log({
        category: ErrorHandler.CATEGORIES.API,
        message: 'API test error',
        level: ErrorHandler.LEVELS.ERROR
      });
      
      // Should update error history in UIState
      expect(setSpy).toHaveBeenCalled();
      const call = setSpy.mock.calls[0];
      expect(call[0]).toBe('errorHistory');
      expect(call[1]).toHaveLength(1);
      expect(call[1][0].message).toContain('API test error');
    });
    
    test('ErrorHandler logs different levels correctly', () => {
      const consoleErrorSpy = jest.spyOn(console, 'error').mockImplementation();
      const consoleWarnSpy = jest.spyOn(console, 'warn').mockImplementation();
      
      // Log an error
      ErrorHandler.log({
        message: 'Error test message',
        level: ErrorHandler.LEVELS.ERROR
      });
      
      // Log a warning
      ErrorHandler.log({
        message: 'Warning test message',
        level: ErrorHandler.LEVELS.WARNING
      });
      
      // Verify correct console methods were called
      expect(consoleErrorSpy).toHaveBeenCalled();
      expect(consoleWarnSpy).toHaveBeenCalled();
      
      consoleErrorSpy.mockRestore();
      consoleWarnSpy.mockRestore();
    });
  });
  
  
  describe('All Modules Working Together', () => {
    test('Complete workflow using core modules', () => {
      // 1. Check viewport with UIConfig
      const breakpoint = UIConfig.getCurrentBreakpoint();
      
      // 2. Store in UIState
      UIState.set('viewport', breakpoint);
      
      // 3. Handle a mock error
      ErrorHandler.log({
        category: ErrorHandler.CATEGORIES.DOM,
        message: 'Test element not found',
        level: ErrorHandler.LEVELS.WARNING
      });
      
      // 4. Verify the workflow
      expect(UIState.get('viewport')).toBeDefined();
      expect(UIState.get('viewport')).toBe(breakpoint);
      
      // 5. Check error was stored
      const errorHistory = UIState.get('errorHistory');
      expect(errorHistory).toBeDefined();
      expect(errorHistory.length).toBeGreaterThan(0);
      expect(errorHistory[0].message).toContain('Test element not found');
    });
    
    test('Error recovery workflow', () => {
      const failingFunction = () => {
        throw new Error('Test error');
      };
      
      // Wrap with error handler
      const wrapped = ErrorHandler.safeWrap(failingFunction, 'testFunction');
      
      // Execute and verify error handling
      const result = wrapped();
      expect(result).toBeNull();
      
      // Check error was logged to UIState
      const errorHistory = UIState.get('errorHistory');
      expect(errorHistory).toHaveLength(1);
      expect(errorHistory[0].message).toContain('testFunction');
    });
  });
  
  describe('State Change Propagation', () => {
    test('Multiple state updates work correctly', () => {
      // Set multiple values
      UIState.set('value1', 'test1');
      UIState.set('value2', 'test2');
      UIState.set('value3', 'test3');
      
      // Verify all values are stored
      expect(UIState.get('value1')).toBe('test1');
      expect(UIState.get('value2')).toBe('test2');
      expect(UIState.get('value3')).toBe('test3');
      
      // Update multiple at once
      UIState.update({
        value1: 'updated1',
        value2: 'updated2'
      });
      
      // Verify updates
      expect(UIState.get('value1')).toBe('updated1');
      expect(UIState.get('value2')).toBe('updated2');
      expect(UIState.get('value3')).toBe('test3'); // Unchanged
    });
    
    test('Nested state properties work correctly', () => {
      // Set nested values
      UIState.set('nested.level1.level2', 'deep value');
      
      // Verify nested access
      expect(UIState.get('nested.level1.level2')).toBe('deep value');
      
      // Update nested value
      UIState.set('nested.level1.level2', 'updated deep value');
      expect(UIState.get('nested.level1.level2')).toBe('updated deep value');
      
      // Set another nested property
      UIState.set('nested.level1.another', 'sibling value');
      expect(UIState.get('nested.level1.another')).toBe('sibling value');
      
      // Original nested value should be unchanged
      expect(UIState.get('nested.level1.level2')).toBe('updated deep value');
    });
  });
  
  describe('Module Initialization Order', () => {
    test('Modules can reference each other after initialization', () => {
      // Core modules should be available
      expect(UIConfig).toBeDefined();
      expect(UIState).toBeDefined();
      expect(ErrorHandler).toBeDefined();
      
      // They should have their main methods
      expect(typeof UIConfig.isMobileView).toBe('function');
      expect(typeof UIState.get).toBe('function');
      expect(typeof ErrorHandler.log).toBe('function');
    });
  });
});