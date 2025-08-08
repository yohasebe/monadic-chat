/**
 * @jest-environment jsdom
 */

const fs = require('fs');
const path = require('path');

// Helper to load migration files
function loadMigrationFile(filename) {
  const filePath = path.join(__dirname, '../../../docker/services/ruby/public/js/monadic/migration', filename);
  const code = fs.readFileSync(filePath, 'utf8');
  
  // Create a function that executes the code
  const func = new Function('window', 'document', 'console', code);
  
  // Execute in the context of the global window
  func(global.window, global.document, console);
}

describe('Rollback Manager', () => {
  beforeEach(() => {
    // Reset window state
    global.window = {
      location: { hostname: 'localhost' },
      localStorage: {
        getItem: jest.fn(),
        setItem: jest.fn(),
        removeItem: jest.fn()
      },
      MigrationConfig: {
        disableAll: jest.fn(),
        features: {}
      },
      onerror: null,
      addEventListener: jest.fn()
    };
    
    // Mock jQuery
    global.$ = jest.fn(() => ({
      hide: jest.fn(),
      show: jest.fn(),
      remove: jest.fn()
    }));
    
    // Load RollbackManager
    loadMigrationFile('rollback_manager.js');
  });
  
  describe('Backup and Restore', () => {
    test('should backup functions', () => {
      const testFunc = () => 'original';
      window.RollbackManager.backupFunction('testFunc', testFunc);
      
      const status = window.RollbackManager.getStatus();
      expect(status.backedUpFunctions).toContain('testFunc');
    });
    
    test('should backup values', () => {
      const testValue = { data: 'original' };
      window.RollbackManager.backupValue('testValue', testValue);
      
      const status = window.RollbackManager.getStatus();
      expect(status.backedUpValues).toContain('testValue');
    });
    
    test('should backup flags', () => {
      window.MigrationConfig.features = { messages: true, session: false };
      window.MigrationConfig.enabled = true;
      
      window.RollbackManager.backupFlags();
      
      expect(window.RollbackManager.backups.flags.has('features')).toBe(true);
      expect(window.RollbackManager.backups.flags.has('enabled')).toBe(true);
    });
  });
  
  describe('Error Tracking', () => {
    test('should record errors', () => {
      const error = new Error('Test error');
      window.RollbackManager.recordError(error, 'test-context');
      
      const status = window.RollbackManager.getStatus();
      expect(status.errorCount).toBe(1);
      expect(status.recentErrors[0].message).toBe('Test error');
      expect(status.recentErrors[0].context).toBe('test-context');
    });
    
    test('should auto-rollback after error threshold', () => {
      window.RollbackManager.autoRollbackEnabled = true;
      window.RollbackManager.errorThreshold = 3;
      
      // Record errors up to threshold
      for (let i = 0; i < 3; i++) {
        window.RollbackManager.recordError(new Error(`Error ${i}`), 'test');
      }
      
      expect(window.RollbackManager.isRolledBack).toBe(true);
      expect(window.MigrationConfig.disableAll).toHaveBeenCalled();
    });
    
    test('should not auto-rollback when disabled', () => {
      window.RollbackManager.autoRollbackEnabled = false;
      
      // Record many errors
      for (let i = 0; i < 10; i++) {
        window.RollbackManager.recordError(new Error(`Error ${i}`), 'test');
      }
      
      expect(window.RollbackManager.isRolledBack).toBe(false);
    });
  });
  
  describe('Rollback Operations', () => {
    test('should perform rollback successfully', () => {
      // Setup backups
      window.testValue = 'modified';
      window.RollbackManager.backupValue('testValue', 'original');
      
      // Perform rollback
      const result = window.RollbackManager.rollback('test rollback');
      
      expect(result).toBe(true);
      expect(window.RollbackManager.isRolledBack).toBe(true);
      expect(window.MigrationConfig.disableAll).toHaveBeenCalled();
    });
    
    test('should prevent double rollback', () => {
      window.RollbackManager.isRolledBack = true;
      
      const result = window.RollbackManager.rollback('second rollback');
      expect(result).toBe(false);
    });
    
    test('should handle manual rollback', () => {
      const result = window.RollbackManager.manualRollback();
      
      expect(result).toBe(true);
      expect(window.RollbackManager.isRolledBack).toBe(true);
    });
  });
  
  describe('Safe Execute', () => {
    test('should execute function safely', () => {
      const safeFunc = () => 'success';
      const result = window.RollbackManager.safeExecute(safeFunc, 'test-context');
      
      expect(result).toBe('success');
      expect(window.RollbackManager.errors).toHaveLength(0);
    });
    
    test('should handle errors and use fallback', () => {
      const errorFunc = () => { throw new Error('Test error'); };
      const fallback = 'fallback value';
      
      const result = window.RollbackManager.safeExecute(errorFunc, 'test-context', fallback);
      
      expect(result).toBe('fallback value');
      expect(window.RollbackManager.errors).toHaveLength(1);
    });
    
    test('should execute fallback function', () => {
      const errorFunc = () => { throw new Error('Test error'); };
      const fallbackFunc = () => 'fallback result';
      
      const result = window.RollbackManager.safeExecute(errorFunc, 'test-context', fallbackFunc);
      
      expect(result).toBe('fallback result');
    });
  });
  
  describe('Status and Reset', () => {
    test('should return correct status', () => {
      window.RollbackManager.backupFunction('func1', () => {});
      window.RollbackManager.backupValue('value1', 'test');
      window.RollbackManager.recordError(new Error('Test'), 'context');
      
      const status = window.RollbackManager.getStatus();
      
      expect(status.isRolledBack).toBe(false);
      expect(status.errorCount).toBe(1);
      expect(status.errorThreshold).toBe(5);
      expect(status.autoRollbackEnabled).toBe(true);
      expect(status.backedUpFunctions).toContain('func1');
      expect(status.backedUpValues).toContain('value1');
      expect(status.recentErrors).toHaveLength(1);
    });
    
    test('should reset state correctly', () => {
      // Add some state
      window.RollbackManager.backupFunction('func1', () => {});
      window.RollbackManager.recordError(new Error('Test'), 'context');
      window.RollbackManager.isRolledBack = true;
      
      // Reset
      window.RollbackManager.reset();
      
      expect(window.RollbackManager.isRolledBack).toBe(false);
      expect(window.RollbackManager.errors).toHaveLength(0);
      expect(window.RollbackManager.backups.functions.size).toBe(0);
      expect(window.RollbackManager.backups.values.size).toBe(0);
    });
  });
  
  describe('Global Error Handling', () => {
    test('should handle migration-related global errors', () => {
      const errorHandler = window.onerror;
      
      // Simulate migration error
      errorHandler('Error message', 'migration/test.js', 10, 5, new Error('Migration error'));
      
      expect(window.RollbackManager.errors).toHaveLength(1);
    });
    
    test('should handle unhandled promise rejections', () => {
      const handlers = {};
      window.addEventListener = jest.fn((event, handler) => {
        handlers[event] = handler;
      });
      
      // Re-initialize to set up handlers
      window.RollbackManager.init();
      
      // Simulate unhandled rejection with migration error
      if (handlers['unhandledrejection']) {
        handlers['unhandledrejection']({
          reason: new Error('migration failed')
        });
        
        expect(window.RollbackManager.errors).toHaveLength(1);
      }
    });
  });
  
  describe('Console Commands', () => {
    test('should expose console commands', () => {
      expect(typeof window.rollback).toBe('function');
      expect(typeof window.rollbackStatus).toBe('function');
      
      // Test commands work
      const status = window.rollbackStatus();
      expect(status).toBeDefined();
      expect(status.isRolledBack).toBeDefined();
    });
  });
});