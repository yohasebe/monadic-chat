// State Migration Helper
// This module helps with the gradual migration from global variables to SessionState

(function() {
  'use strict';
  
  window.StateMigration = {
    // Feature flag for enabling new state management
    useNewStateManagement: false,
    
    // Logging for migration tracking
    logMigration: false,
    
    // Migration statistics
    stats: {
      legacyCalls: 0,
      newApiCalls: 0,
      migrationWarnings: []
    },
    
    // === Safe Migration Wrappers ===
    
    // Message management wrapper
    addMessage: function(message) {
      if (this.useNewStateManagement && window.SessionState.addMessage) {
        this.stats.newApiCalls++;
        if (this.logMigration) console.log('[Migration] Using new API: addMessage');
        return window.SessionState.addMessage(message);
      } else {
        this.stats.legacyCalls++;
        if (this.logMigration) console.log('[Migration] Using legacy: messages.push');
        window.messages = window.messages || [];
        window.messages.push(message);
        return message;
      }
    },
    
    getMessages: function() {
      if (this.useNewStateManagement && window.SessionState.getMessages) {
        this.stats.newApiCalls++;
        if (this.logMigration) console.log('[Migration] Using new API: getMessages');
        return window.SessionState.getMessages();
      } else {
        this.stats.legacyCalls++;
        if (this.logMigration) console.log('[Migration] Using legacy: messages');
        return window.messages || [];
      }
    },
    
    clearMessages: function() {
      if (this.useNewStateManagement && window.SessionState.clearMessages) {
        this.stats.newApiCalls++;
        if (this.logMigration) console.log('[Migration] Using new API: clearMessages');
        window.SessionState.clearMessages();
      } else {
        this.stats.legacyCalls++;
        if (this.logMigration) console.log('[Migration] Using legacy: messages = []');
        window.messages = [];
      }
    },
    
    // Session management wrapper
    forceNewSession: function(value) {
      if (value === undefined) {
        // Getter
        if (this.useNewStateManagement && window.SessionState) {
          this.stats.newApiCalls++;
          return window.SessionState.shouldForceNewSession();
        } else {
          this.stats.legacyCalls++;
          return window.forceNewSession === true;
        }
      } else {
        // Setter
        if (this.useNewStateManagement && window.SessionState) {
          this.stats.newApiCalls++;
          if (this.logMigration) console.log('[Migration] Using new API: forceNewSession =', value);
          if (value) {
            window.SessionState.startNewSession();
          } else {
            window.SessionState.clearForceNewSession();
          }
        } else {
          this.stats.legacyCalls++;
          if (this.logMigration) console.log('[Migration] Using legacy: forceNewSession =', value);
          window.forceNewSession = value;
        }
      }
    },
    
    // App state wrapper
    getCurrentApp: function() {
      if (this.useNewStateManagement && window.SessionState.getCurrentApp) {
        this.stats.newApiCalls++;
        if (this.logMigration) console.log('[Migration] Using new API: getCurrentApp');
        return window.SessionState.getCurrentApp();
      } else {
        this.stats.legacyCalls++;
        if (this.logMigration) console.log('[Migration] Using legacy: loadedApp');
        return window.loadedApp || null;
      }
    },
    
    setCurrentApp: function(appName, params) {
      if (this.useNewStateManagement && window.SessionState.setCurrentApp) {
        this.stats.newApiCalls++;
        if (this.logMigration) console.log('[Migration] Using new API: setCurrentApp');
        window.SessionState.setCurrentApp(appName, params);
      } else {
        this.stats.legacyCalls++;
        if (this.logMigration) console.log('[Migration] Using legacy: loadedApp =', appName);
        window.loadedApp = appName;
        if (params) {
          window.params = params;
        }
      }
    },
    
    // === Parallel Execution (for testing) ===
    
    // Run both old and new implementations and compare results
    parallelExecute: function(operation, ...args) {
      if (!this.useNewStateManagement) {
        return null; // Only works when new state management is enabled
      }
      
      let legacyResult, newResult;
      let legacyError, newError;
      
      // Execute legacy version
      try {
        this.useNewStateManagement = false;
        legacyResult = operation.apply(this, args);
      } catch (error) {
        legacyError = error;
      }
      
      // Execute new version
      try {
        this.useNewStateManagement = true;
        newResult = operation.apply(this, args);
      } catch (error) {
        newError = error;
      }
      
      // Compare results
      const resultsMatch = JSON.stringify(legacyResult) === JSON.stringify(newResult);
      const errorsMatch = (legacyError && newError) || (!legacyError && !newError);
      
      if (!resultsMatch || !errorsMatch) {
        const warning = {
          operation: operation.name,
          args: args,
          legacyResult: legacyResult,
          newResult: newResult,
          legacyError: legacyError,
          newError: newError,
          timestamp: new Date().toISOString()
        };
        
        this.stats.migrationWarnings.push(warning);
        console.warn('[Migration] Results mismatch:', warning);
      }
      
      // Keep new state management enabled
      this.useNewStateManagement = true;
      
      return {
        legacy: legacyResult,
        new: newResult,
        match: resultsMatch && errorsMatch
      };
    },
    
    // === Validation and Health Checks ===
    
    // Verify that both systems are in sync
    validateConsistency: function() {
      const checks = [];
      
      // Check message consistency
      if (window.messages && window.SessionState.conversation) {
        const legacyMessages = window.messages || [];
        const newMessages = window.SessionState.conversation.messages || [];
        checks.push({
          name: 'messages',
          legacy: legacyMessages.length,
          new: newMessages.length,
          match: legacyMessages.length === newMessages.length
        });
      }
      
      // Check session flags
      if (window.forceNewSession !== undefined && window.SessionState) {
        checks.push({
          name: 'forceNewSession',
          legacy: window.forceNewSession,
          new: window.SessionState.forceNewSession,
          match: window.forceNewSession === window.SessionState.forceNewSession
        });
      }
      
      // Check app state
      if (window.loadedApp !== undefined && window.SessionState.app) {
        checks.push({
          name: 'currentApp',
          legacy: window.loadedApp,
          new: window.SessionState.app.current,
          match: window.loadedApp === window.SessionState.app.current
        });
      }
      
      const allMatch = checks.every(check => check.match);
      
      return {
        consistent: allMatch,
        checks: checks,
        timestamp: new Date().toISOString()
      };
    },
    
    // === Migration Progress Tracking ===
    
    getMigrationReport: function() {
      const consistency = this.validateConsistency();
      
      return {
        enabled: this.useNewStateManagement,
        stats: {
          ...this.stats,
          migrationPercentage: this.stats.newApiCalls / 
            (this.stats.newApiCalls + this.stats.legacyCalls) * 100 || 0
        },
        consistency: consistency,
        warnings: this.stats.migrationWarnings.slice(-10), // Last 10 warnings
        recommendation: this.getRecommendation()
      };
    },
    
    getRecommendation: function() {
      const percentage = this.stats.newApiCalls / 
        (this.stats.newApiCalls + this.stats.legacyCalls) * 100 || 0;
      
      if (percentage === 0) {
        return "Migration not started. Enable with StateMigration.enable()";
      } else if (percentage < 50) {
        return "Migration in progress. Most calls still using legacy API.";
      } else if (percentage < 90) {
        return "Good progress. Consider migrating remaining legacy calls.";
      } else if (percentage < 100) {
        return "Almost complete. Review remaining legacy calls.";
      } else {
        return "Migration complete! Consider removing legacy code.";
      }
    },
    
    // === Control Methods ===
    
    enable: function(options = {}) {
      this.useNewStateManagement = true;
      this.logMigration = options.logging || false;
      
      if (options.validateOnEnable) {
        const validation = this.validateConsistency();
        if (!validation.consistent) {
          console.warn('[Migration] State inconsistency detected:', validation);
        }
      }
      
      console.log('[Migration] New state management enabled');
      return this;
    },
    
    disable: function() {
      this.useNewStateManagement = false;
      this.logMigration = false;
      console.log('[Migration] New state management disabled (using legacy)');
      return this;
    },
    
    reset: function() {
      this.stats = {
        legacyCalls: 0,
        newApiCalls: 0,
        migrationWarnings: []
      };
      console.log('[Migration] Statistics reset');
      return this;
    },
    
    // === Auto-migration for common patterns ===
    
    // Automatically replace common global variable access patterns
    autoMigrate: function(code) {
      const replacements = [
        // messages array
        { from: /window\.messages\.push\(/g, to: 'StateMigration.addMessage(' },
        { from: /messages\.push\(/g, to: 'StateMigration.addMessage(' },
        { from: /window\.messages\s*=\s*\[\]/g, to: 'StateMigration.clearMessages()' },
        { from: /messages\s*=\s*\[\]/g, to: 'StateMigration.clearMessages()' },
        
        // session flags
        { from: /window\.forceNewSession\s*=\s*true/g, to: 'StateMigration.forceNewSession(true)' },
        { from: /window\.forceNewSession\s*=\s*false/g, to: 'StateMigration.forceNewSession(false)' },
        { from: /forceNewSession\s*=\s*true/g, to: 'StateMigration.forceNewSession(true)' },
        { from: /forceNewSession\s*=\s*false/g, to: 'StateMigration.forceNewSession(false)' },
        
        // app state
        { from: /window\.loadedApp\s*=/g, to: 'StateMigration.setCurrentApp(' },
        { from: /loadedApp\s*=/g, to: 'StateMigration.setCurrentApp(' }
      ];
      
      let migratedCode = code;
      replacements.forEach(replacement => {
        migratedCode = migratedCode.replace(replacement.from, replacement.to);
      });
      
      return migratedCode;
    }
  };
  
  // Auto-enable in development mode
  if (window.location.hostname === 'localhost' || window.DEBUG_STATE_MIGRATION) {
    window.StateMigration.enable({ logging: false, validateOnEnable: true });
  }
  
})();