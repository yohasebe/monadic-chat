// Session Management Migration
// Migrates session reset and management to use SessionState

(function() {
  'use strict';
  
  // Check if migration is enabled
  if (!window.MigrationConfig || !window.MigrationConfig.features.session) {
    console.log('[SessionMigration] Not enabled');
    return;
  }
  
  console.log('[SessionMigration] Starting session management migration');
  
  // === Enhanced Session Operations ===
  
  window.SessionManager = {
    // Reset the session with proper cleanup
    resetSession: function(options = {}) {
      const silent = options.silent || false;
      
      if (!silent) {
        console.log('[SessionManager] Resetting session');
      }
      
      // Use SessionState if available
      if (window.SessionState) {
        window.SessionState.resetSession();
      } else {
        // Legacy fallback
        window.forceNewSession = true;
        window.justReset = true;
        if (window.messages) {
          window.messages.length = 0;
        }
      }
      
      // Clear UI
      $("#discourse").empty();
      
      // Reset stats
      if (typeof setStats === 'function' && typeof formatInfo === 'function') {
        setStats(formatInfo([]), "info");
      }
      
      // Update UI labels
      $("#start-label").text("Start Session");
      $("#ai_user").prop("disabled", true);
      
      // Show config panel
      $("#config").show();
      $("#main-panel").hide();
      $("#back-to-settings").hide();
      
      // Notify listeners
      if (!silent && window.SessionState) {
        window.SessionState.notifyListeners('session:ui-reset');
      }
      
      return true;
    },
    
    // Start a new session
    startNewSession: function(options = {}) {
      console.log('[SessionManager] Starting new session');
      
      // Use SessionState if available
      if (window.SessionState) {
        window.SessionState.startNewSession();
      } else {
        // Legacy fallback
        window.forceNewSession = true;
        if (window.messages) {
          window.messages.length = 0;
        }
      }
      
      // Hide config, show main panel
      $("#config").hide();
      $("#main-panel").show();
      $("#back-to-settings").show();
      
      // Update UI labels
      if (window.MessageManager && window.MessageManager.getMessageCount() > 0) {
        $("#start-label").text("Continue Session");
      }
      
      return true;
    },
    
    // Check if we should force a new session
    shouldForceNewSession: function() {
      if (window.SessionState) {
        return window.SessionState.shouldForceNewSession();
      }
      return window.forceNewSession === true;
    },
    
    // Clear force new session flag
    clearForceNewSession: function() {
      if (window.SessionState) {
        window.SessionState.clearForceNewSession();
      } else {
        window.forceNewSession = false;
      }
    },
    
    // Get session info
    getSessionInfo: function() {
      const info = {
        id: null,
        started: false,
        messageCount: 0,
        forceNew: false,
        justReset: false
      };
      
      if (window.SessionState) {
        info.id = window.SessionState.session.id;
        info.started = window.SessionState.session.started;
        info.messageCount = window.SessionState.conversation.messages.length;
        info.forceNew = window.SessionState.session.forceNew;
        info.justReset = window.SessionState.session.justReset;
      } else {
        // Legacy fallback
        info.messageCount = window.messages ? window.messages.length : 0;
        info.forceNew = window.forceNewSession || false;
        info.justReset = window.justReset || false;
        info.started = info.messageCount > 0;
      }
      
      return info;
    },
    
    // Save session state
    saveSession: function() {
      if (window.SessionState && window.SessionState.save) {
        try {
          window.SessionState.save();
          console.log('[SessionManager] Session saved');
          return true;
        } catch (e) {
          console.error('[SessionManager] Failed to save session:', e);
          return false;
        }
      }
      return false;
    },
    
    // Restore session state
    restoreSession: function() {
      if (window.SessionState && window.SessionState.restore) {
        try {
          window.SessionState.restore();
          console.log('[SessionManager] Session restored');
          
          // Update UI based on restored state
          const info = this.getSessionInfo();
          if (info.messageCount > 0) {
            $("#start-label").text("Continue Session");
            $("#ai_user").prop("disabled", false);
          }
          
          return true;
        } catch (e) {
          console.error('[SessionManager] Failed to restore session:', e);
          return false;
        }
      }
      return false;
    }
  };
  
  // === Patch existing reset functions ===
  
  // Store original doResetActions if it exists
  if (typeof window.doResetActions === 'function' && !window.originalDoResetActions_session) {
    window.originalDoResetActions_session = window.doResetActions;
    
    // Override with migrated version
    window.doResetActions = function() {
      console.log('[SessionMigration] Intercepting doResetActions');
      
      // Call SessionManager
      window.SessionManager.resetSession();
      
      // Call original if needed for other functionality
      if (window.originalDoResetActions_session) {
        window.originalDoResetActions_session.call(this);
      }
    };
  }
  
  // === Event Listeners ===
  
  if (window.SessionState) {
    // Listen for session events
    window.SessionState.on('session:new', function(data) {
      console.log('[SessionMigration] New session started:', data);
      
      // Auto-save on new session
      if (window.MigrationConfig.features.session) {
        setTimeout(() => window.SessionManager.saveSession(), 1000);
      }
    });
    
    window.SessionState.on('session:reset', function() {
      console.log('[SessionMigration] Session reset');
      
      // Clear any pending operations
      if (window.cancelQuery) {
        window.cancelQuery();
      }
    });
  }
  
  // === Auto-restore on load ===
  
  document.addEventListener('DOMContentLoaded', function() {
    if (window.MigrationConfig.features.session) {
      // Try to restore session after a delay
      setTimeout(() => {
        const restored = window.SessionManager.restoreSession();
        if (restored) {
          console.log('[SessionMigration] Session auto-restored');
        }
      }, 500);
    }
  });
  
  // === Auto-save on important events ===
  
  if (window.MigrationConfig.features.session) {
    // Save on page unload
    window.addEventListener('beforeunload', function() {
      window.SessionManager.saveSession();
    });
    
    // Save periodically
    setInterval(() => {
      const info = window.SessionManager.getSessionInfo();
      if (info.started && info.messageCount > 0) {
        window.SessionManager.saveSession();
      }
    }, 30000); // Every 30 seconds
  }
  
  // === Migration Status ===
  
  window.SessionMigration = {
    status: 'active',
    
    // Get migration statistics
    getStats: function() {
      return {
        enabled: window.MigrationConfig.features.session,
        sessionInfo: window.SessionManager.getSessionInfo(),
        usingSessionState: !!window.SessionState,
        autoSaveEnabled: window.MigrationConfig.features.session,
        autoRestoreEnabled: window.MigrationConfig.features.session
      };
    },
    
    // Test session operations
    testOperations: function() {
      console.group('[SessionMigration] Testing operations');
      
      // Test reset
      console.log('Testing reset...');
      window.SessionManager.resetSession({ silent: true });
      const afterReset = window.SessionManager.getSessionInfo();
      console.log('After reset:', afterReset);
      
      // Test new session
      console.log('Testing new session...');
      window.SessionManager.startNewSession();
      const afterNew = window.SessionManager.getSessionInfo();
      console.log('After new:', afterNew);
      
      // Test save/restore
      console.log('Testing save/restore...');
      const saved = window.SessionManager.saveSession();
      console.log('Save result:', saved);
      
      const restored = window.SessionManager.restoreSession();
      console.log('Restore result:', restored);
      
      console.groupEnd();
      
      return {
        reset: afterReset.messageCount === 0,
        newSession: afterNew.forceNew === true,
        save: saved,
        restore: restored
      };
    }
  };
  
  console.log('[SessionMigration] Session management migration complete');
  console.log('[SessionMigration] Stats:', window.SessionMigration.getStats());
  
})();