// Rollback Manager for State Migration
// Provides safety mechanisms to instantly revert to legacy behavior if issues occur

(function() {
  'use strict';
  
  window.RollbackManager = {
    // Backup of original functions and values
    backups: {
      functions: new Map(),
      values: new Map(),
      flags: new Map()
    },
    
    // Error tracking
    errors: [],
    errorThreshold: 5, // Number of errors before auto-rollback
    
    // Status
    isRolledBack: false,
    autoRollbackEnabled: true,
    
    // Backup a function before migration
    backupFunction: function(name, originalFunc) {
      if (!this.backups.functions.has(name)) {
        this.backups.functions.set(name, originalFunc);
        console.log(`[Rollback] Backed up function: ${name}`);
      }
    },
    
    // Backup a value before migration
    backupValue: function(name, originalValue) {
      if (!this.backups.values.has(name)) {
        this.backups.values.set(name, JSON.parse(JSON.stringify(originalValue)));
        console.log(`[Rollback] Backed up value: ${name}`);
      }
    },
    
    // Backup migration flags
    backupFlags: function() {
      if (window.MigrationConfig) {
        this.backups.flags.set('features', { ...window.MigrationConfig.features });
        this.backups.flags.set('enabled', window.MigrationConfig.enabled);
      }
    },
    
    // Record an error
    recordError: function(error, context) {
      const errorInfo = {
        message: error.message || error,
        stack: error.stack,
        context: context,
        timestamp: new Date().toISOString()
      };
      
      this.errors.push(errorInfo);
      console.error('[Rollback] Error recorded:', errorInfo);
      
      // Check if we should auto-rollback
      if (this.autoRollbackEnabled && this.errors.length >= this.errorThreshold) {
        console.warn(`[Rollback] Error threshold reached (${this.errors.length}/${this.errorThreshold}). Initiating auto-rollback...`);
        this.rollback('auto-rollback due to errors');
      }
      
      return errorInfo;
    },
    
    // Perform rollback
    rollback: function(reason) {
      if (this.isRolledBack) {
        console.warn('[Rollback] Already rolled back');
        return false;
      }
      
      console.warn(`[Rollback] Initiating rollback. Reason: ${reason}`);
      
      try {
        // Disable all migrations
        if (window.MigrationConfig) {
          window.MigrationConfig.disableAll();
        }
        
        // Restore backed up functions
        this.backups.functions.forEach((func, name) => {
          try {
            // Parse the name to restore (e.g., "window.doResetActions")
            const parts = name.split('.');
            let target = window;
            for (let i = 0; i < parts.length - 1; i++) {
              target = target[parts[i]];
            }
            target[parts[parts.length - 1]] = func;
            console.log(`[Rollback] Restored function: ${name}`);
          } catch (e) {
            console.error(`[Rollback] Failed to restore function ${name}:`, e);
          }
        });
        
        // Restore backed up values
        this.backups.values.forEach((value, name) => {
          try {
            window[name] = value;
            console.log(`[Rollback] Restored value: ${name}`);
          } catch (e) {
            console.error(`[Rollback] Failed to restore value ${name}:`, e);
          }
        });
        
        // Mark as rolled back
        this.isRolledBack = true;
        
        // Show user notification
        this.notifyUser(reason);
        
        // Log rollback event
        this.logRollback(reason);
        
        console.log('[Rollback] Rollback completed');
        return true;
        
      } catch (error) {
        console.error('[Rollback] Rollback failed:', error);
        // Emergency fallback - reload the page
        if (confirm('Migration rollback failed. Reload the page to restore original behavior?')) {
          window.location.reload();
        }
        return false;
      }
    },
    
    // Notify user about rollback
    notifyUser: function(reason) {
      // Try to use the app's notification system
      if (typeof setAlert === 'function') {
        setAlert(
          `<i class="fas fa-exclamation-triangle"></i> State migration disabled due to ${reason}. Using original system.`,
          'warning'
        );
      } else {
        // Fallback to console
        console.warn(`[User Notice] State migration disabled due to ${reason}. Using original system.`);
      }
    },
    
    // Log rollback for debugging
    logRollback: function(reason) {
      const rollbackInfo = {
        reason: reason,
        errors: this.errors,
        timestamp: new Date().toISOString(),
        environment: window.EnvironmentDetector ? window.EnvironmentDetector.getEnvironment() : 'unknown',
        migrationStatus: window.MigrationConfig ? window.MigrationConfig.getStatus() : null
      };
      
      // Store in localStorage for debugging
      try {
        localStorage.setItem('rollbackLog', JSON.stringify(rollbackInfo));
      } catch (e) {
        console.error('[Rollback] Failed to save rollback log:', e);
      }
      
      return rollbackInfo;
    },
    
    // Manual rollback trigger
    manualRollback: function() {
      return this.rollback('manual user request');
    },
    
    // Reset rollback state (for testing)
    reset: function() {
      this.isRolledBack = false;
      this.errors = [];
      this.backups.functions.clear();
      this.backups.values.clear();
      this.backups.flags.clear();
      console.log('[Rollback] Reset completed');
    },
    
    // Get rollback status
    getStatus: function() {
      return {
        isRolledBack: this.isRolledBack,
        errorCount: this.errors.length,
        errorThreshold: this.errorThreshold,
        autoRollbackEnabled: this.autoRollbackEnabled,
        backedUpFunctions: Array.from(this.backups.functions.keys()),
        backedUpValues: Array.from(this.backups.values.keys()),
        recentErrors: this.errors.slice(-5)
      };
    },
    
    // Health check wrapper for safe execution
    safeExecute: function(fn, context, fallback) {
      try {
        return fn.call(context || this);
      } catch (error) {
        this.recordError(error, context || 'unknown context');
        
        if (fallback) {
          console.warn('[Rollback] Using fallback due to error');
          return typeof fallback === 'function' ? fallback() : fallback;
        }
        
        throw error;
      }
    },
    
    // Initialize rollback manager
    init: function() {
      // Backup initial state
      this.backupFlags();
      
      // Set up global error handler for migration errors
      const originalErrorHandler = window.onerror;
      window.onerror = (message, source, lineno, colno, error) => {
        // Check if this is a migration-related error
        if (source && source.includes('migration')) {
          this.recordError(error || { message }, 'global error handler');
        }
        
        // Call original handler if exists
        if (originalErrorHandler) {
          return originalErrorHandler(message, source, lineno, colno, error);
        }
        
        return false;
      };
      
      // Add unhandled promise rejection handler
      window.addEventListener('unhandledrejection', (event) => {
        // Check if this is migration-related
        if (event.reason && event.reason.toString().includes('migration')) {
          this.recordError(event.reason, 'unhandled promise rejection');
        }
      });
      
      console.log('[Rollback] Rollback manager initialized');
      
      // Add console commands for easy access
      window.rollback = () => this.manualRollback();
      window.rollbackStatus = () => this.getStatus();
      
      return this;
    }
  };
  
  // Initialize on load
  window.RollbackManager.init();
  
  // Export for testing
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = window.RollbackManager;
  }
  
})();