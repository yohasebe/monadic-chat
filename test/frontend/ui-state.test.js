/**
 * Tests for UI State Management Module
 */

const { loadModule, cleanupModule } = require('../module-loader');

describe('UI State Management', () => {
  let UIState;
  let moduleWindow;
  
  beforeEach(() => {
    // Load the module with proper window mock
    moduleWindow = loadModule('docker/services/ruby/public/js/monadic/ui-state.js', {
      addEventListener: jest.fn()
    });
    UIState = moduleWindow.UIState;
  });
  
  afterEach(() => {
    if (UIState && UIState.reset) {
      UIState.reset();
    }
    cleanupModule('UIState');
  });
  
  describe('State Management', () => {
    test('should set and get state values', () => {
      UIState.set('testKey', 'testValue');
      expect(UIState.get('testKey')).toBe('testValue');
    });
    
    test('should handle nested state paths', () => {
      UIState.set('scrollPosition.main', 100);
      expect(UIState.get('scrollPosition.main')).toBe(100);
    });
    
    test('should update multiple states at once', () => {
      UIState.update({
        isStreaming: true,
        isLoading: false,
        windowWidth: 1024
      });
      
      expect(UIState.get('isStreaming')).toBe(true);
      expect(UIState.get('isLoading')).toBe(false);
      expect(UIState.get('windowWidth')).toBe(1024);
    });
    
    test('should return undefined for non-existent keys', () => {
      expect(UIState.get('nonExistent')).toBeUndefined();
    });
  });
  
  describe('State Subscriptions', () => {
    test('should subscribe to state changes', (done) => {
      const callback = jest.fn((newValue, oldValue) => {
        expect(newValue).toBe('newValue');
        expect(oldValue).toBe('oldValue');
        done();
      });
      
      UIState.set('testKey', 'oldValue');
      UIState.subscribe('testKey', callback);
      UIState.set('testKey', 'newValue');
    });
    
    test('should support wildcard subscriptions', (done) => {
      const callback = jest.fn((newValue, oldValue, key) => {
        expect(key).toBe('anyKey');
        expect(newValue).toBe('anyValue');
        done();
      });
      
      UIState.subscribe('*', callback);
      UIState.set('anyKey', 'anyValue');
    });
    
    test('should unsubscribe properly', () => {
      const callback = jest.fn();
      const unsubscribe = UIState.subscribe('testKey', callback);
      
      UIState.set('testKey', 'value1');
      expect(callback).toHaveBeenCalledTimes(1);
      
      unsubscribe();
      UIState.set('testKey', 'value2');
      expect(callback).toHaveBeenCalledTimes(1); // Still 1, not called again
    });
  });
  
  describe('Special State Handlers', () => {
    test('should handle streaming state changes', () => {
      // Mock toggle button
      document.body.innerHTML = '<div id="toggle-menu"></div>';
      const toggleBtn = document.getElementById('toggle-menu');
      
      UIState.set('isStreaming', true);
      expect(UIState.get('toggleMenuLocked')).toBe(true);
      expect(toggleBtn.classList.contains('streaming-active')).toBe(true);
      
      UIState.set('isStreaming', false);
      expect(UIState.get('toggleMenuLocked')).toBe(false);
      expect(toggleBtn.classList.contains('streaming-active')).toBe(false);
    });
    
    test('should track window width changes', () => {
      UIState.set('windowWidth', 1024);
      UIState.set('windowWidth', 768);
      expect(UIState.get('previousWidth')).toBe(1024);
    });
  });
  
  describe('State Reset', () => {
    test('should reset state to defaults', () => {
      UIState.set('isStreaming', true);
      UIState.set('windowWidth', 1024);
      UIState.set('currentApp', 'TestApp');
      
      UIState.reset();
      
      expect(UIState.get('isStreaming')).toBe(false);
      expect(UIState.get('windowWidth')).toBe(0);
      // currentApp might be empty string or null after reset
      const currentApp = UIState.get('currentApp');
      expect(currentApp === null || currentApp === '').toBe(true);
    });
  });
});