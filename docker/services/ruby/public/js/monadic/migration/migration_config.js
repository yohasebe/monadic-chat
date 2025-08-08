// Migration Configuration
// Controls the gradual migration to the new SessionState system

(function() {
  'use strict';
  
  window.MigrationConfig = {
    // Master switch for all migrations
    enabled: false,
    
    // Individual feature flags
    features: {
      messages: false,     // Message array migration
      session: false,      // Session state migration
      app: false,         // App state migration
      ui: false,          // UI state migration
      audio: false        // Audio state migration
    },
    
    // Debug options
    debug: {
      logging: false,           // Enable migration logging
      validation: false,        // Enable consistency validation
      parallelExecution: false, // Run old and new code in parallel
      reportInterval: 0         // Report stats every N operations (0 = disabled)
    },
    
    // Initialize migration based on environment
    init: function() {
      // Auto-enable in development
      if (window.location.hostname === 'localhost') {
        this.enabled = true;
        // Enable all stable migrations
        this.features.messages = true;
        this.features.session = true;
        this.features.app = true;
        this.features.ui = true;
        this.features.audio = true;
        this.debug.logging = false;     // Keep logging off unless debugging
        this.debug.validation = true;   // Enable validation in dev
        
        console.log('[MigrationConfig] Development mode - all stable migrations enabled');
      }
      
      // Check for URL parameters
      const params = new URLSearchParams(window.location.search);
      if (params.has('migration')) {
        this.enabled = params.get('migration') === 'true';
        console.log('[MigrationConfig] Migration set via URL:', this.enabled);
      }
      
      if (params.has('migration_debug')) {
        this.debug.logging = true;
        this.debug.validation = true;
        console.log('[MigrationConfig] Debug mode enabled');
      }
      
      // Check for localStorage settings
      const saved = localStorage.getItem('migrationConfig');
      if (saved) {
        try {
          const config = JSON.parse(saved);
          Object.assign(this.features, config.features || {});
          Object.assign(this.debug, config.debug || {});
          console.log('[MigrationConfig] Loaded from localStorage:', config);
        } catch (e) {
          console.error('[MigrationConfig] Failed to load config:', e);
        }
      }
      
      // Set global flag for other scripts
      window.ENABLE_STATE_MIGRATION = this.enabled && this.features.messages;
      
      return this;
    },
    
    // Enable a specific feature
    enableFeature: function(feature) {
      if (this.features.hasOwnProperty(feature)) {
        this.features[feature] = true;
        this.save();
        console.log(`[MigrationConfig] Enabled feature: ${feature}`);
        
        // Update global flags
        if (feature === 'messages') {
          window.ENABLE_STATE_MIGRATION = true;
        }
      }
    },
    
    // Disable a specific feature
    disableFeature: function(feature) {
      if (this.features.hasOwnProperty(feature)) {
        this.features[feature] = false;
        this.save();
        console.log(`[MigrationConfig] Disabled feature: ${feature}`);
        
        // Update global flags
        if (feature === 'messages') {
          window.ENABLE_STATE_MIGRATION = false;
        }
      }
    },
    
    // Enable all features
    enableAll: function() {
      this.enabled = true;
      Object.keys(this.features).forEach(feature => {
        this.features[feature] = true;
      });
      this.save();
      window.ENABLE_STATE_MIGRATION = true;
      console.log('[MigrationConfig] All features enabled');
    },
    
    // Disable all features
    disableAll: function() {
      this.enabled = false;
      Object.keys(this.features).forEach(feature => {
        this.features[feature] = false;
      });
      this.save();
      window.ENABLE_STATE_MIGRATION = false;
      console.log('[MigrationConfig] All features disabled');
    },
    
    // Save configuration to localStorage
    save: function() {
      try {
        localStorage.setItem('migrationConfig', JSON.stringify({
          features: this.features,
          debug: this.debug
        }));
      } catch (e) {
        console.error('[MigrationConfig] Failed to save config:', e);
      }
    },
    
    // Get migration status
    getStatus: function() {
      const status = {
        enabled: this.enabled,
        features: { ...this.features },
        debug: { ...this.debug },
        stats: {}
      };
      
      // Collect stats from various migration modules
      if (window.MessageMigration) {
        status.stats.messages = window.MessageMigration.getStats();
      }
      
      if (window.StateMigration) {
        status.stats.general = window.StateMigration.getMigrationReport();
      }
      
      if (window.SessionState) {
        status.stats.sessionState = {
          valid: window.SessionState.validateState(),
          snapshot: window.SessionState.getStateSnapshot()
        };
      }
      
      return status;
    },
    
    // Run consistency check
    checkConsistency: function() {
      const results = {};
      
      // Check message consistency
      if (window.MessageMigration && window.MessageMigration.testConsistency) {
        results.messages = window.MessageMigration.testConsistency();
      }
      
      // Check state consistency
      if (window.StateMigration && window.StateMigration.validateConsistency) {
        results.state = window.StateMigration.validateConsistency();
      }
      
      // Check SessionState validity
      if (window.SessionState && window.SessionState.validateState) {
        results.sessionState = window.SessionState.validateState();
      }
      
      const allConsistent = Object.values(results).every(r => 
        r === true || (r && r.consistent === true)
      );
      
      return {
        consistent: allConsistent,
        details: results,
        timestamp: new Date().toISOString()
      };
    },
    
    // Display migration dashboard in console
    showDashboard: function() {
      const status = this.getStatus();
      const consistency = this.checkConsistency();
      
      console.group('🔄 Migration Dashboard');
      
      console.group('Status');
      console.table({
        'Master Switch': status.enabled ? '✅ Enabled' : '❌ Disabled',
        'Messages': status.features.messages ? '✅' : '❌',
        'Session': status.features.session ? '✅' : '❌',
        'App State': status.features.app ? '✅' : '❌',
        'WebSocket': status.features.websocket ? '✅' : '❌',
        'Events': status.features.events ? '✅' : '❌'
      });
      console.groupEnd();
      
      console.group('Consistency');
      console.log(consistency.consistent ? '✅ All systems consistent' : '⚠️ Inconsistencies detected');
      if (!consistency.consistent) {
        console.table(consistency.details);
      }
      console.groupEnd();
      
      if (status.stats.messages) {
        console.group('Message Stats');
        console.table(status.stats.messages);
        console.groupEnd();
      }
      
      if (status.stats.sessionState) {
        console.group('Session State');
        console.log('Valid:', status.stats.sessionState.valid ? '✅' : '❌');
        console.table(status.stats.sessionState.snapshot);
        console.groupEnd();
      }
      
      console.group('Available Commands');
      console.log('MigrationConfig.enableFeature("messages")  - Enable message migration');
      console.log('MigrationConfig.disableFeature("messages") - Disable message migration');
      console.log('MigrationConfig.enableAll()                - Enable all migrations');
      console.log('MigrationConfig.disableAll()               - Disable all migrations');
      console.log('MigrationConfig.checkConsistency()         - Check system consistency');
      console.log('MigrationConfig.showDashboard()            - Show this dashboard');
      console.groupEnd();
      
      console.groupEnd();
    }
  };
  
  // Initialize on load
  window.MigrationConfig.init();
  
  // Show dashboard in development mode
  if (window.location.hostname === 'localhost') {
    // Delay to ensure all scripts are loaded
    setTimeout(() => {
      console.log('💡 Tip: Run MigrationConfig.showDashboard() to see migration status');
    }, 2000);
  }
  
})();