// Centralized session state management
// This module manages session-related flags to ensure consistency across different parts of the application

(function() {
  'use strict';
  
  // Session state object
  window.SessionState = {
    // Flag to indicate that a new session should be forced (messages should be cleared)
    forceNewSession: false,
    
    // Flag to indicate that a reset just happened (currently unused, kept for potential future use)
    justReset: false,
    
    // Method to set reset flags when reset action occurs
    setResetFlags: function() {
      this.forceNewSession = true;
      this.justReset = true;
    },
    
    // Method to clear the forceNewSession flag after it has been processed
    clearForceNewSession: function() {
      this.forceNewSession = false;
    },
    
    // Method to clear the justReset flag if needed
    clearJustReset: function() {
      this.justReset = false;
    },
    
    // Method to check if a new session should be forced
    shouldForceNewSession: function() {
      return this.forceNewSession === true;
    },
    
    // Method to reset all flags
    resetAllFlags: function() {
      this.forceNewSession = false;
      this.justReset = false;
    }
  };
  
  // For backward compatibility, maintain the global variables but sync them with SessionState
  // This allows gradual migration without breaking existing code
  Object.defineProperty(window, 'forceNewSession', {
    get: function() {
      return window.SessionState.forceNewSession;
    },
    set: function(value) {
      window.SessionState.forceNewSession = value;
    }
  });
  
  Object.defineProperty(window, 'justReset', {
    get: function() {
      return window.SessionState.justReset;
    },
    set: function(value) {
      window.SessionState.justReset = value;
    }
  });
  
})();