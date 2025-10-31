// Centralized session state management
// This module provides a single source of truth for all application state

(function() {
  'use strict';
  
  // === Safe SessionState Operations ===
  // These functions provide error-safe access to SessionState
  window.safeSessionState = {
    // Check if SessionState is available
    isAvailable: function() {
      return window.SessionState && typeof window.SessionState === 'object';
    },
    
    // Safe message operations
    addMessage: function(message) {
      try {
        if (!this.isAvailable()) {
          console.error('[SessionState] Not initialized. Cannot add message.');
          return false;
        }
        if (!message || typeof message !== 'object') {
          console.error('[SessionState] Invalid message object:', message);
          return false;
        }
        window.SessionState.addMessage(message);
        return true;
      } catch (error) {
        console.error('[SessionState] Error adding message:', error);
        return false;
      }
    },
    
    removeMessage: function(index) {
      try {
        if (!this.isAvailable()) {
          console.error('[SessionState] Not initialized. Cannot remove message.');
          return false;
        }
        if (typeof index !== 'number' || index < 0) {
          console.error('[SessionState] Invalid message index:', index);
          return false;
        }
        window.SessionState.removeMessage(index);
        return true;
      } catch (error) {
        console.error('[SessionState] Error removing message:', error);
        return false;
      }
    },
    
    clearMessages: function() {
      try {
        if (!this.isAvailable()) {
          console.error('[SessionState] Not initialized. Cannot clear messages.');
          return false;
        }
        window.SessionState.clearMessages();
        return true;
      } catch (error) {
        console.error('[SessionState] Error clearing messages:', error);
        return false;
      }
    },
    
    // Safe session flag operations
    setResetFlags: function() {
      try {
        if (!this.isAvailable()) {
          console.error('[SessionState] Not initialized. Cannot set reset flags.');
          return false;
        }
        window.SessionState.setResetFlags();
        return true;
      } catch (error) {
        console.error('[SessionState] Error setting reset flags:', error);
        return false;
      }
    },
    
    clearResetFlags: function() {
      try {
        if (!this.isAvailable()) {
          console.error('[SessionState] Not initialized. Cannot clear reset flags.');
          return false;
        }
        window.SessionState.clearResetFlags();
        return true;
      } catch (error) {
        console.error('[SessionState] Error clearing reset flags:', error);
        return false;
      }
    },
    
    shouldForceNewSession: function() {
      try {
        if (!this.isAvailable()) {
          console.warn('[SessionState] Not initialized. Returning false for shouldForceNewSession.');
          return false;
        }
        return window.SessionState.shouldForceNewSession();
      } catch (error) {
        console.error('[SessionState] Error checking force new session:', error);
        return false;
      }
    },
    
    clearForceNewSession: function() {
      try {
        if (!this.isAvailable()) {
          console.error('[SessionState] Not initialized. Cannot clear force new session.');
          return false;
        }
        window.SessionState.clearForceNewSession();
        return true;
      } catch (error) {
        console.error('[SessionState] Error clearing force new session:', error);
        return false;
      }
    }
  };
  
  // Main state object
  window.SessionState = {
    // === Legacy flags (for backward compatibility) ===
    forceNewSession: false,
    justReset: false,
    
    // === Core Session State ===
    session: {
      id: null,
      started: false,
      forceNew: false,
      justReset: false
    },
    
    // === Conversation State ===
    conversation: {
      messages: [],
      currentQuery: null,
      isStreaming: false,
      responseStarted: false,
      callingFunction: false
    },
    
    // === Application State ===
    app: {
      current: null,
      params: {},
      originalParams: {},
      model: null,
      modelOptions: []
    },
    
    // === UI State ===
    ui: {
      autoScroll: true,
      isLoading: false,
      configVisible: true,
      mainPanelVisible: false
    },
    
    // === WebSocket State ===
    connection: {
      ws: null,
      reconnectDelay: 1000,
      pingInterval: null,
      isConnected: false
    },
    
    // === Audio State ===
    audio: {
      queue: [],
      isPlaying: false,
      currentSegment: null,
      enabled: false
    },
    
    // === Legacy Methods (for backward compatibility) ===
    setResetFlags: function() {
      this.forceNewSession = true;
      this.justReset = true;
      this.session.forceNew = true;
      this.session.justReset = true;
      this.notifyListeners('session:reset-flags-set');
    },
    
    clearForceNewSession: function() {
      this.forceNewSession = false;
      this.session.forceNew = false;
      this.notifyListeners('session:force-new-cleared');
    },
    
    clearJustReset: function() {
      this.justReset = false;
      this.session.justReset = false;
    },
    
    shouldForceNewSession: function() {
      return this.forceNewSession === true || this.session.forceNew === true;
    },
    
    resetAllFlags: function() {
      this.forceNewSession = false;
      this.justReset = false;
      this.session.forceNew = false;
      this.session.justReset = false;
      this.notifyListeners('session:all-flags-reset');
    },
    
    // === New State Management Methods ===
    
    // Session management
    startNewSession: function() {
      this.session.forceNew = true;
      this.session.started = true;
      this.conversation.messages = [];
      this.forceNewSession = true; // Legacy support
      this.notifyListeners('session:new', { id: this.session.id });
    },
    
    resetSession: function() {
      this.setResetFlags();
      this.conversation.messages = [];
      this.session.started = false;
      this.notifyListeners('session:reset');
    },
    
    // Message management
    addMessage: function(message) {
      try {
        if (!message || typeof message !== 'object') {
          console.error('[SessionState.addMessage] Invalid message:', message);
          return null;
        }
        // Add to internal array
        this.conversation.messages.push(message);
      
      // Sync with legacy messages array if it exists (avoid Array.prototype.push override)
      if (window.messages && Array.isArray(window.messages)) {
        // Check if message is not already in the array
        if (!window.messages.some(m => m === message || (m.mid && m.mid === message.mid))) {
          // Use original push if available, or direct assignment
          if (window.originalPush) {
            window.originalPush.call(window.messages, message);
          } else {
            window.messages[window.messages.length] = message;
          }
        }
      }
      
      this.notifyListeners('message:added', message);

      // Auto-save state after adding message (debounced to avoid excessive writes)
      if (!this._saveTimeout) {
        this._saveTimeout = setTimeout(() => {
          this.save();
          this._saveTimeout = null;
        }, 500);  // Save 500ms after the last message addition
      }

      return message;
      } catch (error) {
        console.error('[SessionState.addMessage] Error:', error);
        return null;
      }
    },
    
    clearMessages: function() {
      try {
        this.conversation.messages = [];
        this.notifyListeners('messages:cleared');
      } catch (error) {
        console.error('[SessionState.clearMessages] Error:', error);
      }
    },
    
    updateLastMessage: function(content) {
      try {
        if (this.conversation.messages.length > 0) {
          const lastMessage = this.conversation.messages[this.conversation.messages.length - 1];
          lastMessage.content = content;
          this.notifyListeners('message:updated', lastMessage);
        }
      } catch (error) {
        console.error('[SessionState.updateLastMessage] Error:', error);
      }
    },
    
    deleteMessage: function(index) {
      try {
        if (typeof index !== 'number' || index < 0) {
          console.error('[SessionState.deleteMessage] Invalid index:', index);
          return null;
        }
        if (index >= 0 && index < this.conversation.messages.length) {
          const deleted = this.conversation.messages.splice(index, 1)[0];
          this.notifyListeners('message:deleted', { index: index, message: deleted });
          return deleted;
        }
        console.warn('[SessionState.deleteMessage] Index out of bounds:', index);
        return null;
      } catch (error) {
        console.error('[SessionState.deleteMessage] Error:', error);
        return null;
      }
    },
    
    // Alias for deleteMessage
    removeMessage: function(index) {
      return this.deleteMessage(index);
    },
    
    // === Session Flag Methods ===
    setResetFlags: function() {
      try {
        this.session.forceNew = true;
        this.session.justReset = true;
        // Also set legacy flags for compatibility
        this.forceNewSession = true;
        this.justReset = true;
        this.notifyListeners('flags:reset', { forceNew: true, justReset: true });
        // Save to localStorage so flags persist across page reloads
        this.save();
        console.log('[SessionState] Reset flags set and saved to localStorage');
      } catch (error) {
        console.error('[SessionState.setResetFlags] Error:', error);
      }
    },
    
    clearResetFlags: function() {
      try {
        this.session.forceNew = false;
        this.session.justReset = false;
        // Also clear legacy flags
        this.forceNewSession = false;
        this.justReset = false;
        this.notifyListeners('flags:cleared', { forceNew: false, justReset: false });
        // Save to localStorage to persist cleared flags
        this.save();
        console.log('[SessionState] Reset flags cleared and saved to localStorage');
      } catch (error) {
        console.error('[SessionState.clearResetFlags] Error:', error);
      }
    },
    
    shouldForceNewSession: function() {
      try {
        return this.session.forceNew === true || this.forceNewSession === true;
      } catch (error) {
        console.error('[SessionState.shouldForceNewSession] Error:', error);
        return false;
      }
    },
    
    clearForceNewSession: function() {
      try {
        this.session.forceNew = false;
        this.forceNewSession = false;
        this.notifyListeners('flags:forceNewCleared', { forceNew: false });
      } catch (error) {
        console.error('[SessionState.clearForceNewSession] Error:', error);
      }
    },
    
    // State getters with validation
    getMessages: function() {
      return [...this.conversation.messages]; // Return copy to prevent direct mutation
    },
    
    getCurrentApp: function() {
      return this.app.current;
    },
    
    getAppParams: function() {
      return { ...this.app.params }; // Return copy
    },
    
    // App state management
    setCurrentApp: function(appName, params) {
      this.app.current = appName;
      if (params) {
        this.app.params = { ...params };
        this.app.originalParams = { ...params };
      }
      this.notifyListeners('app:changed', { app: appName, params: params });
    },
    
    updateAppParams: function(params) {
      Object.assign(this.app.params, params);
      this.notifyListeners('app:params-updated', params);
    },
    
    // Connection state
    setWebSocket: function(ws) {
      this.connection.ws = ws;
      this.connection.isConnected = ws && ws.readyState === WebSocket.OPEN;
      this.notifyListeners('connection:updated', { connected: this.connection.isConnected });
    },
    
    // === Event System ===
    listeners: new Map(),
    
    on: function(event, callback) {
      if (!this.listeners.has(event)) {
        this.listeners.set(event, []);
      }
      this.listeners.get(event).push(callback);
      return callback; // Return for easy removal
    },
    
    off: function(event, callback) {
      if (this.listeners.has(event)) {
        const callbacks = this.listeners.get(event);
        const index = callbacks.indexOf(callback);
        if (index > -1) {
          callbacks.splice(index, 1);
        }
      }
    },
    
    once: function(event, callback) {
      const wrapper = (data) => {
        callback(data);
        this.off(event, wrapper);
      };
      this.on(event, wrapper);
    },
    
    notifyListeners: function(event, data) {
      if (this.listeners.has(event)) {
        this.listeners.get(event).forEach(callback => {
          try {
            callback(data);
          } catch (error) {
            console.error(`Error in event listener for ${event}:`, error);
          }
        });
      }
      
      // Log state changes in debug mode
      if (window.DEBUG_STATE_CHANGES) {
        console.log(`[SessionState] Event: ${event}`, data);
      }
    },
    
    // === State Persistence ===
    save: function() {
      try {
        const stateToSave = {
          session: {
            id: this.session.id,
            started: this.session.started,
            forceNew: this.session.forceNew,
            justReset: this.session.justReset
          },
          app: {
            current: this.app.current,
            params: this.app.params,
            model: this.app.model
          },
          conversation: {
            // Only save last 50 messages to avoid storage limits
            messages: this.conversation.messages.slice(-50)
          },
          ui: {
            autoScroll: this.ui.autoScroll
          }
        };
        
        // Use environment-aware storage if available
        if (window.EnvironmentDetector && window.EnvironmentDetector.storage) {
          window.EnvironmentDetector.storage.setItem('monadicState', stateToSave);
        } else {
          // Fallback to localStorage with safe storage helper
          StorageHelper.safeSetItem('monadicState', JSON.stringify(stateToSave));
        }
        
        this.notifyListeners('state:saved');
      } catch (error) {
        console.error('Failed to save state:', error);
      }
    },
    
    restore: function() {
      try {
        let saved;
        
        // Use environment-aware storage if available
        if (window.EnvironmentDetector && window.EnvironmentDetector.storage) {
          saved = window.EnvironmentDetector.storage.getItem('monadicState');
        } else {
          // Fallback to localStorage
          const item = localStorage.getItem('monadicState');
          saved = item ? JSON.parse(item) : null;
        }
        
        if (saved) {
          // Restore session state
          if (saved.session) {
            Object.assign(this.session, saved.session);
          }
          
          // Restore app state
          if (saved.app) {
            Object.assign(this.app, saved.app);
          }
          
          // Restore conversation
          if (saved.conversation && saved.conversation.messages) {
            this.conversation.messages = saved.conversation.messages;
          }
          
          // Restore UI preferences
          if (saved.ui) {
            Object.assign(this.ui, saved.ui);
          }
          
          this.notifyListeners('state:restored', saved);
        }
      } catch (error) {
        console.error('Failed to restore state:', error);
      }
    },
    
    // === Health Check ===
    validateState: function() {
      const checks = {
        messagesIsArray: Array.isArray(this.conversation.messages),
        sessionIdValid: this.session.id === null || typeof this.session.id === 'string',
        appCurrentValid: this.app.current === null || typeof this.app.current === 'string',
        flagsAreBoolean: typeof this.forceNewSession === 'boolean' && typeof this.justReset === 'boolean'
      };
      
      const allValid = Object.values(checks).every(check => check === true);
      
      if (!allValid && window.DEBUG_STATE_CHANGES) {
        console.warn('[SessionState] Validation failed:', checks);
      }
      
      return allValid;
    },
    
    // === Debug Helper ===
    getStateSnapshot: function() {
      return {
        session: { ...this.session },
        conversation: {
          messageCount: this.conversation.messages.length,
          isStreaming: this.conversation.isStreaming,
          responseStarted: this.conversation.responseStarted
        },
        app: { ...this.app },
        ui: { ...this.ui },
        connection: {
          isConnected: this.connection.isConnected,
          hasWebSocket: !!this.connection.ws
        },
        audio: {
          queueLength: this.audio.queue.length,
          isPlaying: this.audio.isPlaying
        }
      };
    }
  };
  
  // Maintain backward compatibility with global variables for external code that may still use them
  // Check if properties are already defined to avoid redefinition errors in tests
  if (!Object.getOwnPropertyDescriptor(window, 'forceNewSession')) {
    Object.defineProperty(window, 'forceNewSession', {
      get: function() {
        return window.SessionState.forceNewSession;
      },
      set: function(value) {
        window.SessionState.forceNewSession = value;
      },
      configurable: true // Allow redefinition in tests
    });
  }
  
  if (!Object.getOwnPropertyDescriptor(window, 'justReset')) {
    Object.defineProperty(window, 'justReset', {
      get: function() {
        return window.SessionState.justReset;
      },
      set: function(value) {
        window.SessionState.justReset = value;
      },
      configurable: true // Allow redefinition in tests
    });
  }
  
  // Create global messages array compatibility layer
  // This ensures backward compatibility with code that directly accesses the messages array
  if (!window.messages) {
    // Initialize with empty array if not exists
    window.messages = [];
  }
  
  // Override the messages array to sync with SessionState
  // Check if already defined to avoid redefinition errors in tests
  if (!Object.getOwnPropertyDescriptor(window, 'messages') || 
      !Object.getOwnPropertyDescriptor(window, 'messages').get) {
    Object.defineProperty(window, 'messages', {
      get: function() {
        // Return the SessionState messages array
        return window.SessionState.conversation.messages;
      },
      set: function(value) {
        // Handle direct assignment to messages array
        if (Array.isArray(value)) {
          console.warn('Direct assignment to messages array is deprecated. Use SessionState methods instead.');
          // Clear and repopulate SessionState messages
          window.SessionState.conversation.messages = [...value];
          
          // Notify listeners of the change
          if (window.SessionState.notifyListeners) {
            window.SessionState.notifyListeners('conversation', window.SessionState.conversation);
          }
        } else {
          console.error('Invalid assignment to messages array. Expected array, got:', typeof value);
        }
      },
      configurable: true,
      enumerable: true
    });
  }
  
  // Also ensure array methods work correctly
  // The messages array returned by the getter will have all Array.prototype methods
  
})();