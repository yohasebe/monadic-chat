// App State Migration
// Migrates app selection, parameters, and configuration to SessionState

(function() {
  'use strict';
  
  // Check if migration is enabled
  if (!window.MigrationConfig || !window.MigrationConfig.features.app) {
    console.log('[AppStateMigration] Not enabled');
    return;
  }
  
  console.log('[AppStateMigration] Starting app state migration');
  
  // Backup original values for rollback
  if (window.RollbackManager) {
    window.RollbackManager.backupValue('loadedApp', window.loadedApp);
    window.RollbackManager.backupValue('params', window.params);
    window.RollbackManager.backupValue('originalParams', window.originalParams);
    window.RollbackManager.backupValue('apps', window.apps);
  }
  
  // === Enhanced App State Operations ===
  
  window.AppStateManager = {
    // Get current app
    getCurrentApp: function() {
      try {
        if (window.SessionState && window.SessionState.app) {
          return window.SessionState.app.current || window.loadedApp;
        }
        return window.loadedApp;
      } catch (error) {
        window.RollbackManager && window.RollbackManager.recordError(error, 'getCurrentApp');
        return window.loadedApp; // Fallback
      }
    },
    
    // Set current app with validation
    setCurrentApp: function(appName, params) {
      try {
        console.log(`[AppStateManager] Setting app: ${appName}`);
        
        // Validate app exists
        if (appName && window.apps && !window.apps[appName]) {
          console.warn(`[AppStateManager] Unknown app: ${appName}`);
          return false;
        }
        
        // Update SessionState if available
        if (window.SessionState) {
          window.SessionState.setCurrentApp(appName, params);
        }
        
        // Keep legacy variables in sync
        window.loadedApp = appName;
        if (params) {
          window.params = { ...params };
          window.originalParams = { ...params };
        }
        
        // Update UI
        this.updateAppUI(appName);
        
        return true;
      } catch (error) {
        window.RollbackManager && window.RollbackManager.recordError(error, 'setCurrentApp');
        // Fallback to direct assignment
        window.loadedApp = appName;
        if (params) {
          window.params = params;
        }
        return false;
      }
    },
    
    // Get app parameters
    getAppParams: function() {
      try {
        if (window.SessionState && window.SessionState.app) {
          return window.SessionState.getAppParams() || window.params || {};
        }
        return window.params || {};
      } catch (error) {
        window.RollbackManager && window.RollbackManager.recordError(error, 'getAppParams');
        return window.params || {};
      }
    },
    
    // Update app parameters
    updateAppParams: function(updates) {
      try {
        console.log('[AppStateManager] Updating params:', updates);
        
        // Update SessionState if available
        if (window.SessionState) {
          window.SessionState.updateAppParams(updates);
        }
        
        // Keep legacy variables in sync
        if (window.params) {
          Object.assign(window.params, updates);
        } else {
          window.params = { ...updates };
        }
        
        return true;
      } catch (error) {
        window.RollbackManager && window.RollbackManager.recordError(error, 'updateAppParams');
        // Fallback
        if (window.params) {
          Object.assign(window.params, updates);
        }
        return false;
      }
    },
    
    // Get app configuration
    getAppConfig: function(appName) {
      try {
        appName = appName || this.getCurrentApp();
        if (window.apps && window.apps[appName]) {
          return { ...window.apps[appName] };
        }
        return null;
      } catch (error) {
        window.RollbackManager && window.RollbackManager.recordError(error, 'getAppConfig');
        return null;
      }
    },
    
    // Switch app
    switchApp: function(newAppName) {
      try {
        console.log(`[AppStateManager] Switching from ${this.getCurrentApp()} to ${newAppName}`);
        
        const oldApp = this.getCurrentApp();
        
        // Check if app exists
        if (!window.apps || !window.apps[newAppName]) {
          console.error(`[AppStateManager] App not found: ${newAppName}`);
          return false;
        }
        
        // Get new app config
        const newAppConfig = window.apps[newAppName];
        
        // Prepare new params
        const newParams = {
          ...newAppConfig,
          app: newAppName
        };
        
        // Set the new app
        this.setCurrentApp(newAppName, newParams);
        
        // Notify listeners
        if (window.SessionState) {
          window.SessionState.notifyListeners('app:switched', {
            from: oldApp,
            to: newAppName,
            config: newAppConfig
          });
        }
        
        return true;
      } catch (error) {
        window.RollbackManager && window.RollbackManager.recordError(error, 'switchApp');
        return false;
      }
    },
    
    // Update app UI elements
    updateAppUI: function(appName) {
      try {
        // Update app selector if exists
        if ($("#apps").length) {
          $("#apps").val(appName);
        }
        
        // Update custom app selector if exists
        if ($("#custom-apps-selector").length) {
          $("#custom-apps-selector").val(appName);
        }
        
        // Update app display name
        const config = this.getAppConfig(appName);
        if (config && config.display_name) {
          $(".app-name-display").text(config.display_name);
        }
        
      } catch (error) {
        console.error('[AppStateManager] Failed to update UI:', error);
      }
    },
    
    // Save app state
    saveAppState: function() {
      try {
        if (window.SessionState && window.SessionState.save) {
          window.SessionState.save();
          console.log('[AppStateManager] App state saved');
          return true;
        }
        return false;
      } catch (error) {
        window.RollbackManager && window.RollbackManager.recordError(error, 'saveAppState');
        return false;
      }
    },
    
    // Restore app state
    restoreAppState: function() {
      try {
        if (window.SessionState && window.SessionState.restore) {
          window.SessionState.restore();
          
          // Sync with legacy variables
          if (window.SessionState.app.current) {
            window.loadedApp = window.SessionState.app.current;
          }
          if (window.SessionState.app.params) {
            window.params = { ...window.SessionState.app.params };
          }
          
          console.log('[AppStateManager] App state restored');
          return true;
        }
        return false;
      } catch (error) {
        window.RollbackManager && window.RollbackManager.recordError(error, 'restoreAppState');
        return false;
      }
    },
    
    // Get all available apps
    getAvailableApps: function() {
      try {
        if (window.apps) {
          return Object.keys(window.apps).map(key => ({
            key: key,
            name: window.apps[key].display_name || window.apps[key].app_name || key,
            group: window.apps[key].group || 'Other',
            disabled: window.apps[key].disabled === 'true',
            icon: window.apps[key].icon || ''
          }));
        }
        return [];
      } catch (error) {
        window.RollbackManager && window.RollbackManager.recordError(error, 'getAvailableApps');
        return [];
      }
    },
    
    // Check if app is available
    isAppAvailable: function(appName) {
      try {
        return window.apps && window.apps[appName] && window.apps[appName].disabled !== 'true';
      } catch (error) {
        return false;
      }
    }
  };
  
  // === Sync with legacy variables ===
  
  // Override loadedApp with getter/setter
  let _loadedApp = window.loadedApp;
  Object.defineProperty(window, 'loadedApp', {
    get: function() {
      if (window.SessionState && window.SessionState.app) {
        return window.SessionState.app.current || _loadedApp;
      }
      return _loadedApp;
    },
    set: function(value) {
      _loadedApp = value;
      if (window.SessionState && window.SessionState.app) {
        window.SessionState.app.current = value;
        window.SessionState.notifyListeners('app:changed', { app: value });
      }
    }
  });
  
  // Override params with getter/setter
  let _params = window.params || {};
  Object.defineProperty(window, 'params', {
    get: function() {
      if (window.SessionState && window.SessionState.app) {
        return window.SessionState.app.params || _params;
      }
      return _params;
    },
    set: function(value) {
      _params = value;
      if (window.SessionState && window.SessionState.app) {
        window.SessionState.app.params = { ...value };
        window.SessionState.notifyListeners('app:params-updated', value);
      }
    }
  });
  
  // === Event Listeners ===
  
  if (window.SessionState) {
    // Listen for app changes
    window.SessionState.on('app:changed', function(data) {
      console.log('[AppStateMigration] App changed:', data.app);
      
      // Auto-save on app change
      if (window.MigrationConfig.features.app) {
        setTimeout(() => window.AppStateManager.saveAppState(), 500);
      }
    });
    
    // Listen for params updates
    window.SessionState.on('app:params-updated', function(params) {
      console.log('[AppStateMigration] Params updated:', params);
    });
  }
  
  // === Auto-restore on load ===
  
  document.addEventListener('DOMContentLoaded', function() {
    if (window.MigrationConfig.features.app) {
      // Try to restore app state after a delay
      setTimeout(() => {
        const restored = window.AppStateManager.restoreAppState();
        if (restored) {
          console.log('[AppStateMigration] App state auto-restored');
        }
      }, 1000);
    }
  });
  
  // === Migration Status ===
  
  window.AppStateMigration = {
    status: 'active',
    
    // Get migration statistics
    getStats: function() {
      return {
        enabled: window.MigrationConfig.features.app,
        currentApp: window.AppStateManager.getCurrentApp(),
        availableApps: window.AppStateManager.getAvailableApps().length,
        usingSessionState: !!(window.SessionState && window.SessionState.app),
        paramsCount: Object.keys(window.AppStateManager.getAppParams()).length
      };
    },
    
    // Test app operations
    testOperations: function() {
      console.group('[AppStateMigration] Testing operations');
      
      const originalApp = window.AppStateManager.getCurrentApp();
      const results = {};
      
      try {
        // Test getting current app
        results.getCurrentApp = !!window.AppStateManager.getCurrentApp();
        
        // Test getting params
        results.getParams = !!window.AppStateManager.getAppParams();
        
        // Test getting available apps
        const apps = window.AppStateManager.getAvailableApps();
        results.getAvailableApps = apps.length > 0;
        
        // Test switching app (if there's another available app)
        if (apps.length > 1) {
          const testApp = apps.find(a => a.key !== originalApp && !a.disabled);
          if (testApp) {
            results.switchApp = window.AppStateManager.switchApp(testApp.key);
            // Switch back
            window.AppStateManager.switchApp(originalApp);
          }
        }
        
        // Test save/restore
        results.save = window.AppStateManager.saveAppState();
        results.restore = window.AppStateManager.restoreAppState();
        
      } catch (error) {
        console.error('[AppStateMigration] Test error:', error);
      }
      
      console.table(results);
      console.groupEnd();
      
      return results;
    }
  };
  
  console.log('[AppStateMigration] App state migration complete');
  console.log('[AppStateMigration] Stats:', window.AppStateMigration.getStats());
  
})();