// Centralized session state management
// This module provides a single source of truth for all application state

(function() {
  'use strict';
  
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
      return message;
    },
    
    clearMessages: function() {
      this.conversation.messages = [];
      this.notifyListeners('messages:cleared');
    },
    
    updateLastMessage: function(content) {
      if (this.conversation.messages.length > 0) {
        const lastMessage = this.conversation.messages[this.conversation.messages.length - 1];
        lastMessage.content = content;
        this.notifyListeners('message:updated', lastMessage);
      }
    },
    
    deleteMessage: function(index) {
      if (index >= 0 && index < this.conversation.messages.length) {
        const deleted = this.conversation.messages.splice(index, 1)[0];
        this.notifyListeners('message:deleted', { index: index, message: deleted });
        return deleted;
      }
      return null;
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
            started: this.session.started
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
          // Fallback to localStorage
          localStorage.setItem('monadicState', JSON.stringify(stateToSave));
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