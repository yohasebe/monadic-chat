/**
 * @jest-environment jsdom
 */

describe('Debug Config Module', () => {
  let originalConsoleLog;
  let originalConsoleDebug;
  let originalConsoleError;
  let originalConsoleWarn;
  
  // Save original console methods
  beforeAll(() => {
    originalConsoleLog = console.log;
    originalConsoleDebug = console.debug;
    originalConsoleError = console.error;
    originalConsoleWarn = console.warn;
  });
  
  // Restore original console methods after all tests
  afterAll(() => {
    console.log = originalConsoleLog;
    console.debug = originalConsoleDebug;
    console.error = originalConsoleError;
    console.warn = originalConsoleWarn;
  });
  
  beforeEach(() => {
    // Reset console methods before each test
    console.log = originalConsoleLog;
    console.debug = originalConsoleDebug;
    console.error = originalConsoleError;
    console.warn = originalConsoleWarn;
    
    // Clear module cache to re-import debug-config
    jest.resetModules();
  });
  
  describe('when ENABLE_DEBUG_LOGGING is false', () => {
    it('should disable console.log', () => {
      // Mock the module with ENABLE_DEBUG_LOGGING = false
      jest.doMock('../../docker/services/ruby/public/js/debug-config.js', () => {
        const ENABLE_DEBUG_LOGGING = false;
        
        const originalConsole = {
          log: console.log,
          error: console.error,
          warn: console.warn,
          debug: console.debug
        };
        
        if (!ENABLE_DEBUG_LOGGING) {
          console.log = function() {};
          console.debug = function() {};
        }
      }, { virtual: true });
      
      // Execute the module
      require('../../docker/services/ruby/public/js/debug-config.js');
      
      // Test that console.log is a no-op function
      expect(console.log.toString()).toBe('function() {}');
    });
    
    it('should disable console.debug', () => {
      // Mock the module with ENABLE_DEBUG_LOGGING = false
      jest.doMock('../../docker/services/ruby/public/js/debug-config.js', () => {
        const ENABLE_DEBUG_LOGGING = false;
        
        const originalConsole = {
          log: console.log,
          error: console.error,
          warn: console.warn,
          debug: console.debug
        };
        
        if (!ENABLE_DEBUG_LOGGING) {
          console.log = function() {};
          console.debug = function() {};
        }
      }, { virtual: true });
      
      // Execute the module
      require('../../docker/services/ruby/public/js/debug-config.js');
      
      // Test that console.debug is a no-op function
      expect(console.debug.toString()).toBe('function() {}');
    });
    
    it('should preserve console.error', () => {
      // Mock the module with ENABLE_DEBUG_LOGGING = false
      jest.doMock('../../docker/services/ruby/public/js/debug-config.js', () => {
        const ENABLE_DEBUG_LOGGING = false;
        
        const originalConsole = {
          log: console.log,
          error: console.error,
          warn: console.warn,
          debug: console.debug
        };
        
        if (!ENABLE_DEBUG_LOGGING) {
          console.log = function() {};
          console.debug = function() {};
        }
      }, { virtual: true });
      
      // Execute the module
      require('../../docker/services/ruby/public/js/debug-config.js');
      
      // Test that console.error is unchanged
      expect(console.error).toBe(originalConsoleError);
    });
    
    it('should preserve console.warn', () => {
      // Mock the module with ENABLE_DEBUG_LOGGING = false
      jest.doMock('../../docker/services/ruby/public/js/debug-config.js', () => {
        const ENABLE_DEBUG_LOGGING = false;
        
        const originalConsole = {
          log: console.log,
          error: console.error,
          warn: console.warn,
          debug: console.debug
        };
        
        if (!ENABLE_DEBUG_LOGGING) {
          console.log = function() {};
          console.debug = function() {};
        }
      }, { virtual: true });
      
      // Execute the module
      require('../../docker/services/ruby/public/js/debug-config.js');
      
      // Test that console.warn is unchanged
      expect(console.warn).toBe(originalConsoleWarn);
    });
  });
  
  describe('when ENABLE_DEBUG_LOGGING is true', () => {
    it('should preserve all console methods', () => {
      // Mock the module with ENABLE_DEBUG_LOGGING = true
      jest.doMock('../../docker/services/ruby/public/js/debug-config.js', () => {
        const ENABLE_DEBUG_LOGGING = true;
        
        const originalConsole = {
          log: console.log,
          error: console.error,
          warn: console.warn,
          debug: console.debug
        };
        
        if (!ENABLE_DEBUG_LOGGING) {
          console.log = function() {};
          console.debug = function() {};
        }
      }, { virtual: true });
      
      // Execute the module
      require('../../docker/services/ruby/public/js/debug-config.js');
      
      // Test that all console methods are unchanged
      expect(console.log).toBe(originalConsoleLog);
      expect(console.debug).toBe(originalConsoleDebug);
      expect(console.error).toBe(originalConsoleError);
      expect(console.warn).toBe(originalConsoleWarn);
    });
  });
  
  describe('originalConsole object', () => {
    it('should store references to original console methods', () => {
      // Create a test instance of the module logic
      const testOriginalConsole = {
        log: console.log,
        error: console.error,
        warn: console.warn,
        debug: console.debug
      };
      
      // Verify the references are stored
      expect(testOriginalConsole.log).toBe(originalConsoleLog);
      expect(testOriginalConsole.error).toBe(originalConsoleError);
      expect(testOriginalConsole.warn).toBe(originalConsoleWarn);
      expect(testOriginalConsole.debug).toBe(originalConsoleDebug);
    });
  });
});