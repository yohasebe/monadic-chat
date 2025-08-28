/**
 * Centralized UI State Management
 * Single source of truth for all UI state variables
 */

(function(window) {
  'use strict';
  
  // Private state object
  const state = {
    // Streaming and loading states
    isStreaming: false,
    streamingResponse: false,
    isLoading: false,
    
    // Menu and layout states
    isMenuVisible: true,
    toggleMenuLocked: false,
    
    // Scroll states
    autoScroll: true,
    scrollPosition: {
      main: 0,
      menu: 0
    },
    
    // Window dimensions
    windowWidth: 0,
    windowHeight: 0,
    previousWidth: null,
    
    // Resize tracking
    isResizing: false,
    resizeTimeout: null,
    resizeObserverTimeout: null,
    
    // WebSocket state
    wsConnected: false,
    wsReconnecting: false,
    
    // Session state
    currentApp: null,
    currentModel: null,
    sessionActive: false,
    
    // UI element visibility
    spinnerVisible: false,
    scrollButtonsVisible: {
      top: false,
      bottom: false
    }
  };
  
  // State change listeners
  const listeners = new Map();
  
  // Public API
  const UIState = {
    
    /**
     * Get current value of a state property
     * @param {string} key - The state key to retrieve
     * @returns {*} The current value
     */
    get(key) {
      const keys = key.split('.');
      let value = state;
      for (const k of keys) {
        if (value && typeof value === 'object') {
          value = value[k];
        } else {
          return undefined;
        }
      }
      return value;
    },
    
    /**
     * Set a state property value
     * @param {string} key - The state key to set
     * @param {*} value - The new value
     */
    set(key, value) {
      const keys = key.split('.');
      const lastKey = keys.pop();
      let target = state;
      
      for (const k of keys) {
        if (!target[k] || typeof target[k] !== 'object') {
          target[k] = {};
        }
        target = target[k];
      }
      
      const oldValue = target[lastKey];
      target[lastKey] = value;
      
      // Notify listeners
      this.notifyListeners(key, value, oldValue);
      
      // Handle special cases
      this.handleStateChange(key, value, oldValue);
    },
    
    /**
     * Update multiple state properties at once
     * @param {Object} updates - Object with key-value pairs to update
     */
    update(updates) {
      Object.entries(updates).forEach(([key, value]) => {
        this.set(key, value);
      });
    },
    
    /**
     * Subscribe to state changes
     * @param {string} key - The state key to watch (or '*' for all)
     * @param {Function} callback - Function to call on change
     * @returns {Function} Unsubscribe function
     */
    subscribe(key, callback) {
      if (!listeners.has(key)) {
        listeners.set(key, new Set());
      }
      listeners.get(key).add(callback);
      
      // Return unsubscribe function
      return () => {
        const callbacks = listeners.get(key);
        if (callbacks) {
          callbacks.delete(callback);
          if (callbacks.size === 0) {
            listeners.delete(key);
          }
        }
      };
    },
    
    /**
     * Notify listeners of state change
     * @private
     */
    notifyListeners(key, newValue, oldValue) {
      // Notify specific key listeners
      const callbacks = listeners.get(key);
      if (callbacks) {
        callbacks.forEach(callback => {
          try {
            callback(newValue, oldValue, key);
          } catch (error) {
            console.error('Error in state listener:', error);
          }
        });
      }
      
      // Notify wildcard listeners
      const wildcardCallbacks = listeners.get('*');
      if (wildcardCallbacks) {
        wildcardCallbacks.forEach(callback => {
          try {
            callback(newValue, oldValue, key);
          } catch (error) {
            console.error('Error in wildcard state listener:', error);
          }
        });
      }
    },
    
    /**
     * Handle special state changes that require side effects
     * @private
     */
    handleStateChange(key, newValue, oldValue) {
      switch (key) {
        case 'isStreaming':
        case 'streamingResponse':
          // Update toggle menu state when streaming changes
          if (newValue) {
            this.set('toggleMenuLocked', true);
            // Update UI elements
            const toggleBtn = document.getElementById('toggle-menu');
            if (toggleBtn) {
              toggleBtn.classList.add('streaming-active');
              toggleBtn.style.cursor = 'not-allowed';
            }
          } else {
            this.set('toggleMenuLocked', false);
            const toggleBtn = document.getElementById('toggle-menu');
            if (toggleBtn) {
              toggleBtn.classList.remove('streaming-active');
              toggleBtn.style.cursor = '';
            }
          }
          break;
          
        case 'windowWidth':
          // Track previous width for boundary detection
          if (oldValue !== undefined) {
            this.set('previousWidth', oldValue);
          }
          break;
          
        case 'wsConnected':
          // Handle WebSocket connection state changes
          if (!newValue && !this.get('wsReconnecting')) {
            console.warn('WebSocket disconnected');
          }
          break;
      }
    },
    
    /**
     * Initialize state with current values
     */
    initialize() {
      // Set initial window dimensions
      this.set('windowWidth', window.innerWidth);
      this.set('windowHeight', window.innerHeight);
      
      // Check initial menu visibility
      const menu = document.getElementById('menu');
      if (menu) {
        this.set('isMenuVisible', menu.style.display !== 'none');
      }
      
      // Check initial spinner state
      const spinner = document.getElementById('monadic-spinner');
      if (spinner) {
        this.set('spinnerVisible', spinner.style.display !== 'none');
      }
      
      // Set up window resize listener
      window.addEventListener('resize', () => {
        this.set('isResizing', true);
        this.set('windowWidth', window.innerWidth);
        this.set('windowHeight', window.innerHeight);
        
        // Clear existing timeout
        if (this.get('resizeTimeout')) {
          clearTimeout(this.get('resizeTimeout'));
        }
        
        // Set new timeout
        const timeout = setTimeout(() => {
          this.set('isResizing', false);
        }, 250);
        
        this.set('resizeTimeout', timeout);
      });
    },
    
    /**
     * Get all current state (for debugging)
     */
    getState() {
      return JSON.parse(JSON.stringify(state));
    },
    
    /**
     * Reset state to defaults
     */
    reset() {
      Object.keys(state).forEach(key => {
        if (typeof state[key] === 'boolean') {
          state[key] = false;
        } else if (typeof state[key] === 'number') {
          state[key] = 0;
        } else if (typeof state[key] === 'string') {
          state[key] = '';
        } else if (state[key] !== null && typeof state[key] === 'object') {
          // Reset nested objects recursively
          if (Array.isArray(state[key])) {
            state[key] = [];
          } else {
            Object.keys(state[key]).forEach(nestedKey => {
              if (typeof state[key][nestedKey] === 'boolean') {
                state[key][nestedKey] = false;
              } else if (typeof state[key][nestedKey] === 'number') {
                state[key][nestedKey] = 0;
              } else {
                state[key][nestedKey] = null;
              }
            });
          }
        }
      });
    }
  };
  
  // Export to window
  window.UIState = UIState;
  
  // Also export for CommonJS environments (testing)
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = UIState;
  }
  
})(typeof window !== 'undefined' ? window : this);