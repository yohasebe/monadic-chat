/**
 * Tests for Error Handler Module
 */

const { loadModule, cleanupModule } = require('../module-loader');

describe('Error Handler', () => {
  let ErrorHandler;
  let moduleWindow;
  let consoleErrorSpy;
  let consoleWarnSpy;
  let consoleInfoSpy;
  let consoleDebugSpy;
  
  beforeEach(() => {
    // Spy on console methods
    consoleErrorSpy = jest.spyOn(console, 'error').mockImplementation();
    consoleWarnSpy = jest.spyOn(console, 'warn').mockImplementation();
    consoleInfoSpy = jest.spyOn(console, 'info').mockImplementation();
    consoleDebugSpy = jest.spyOn(console, 'debug').mockImplementation();
    
    // Mock UIState
    const mockUIState = {
      get: jest.fn(() => []),
      set: jest.fn()
    };
    
    // Load the module with mocked dependencies
    moduleWindow = loadModule('docker/services/ruby/public/js/monadic/error-handler.js', {
      UIState: mockUIState,
      addEventListener: jest.fn(),
      DEBUG_MODE: false,
      document: {
        readyState: 'complete',
        addEventListener: jest.fn()
      }
    });
    
    ErrorHandler = moduleWindow.ErrorHandler;
  });
  
  afterEach(() => {
    cleanupModule('ErrorHandler');
    consoleErrorSpy.mockRestore();
    consoleWarnSpy.mockRestore();
    consoleInfoSpy.mockRestore();
    consoleDebugSpy.mockRestore();
  });
  
  describe('Error Formatting', () => {
    test('should format error with all fields', () => {
      const formatted = ErrorHandler.format({
        category: ErrorHandler.CATEGORIES.API,
        message: 'API request failed',
        code: '500',
        details: 'Internal server error',
        suggestion: 'Try again later'
      });
      
      expect(formatted).toContain('[API]');
      expect(formatted).toContain('API request failed');
      expect(formatted).toContain('Code: 500');
      expect(formatted).toContain('Details: Internal server error');
      expect(formatted).toContain('Suggestion: Try again later');
    });
    
    test('should format error with minimal fields', () => {
      const formatted = ErrorHandler.format({
        message: 'Simple error'
      });
      
      expect(formatted).toContain('[System]');
      expect(formatted).toContain('Simple error');
    });
  });
  
  describe('Error Logging', () => {
    test('should log errors to console', () => {
      ErrorHandler.log({
        category: ErrorHandler.CATEGORIES.NETWORK,
        message: 'Network error',
        level: ErrorHandler.LEVELS.ERROR
      });
      
      expect(consoleErrorSpy).toHaveBeenCalled();
      const logMessage = consoleErrorSpy.mock.calls[0][0];
      expect(logMessage).toContain('[Network]');
      expect(logMessage).toContain('Network error');
    });
    
    test('should log warnings to console.warn', () => {
      ErrorHandler.log({
        message: 'Warning message',
        level: ErrorHandler.LEVELS.WARNING
      });
      
      expect(consoleWarnSpy).toHaveBeenCalled();
    });
    
    test('should log info to console.info', () => {
      ErrorHandler.log({
        message: 'Info message',
        level: ErrorHandler.LEVELS.INFO
      });
      
      expect(consoleInfoSpy).toHaveBeenCalled();
    });
    
    test('should store errors in history', () => {
      ErrorHandler.log({
        message: 'Test error',
        level: ErrorHandler.LEVELS.ERROR
      });
      
      expect(moduleWindow.UIState.set).toHaveBeenCalled();
      const call = moduleWindow.UIState.set.mock.calls[0];
      expect(call[0]).toBe('errorHistory');
      expect(call[1]).toHaveLength(1);
      expect(call[1][0].message).toContain('Test error');
    });
  });
  
  describe('Async Error Handling', () => {
    test('should handle async function errors', async () => {
      const failingFunction = jest.fn(async () => {
        throw new Error('Async error');
      });
      
      const wrapped = ErrorHandler.handleAsync(failingFunction, {
        category: ErrorHandler.CATEGORIES.API,
        message: 'API call failed'
      });
      
      const result = await wrapped();
      
      expect(result).toBeNull();
      expect(consoleErrorSpy).toHaveBeenCalled();
    });
    
    test('should pass through successful async results', async () => {
      const successFunction = jest.fn(async () => {
        return { data: 'success' };
      });
      
      const wrapped = ErrorHandler.handleAsync(successFunction);
      const result = await wrapped();
      
      expect(result).toEqual({ data: 'success' });
      expect(consoleErrorSpy).not.toHaveBeenCalled();
    });
  });
  
  describe('Safe Function Wrapper', () => {
    test('should wrap functions safely', () => {
      const riskyFunction = jest.fn(() => {
        throw new Error('Sync error');
      });
      
      const wrapped = ErrorHandler.safeWrap(riskyFunction, 'testFunction');
      const result = wrapped();
      
      expect(result).toBeNull();
      expect(consoleErrorSpy).toHaveBeenCalled();
      const logMessage = consoleErrorSpy.mock.calls[0][0];
      expect(logMessage).toContain('Error in testFunction');
    });
    
    test('should pass through successful results', () => {
      const safeFunction = jest.fn(() => 'success');
      const wrapped = ErrorHandler.safeWrap(safeFunction);
      
      expect(wrapped()).toBe('success');
      expect(consoleErrorSpy).not.toHaveBeenCalled();
    });
  });
});