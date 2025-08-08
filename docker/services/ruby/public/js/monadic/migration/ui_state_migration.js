// UI State Migration
// Centralizes UI state management including visibility, alerts, and user preferences

(function() {
  'use strict';
  
  // Check if migration is enabled
  if (!window.MigrationConfig || !window.MigrationConfig.features.ui) {
    console.log('[UIStateMigration] Not enabled');
    return;
  }
  
  console.log('[UIStateMigration] Starting UI state migration');
  
  // Backup original functions for rollback
  if (window.RollbackManager) {
    if (typeof window.setAlert === 'function') {
      window.RollbackManager.backupFunction('setAlert', window.setAlert);
    }
    if (typeof window.hideAlert === 'function') {
      window.RollbackManager.backupFunction('hideAlert', window.hideAlert);
    }
    if (typeof window.scrollToBottom === 'function') {
      window.RollbackManager.backupFunction('scrollToBottom', window.scrollToBottom);
    }
  }
  
  // === UI State Manager ===
  
  window.UIStateManager = {
    // Alert state
    currentAlert: null,
    alertTimeout: null,
    alertHistory: [],
    
    // Panel visibility state
    panels: {
      config: true,
      mainPanel: false,
      settings: false,
      conversation: false
    },
    
    // User preferences
    preferences: {
      autoScroll: true,
      easySubmit: false,
      autoSpeech: false,
      fontSize: 'medium',
      theme: 'light'
    },
    
    // Loading states
    loading: {
      global: false,
      message: false,
      thinking: false,
      uploading: false
    },
    
    // === Alert Management ===
    
    showAlert: function(message, type = 'info', duration = null) {
      try {
        console.log(`[UIStateManager] Alert: ${type} - ${message}`);
        
        // Clear existing timeout
        if (this.alertTimeout) {
          clearTimeout(this.alertTimeout);
          this.alertTimeout = null;
        }
        
        // Store alert info
        this.currentAlert = {
          message: message,
          type: type,
          timestamp: Date.now()
        };
        
        // Add to history
        this.alertHistory.push(this.currentAlert);
        if (this.alertHistory.length > 50) {
          this.alertHistory.shift(); // Keep only last 50
        }
        
        // Update SessionState if available
        if (window.SessionState) {
          window.SessionState.ui.currentAlert = this.currentAlert;
          window.SessionState.notifyListeners('ui:alert', this.currentAlert);
        }
        
        // Call original setAlert if it exists
        if (typeof window.originalSetAlert === 'function') {
          window.originalSetAlert(message, type);
        } else if (typeof window.setAlert === 'function' && window.setAlert !== this.showAlert) {
          window.setAlert(message, type);
        } else {
          // Direct DOM manipulation as fallback
          this.displayAlert(message, type);
        }
        
        // Auto-hide based on type
        if (duration === null) {
          duration = type === 'error' ? 10000 : (type === 'warning' ? 7000 : 5000);
        }
        
        if (duration > 0) {
          this.alertTimeout = setTimeout(() => {
            this.hideAlert();
          }, duration);
        }
        
        return true;
      } catch (error) {
        window.RollbackManager && window.RollbackManager.recordError(error, 'showAlert');
        // Fallback
        if (typeof window.setAlert === 'function') {
          window.setAlert(message, type);
        }
        return false;
      }
    },
    
    hideAlert: function() {
      try {
        this.currentAlert = null;
        
        if (this.alertTimeout) {
          clearTimeout(this.alertTimeout);
          this.alertTimeout = null;
        }
        
        // Update SessionState
        if (window.SessionState) {
          window.SessionState.ui.currentAlert = null;
          window.SessionState.notifyListeners('ui:alert-hidden');
        }
        
        // Call original hideAlert if exists
        if (typeof window.originalHideAlert === 'function') {
          window.originalHideAlert();
        } else if (typeof window.hideAlert === 'function' && window.hideAlert !== this.hideAlert) {
          window.hideAlert();
        } else {
          // Direct DOM manipulation
          $('#alert').hide();
        }
        
      } catch (error) {
        window.RollbackManager && window.RollbackManager.recordError(error, 'hideAlert');
      }
    },
    
    // Direct alert display (fallback)
    displayAlert: function(message, type) {
      const alertClass = {
        success: 'alert-success',
        warning: 'alert-warning',
        error: 'alert-danger',
        info: 'alert-info'
      }[type] || 'alert-info';
      
      const alertHtml = `
        <div id="alert" class="alert ${alertClass} alert-dismissible" role="alert">
          <span id="alert-message">${message}</span>
          <button type="button" class="close" id="alert-close">
            <span>&times;</span>
          </button>
        </div>
      `;
      
      // Remove existing alert
      $('#alert').remove();
      
      // Add new alert
      $('#alert-container, body').first().prepend(alertHtml);
      
      // Bind close button
      $('#alert-close').on('click', () => this.hideAlert());
    },
    
    // === Panel Visibility Management ===
    
    showPanel: function(panelName) {
      try {
        console.log(`[UIStateManager] Showing panel: ${panelName}`);
        
        this.panels[panelName] = true;
        
        // Update SessionState
        if (window.SessionState) {
          window.SessionState.ui[`${panelName}Visible`] = true;
          window.SessionState.notifyListeners('ui:panel-shown', { panel: panelName });
        }
        
        // Update DOM
        const selectors = {
          config: '#config',
          mainPanel: '#main-panel',
          settings: '#settings',
          conversation: '#conversation'
        };
        
        if (selectors[panelName]) {
          $(selectors[panelName]).show();
        }
        
        return true;
      } catch (error) {
        window.RollbackManager && window.RollbackManager.recordError(error, 'showPanel');
        return false;
      }
    },
    
    hidePanel: function(panelName) {
      try {
        console.log(`[UIStateManager] Hiding panel: ${panelName}`);
        
        this.panels[panelName] = false;
        
        // Update SessionState
        if (window.SessionState) {
          window.SessionState.ui[`${panelName}Visible`] = false;
          window.SessionState.notifyListeners('ui:panel-hidden', { panel: panelName });
        }
        
        // Update DOM
        const selectors = {
          config: '#config',
          mainPanel: '#main-panel',
          settings: '#settings',
          conversation: '#conversation'
        };
        
        if (selectors[panelName]) {
          $(selectors[panelName]).hide();
        }
        
        return true;
      } catch (error) {
        window.RollbackManager && window.RollbackManager.recordError(error, 'hidePanel');
        return false;
      }
    },
    
    togglePanel: function(panelName) {
      if (this.panels[panelName]) {
        return this.hidePanel(panelName);
      } else {
        return this.showPanel(panelName);
      }
    },
    
    // === User Preferences ===
    
    setPreference: function(key, value) {
      try {
        console.log(`[UIStateManager] Setting preference: ${key} = ${value}`);
        
        this.preferences[key] = value;
        
        // Update SessionState
        if (window.SessionState && window.SessionState.ui) {
          window.SessionState.ui[key] = value;
          window.SessionState.notifyListeners('ui:preference-changed', { key: key, value: value });
        }
        
        // Apply preference
        this.applyPreference(key, value);
        
        // Save to storage
        this.savePreferences();
        
        return true;
      } catch (error) {
        window.RollbackManager && window.RollbackManager.recordError(error, 'setPreference');
        return false;
      }
    },
    
    applyPreference: function(key, value) {
      switch (key) {
        case 'autoScroll':
          // Update checkbox if exists
          $('#auto-scroll-toggle').prop('checked', value);
          break;
          
        case 'easySubmit':
          $('#check-easy-submit').prop('checked', value);
          break;
          
        case 'autoSpeech':
          $('#check-auto-speech').prop('checked', value);
          break;
          
        case 'fontSize':
          // Apply font size class to body
          $('body').removeClass('font-small font-medium font-large').addClass(`font-${value}`);
          break;
          
        case 'theme':
          // Apply theme class
          $('body').removeClass('theme-light theme-dark').addClass(`theme-${value}`);
          break;
      }
    },
    
    getPreference: function(key) {
      return this.preferences[key];
    },
    
    // === Loading States ===
    
    setLoading: function(type, isLoading) {
      try {
        console.log(`[UIStateManager] Loading ${type}: ${isLoading}`);
        
        this.loading[type] = isLoading;
        
        // Update SessionState
        if (window.SessionState) {
          window.SessionState.ui.isLoading = this.loading.global || Object.values(this.loading).some(v => v);
          window.SessionState.notifyListeners('ui:loading-changed', { type: type, loading: isLoading });
        }
        
        // Update UI based on loading type
        this.updateLoadingUI(type, isLoading);
        
        return true;
      } catch (error) {
        window.RollbackManager && window.RollbackManager.recordError(error, 'setLoading');
        return false;
      }
    },
    
    updateLoadingUI: function(type, isLoading) {
      switch (type) {
        case 'global':
          if (isLoading) {
            $('body').addClass('loading');
            $('#loading-overlay').show();
          } else {
            $('body').removeClass('loading');
            $('#loading-overlay').hide();
          }
          break;
          
        case 'message':
          $('#send, #voice').prop('disabled', isLoading);
          if (isLoading) {
            $('#send').html('<i class="fas fa-spinner fa-spin"></i>');
          } else {
            $('#send').html('<i class="fas fa-paper-plane"></i>');
          }
          break;
          
        case 'thinking':
          if (isLoading) {
            this.showAlert('<i class="fas fa-robot"></i> THINKING', 'warning', 0);
          }
          break;
          
        case 'uploading':
          if (isLoading) {
            $('#file-upload-button').prop('disabled', true).html('<i class="fas fa-spinner fa-spin"></i>');
          } else {
            $('#file-upload-button').prop('disabled', false).html('<i class="fas fa-upload"></i>');
          }
          break;
      }
    },
    
    // === Scroll Management ===
    
    scrollToBottom: function(smooth = true) {
      try {
        const chatElement = $('#chat')[0];
        if (chatElement) {
          if (smooth) {
            chatElement.scrollTo({
              top: chatElement.scrollHeight,
              behavior: 'smooth'
            });
          } else {
            chatElement.scrollTop = chatElement.scrollHeight;
          }
        }
        
        // Notify listeners
        if (window.SessionState) {
          window.SessionState.notifyListeners('ui:scrolled-to-bottom');
        }
        
      } catch (error) {
        // Fallback to jQuery
        $('#chat').scrollTop($('#chat')[0].scrollHeight);
      }
    },
    
    // === Persistence ===
    
    savePreferences: function() {
      try {
        const prefsToSave = { ...this.preferences };
        
        if (window.EnvironmentDetector && window.EnvironmentDetector.storage) {
          window.EnvironmentDetector.storage.setItem('uiPreferences', prefsToSave);
        } else {
          localStorage.setItem('uiPreferences', JSON.stringify(prefsToSave));
        }
        
        console.log('[UIStateManager] Preferences saved');
      } catch (error) {
        console.error('[UIStateManager] Failed to save preferences:', error);
      }
    },
    
    loadPreferences: function() {
      try {
        let saved;
        
        if (window.EnvironmentDetector && window.EnvironmentDetector.storage) {
          saved = window.EnvironmentDetector.storage.getItem('uiPreferences');
        } else {
          const item = localStorage.getItem('uiPreferences');
          saved = item ? JSON.parse(item) : null;
        }
        
        if (saved) {
          Object.assign(this.preferences, saved);
          
          // Apply all preferences
          for (const [key, value] of Object.entries(this.preferences)) {
            this.applyPreference(key, value);
          }
          
          console.log('[UIStateManager] Preferences loaded');
        }
      } catch (error) {
        console.error('[UIStateManager] Failed to load preferences:', error);
      }
    },
    
    // === State Management ===
    
    getState: function() {
      return {
        panels: { ...this.panels },
        preferences: { ...this.preferences },
        loading: { ...this.loading },
        currentAlert: this.currentAlert,
        alertHistory: this.alertHistory.slice(-10) // Last 10 alerts
      };
    },
    
    restoreState: function(state) {
      try {
        if (state.panels) {
          Object.assign(this.panels, state.panels);
        }
        if (state.preferences) {
          Object.assign(this.preferences, state.preferences);
        }
        if (state.loading) {
          Object.assign(this.loading, state.loading);
        }
        
        // Apply restored state
        for (const [key, value] of Object.entries(this.preferences)) {
          this.applyPreference(key, value);
        }
        
        console.log('[UIStateManager] State restored');
      } catch (error) {
        console.error('[UIStateManager] Failed to restore state:', error);
      }
    }
  };
  
  // === Override global functions ===
  
  // Store original setAlert
  if (typeof window.setAlert === 'function' && !window.originalSetAlert) {
    window.originalSetAlert = window.setAlert;
  }
  
  // Override setAlert
  window.setAlert = function(message, type) {
    return window.UIStateManager.showAlert(message, type);
  };
  
  // Override hideAlert if it exists
  if (typeof window.hideAlert === 'function' && !window.originalHideAlert) {
    window.originalHideAlert = window.hideAlert;
    window.hideAlert = function() {
      return window.UIStateManager.hideAlert();
    };
  }
  
  // Override scrollToBottom if it exists
  if (typeof window.scrollToBottom === 'function' && !window.originalScrollToBottom) {
    window.originalScrollToBottom = window.scrollToBottom;
    window.scrollToBottom = function(smooth) {
      return window.UIStateManager.scrollToBottom(smooth);
    };
  }
  
  // === Integration with SessionState ===
  
  if (window.SessionState) {
    // Sync UI state with SessionState
    window.SessionState.ui = {
      ...window.SessionState.ui,
      ...window.UIStateManager.preferences,
      panels: { ...window.UIStateManager.panels },
      loading: { ...window.UIStateManager.loading }
    };
    
    // Listen for preference changes
    window.SessionState.on('ui:preference-changed', function(data) {
      console.log('[UIStateMigration] Preference changed:', data);
    });
  }
  
  // === Auto-load preferences on DOM ready ===
  
  document.addEventListener('DOMContentLoaded', function() {
    if (window.MigrationConfig.features.ui) {
      window.UIStateManager.loadPreferences();
      console.log('[UIStateMigration] Preferences auto-loaded');
    }
  });
  
  // === Migration Status ===
  
  window.UIStateMigration = {
    status: 'active',
    
    // Get migration statistics
    getStats: function() {
      return {
        enabled: window.MigrationConfig.features.ui,
        alertHistoryCount: window.UIStateManager.alertHistory.length,
        currentAlert: !!window.UIStateManager.currentAlert,
        preferencesLoaded: Object.keys(window.UIStateManager.preferences).length > 0,
        panelsConfigured: Object.keys(window.UIStateManager.panels).length,
        usingSessionState: !!(window.SessionState && window.SessionState.ui)
      };
    },
    
    // Test UI operations
    testOperations: function() {
      console.group('[UIStateMigration] Testing operations');
      
      const results = {};
      
      try {
        // Test alert
        window.UIStateManager.showAlert('Test alert', 'info');
        results.showAlert = !!window.UIStateManager.currentAlert;
        window.UIStateManager.hideAlert();
        results.hideAlert = !window.UIStateManager.currentAlert;
        
        // Test preferences
        const originalAutoScroll = window.UIStateManager.getPreference('autoScroll');
        window.UIStateManager.setPreference('autoScroll', !originalAutoScroll);
        results.setPreference = window.UIStateManager.getPreference('autoScroll') !== originalAutoScroll;
        window.UIStateManager.setPreference('autoScroll', originalAutoScroll);
        
        // Test loading states
        window.UIStateManager.setLoading('message', true);
        results.setLoading = window.UIStateManager.loading.message === true;
        window.UIStateManager.setLoading('message', false);
        
        // Test state management
        const state = window.UIStateManager.getState();
        results.getState = state && state.panels && state.preferences;
        
      } catch (error) {
        console.error('[UIStateMigration] Test error:', error);
      }
      
      console.table(results);
      console.groupEnd();
      
      return results;
    }
  };
  
  console.log('[UIStateMigration] UI state migration complete');
  console.log('[UIStateMigration] Stats:', window.UIStateMigration.getStats());
  
})();