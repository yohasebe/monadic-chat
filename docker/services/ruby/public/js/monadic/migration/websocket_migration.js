// WebSocket State Migration
// Centralizes WebSocket management and provides a clean API for connection handling

(function() {
  'use strict';
  
  // Check if migration is enabled
  if (!window.MigrationConfig || !window.MigrationConfig.features.websocket) {
    console.log('[WebSocketMigration] Not enabled');
    return;
  }
  
  console.log('[WebSocketMigration] Starting WebSocket state migration');
  
  // Backup original WebSocket variable for rollback
  if (window.RollbackManager) {
    window.RollbackManager.backupValue('ws', window.ws);
    window.RollbackManager.backupFunction('connect_websocket', window.connect_websocket);
    window.RollbackManager.backupFunction('reconnect_websocket', window.reconnect_websocket);
  }
  
  // === WebSocket Manager ===
  
  window.WebSocketManager = {
    // Connection state
    connection: null,
    reconnectTimer: null,
    reconnectDelay: 1000,
    maxReconnectDelay: 30000,
    reconnectAttempts: 0,
    
    // Ping/Pong for keep-alive
    pingTimer: null,
    pingInterval: 30000, // 30 seconds
    
    // Message queue for offline handling
    messageQueue: [],
    queueEnabled: false,
    
    // Event handlers
    handlers: new Map(),
    
    // Get current connection
    getConnection: function() {
      try {
        // Use SessionState if available
        if (window.SessionState && window.SessionState.connection) {
          return window.SessionState.connection.ws || this.connection;
        }
        return this.connection || window.ws;
      } catch (error) {
        window.RollbackManager && window.RollbackManager.recordError(error, 'getConnection');
        return window.ws; // Fallback
      }
    },
    
    // Check connection status
    isConnected: function() {
      const ws = this.getConnection();
      return ws && ws.readyState === WebSocket.OPEN;
    },
    
    // Connect to WebSocket server
    connect: function(url, options = {}) {
      try {
        console.log('[WebSocketManager] Connecting to:', url || 'default');
        
        // Close existing connection if any
        if (this.connection) {
          this.disconnect();
        }
        
        // Use original connect_websocket if available and no URL specified
        if (!url && typeof window.connect_websocket === 'function') {
          this.connection = window.connect_websocket();
        } else {
          // Create new WebSocket connection
          const wsUrl = url || this.getDefaultUrl();
          this.connection = new WebSocket(wsUrl);
        }
        
        // Setup event handlers
        this.setupEventHandlers(this.connection);
        
        // Update SessionState if available
        if (window.SessionState) {
          window.SessionState.setWebSocket(this.connection);
        }
        
        // Update global reference for legacy code
        window.ws = this.connection;
        
        // Start ping timer
        this.startPing();
        
        return this.connection;
      } catch (error) {
        window.RollbackManager && window.RollbackManager.recordError(error, 'connect');
        console.error('[WebSocketManager] Connection failed:', error);
        
        // Fallback to original method
        if (typeof window.connect_websocket === 'function') {
          this.connection = window.connect_websocket();
          window.ws = this.connection;
          return this.connection;
        }
        
        throw error;
      }
    },
    
    // Disconnect WebSocket
    disconnect: function() {
      try {
        console.log('[WebSocketManager] Disconnecting');
        
        // Stop ping timer
        this.stopPing();
        
        // Clear reconnect timer
        if (this.reconnectTimer) {
          clearTimeout(this.reconnectTimer);
          this.reconnectTimer = null;
        }
        
        // Close connection
        if (this.connection) {
          this.connection.close();
          this.connection = null;
        }
        
        // Update SessionState
        if (window.SessionState) {
          window.SessionState.setWebSocket(null);
        }
        
        // Clear global reference
        window.ws = null;
        
        // Notify listeners
        this.notifyHandlers('disconnected');
        
      } catch (error) {
        window.RollbackManager && window.RollbackManager.recordError(error, 'disconnect');
        console.error('[WebSocketManager] Disconnect error:', error);
      }
    },
    
    // Reconnect with exponential backoff
    reconnect: function(immediate = false) {
      try {
        // Clear existing timer
        if (this.reconnectTimer) {
          clearTimeout(this.reconnectTimer);
        }
        
        const delay = immediate ? 0 : Math.min(
          this.reconnectDelay * Math.pow(2, this.reconnectAttempts),
          this.maxReconnectDelay
        );
        
        console.log(`[WebSocketManager] Reconnecting in ${delay}ms (attempt ${this.reconnectAttempts + 1})`);
        
        this.reconnectTimer = setTimeout(() => {
          this.reconnectAttempts++;
          
          // Use original reconnect_websocket if available
          if (typeof window.reconnect_websocket === 'function' && this.connection) {
            window.reconnect_websocket(this.connection, (newWs) => {
              this.connection = newWs;
              window.ws = newWs;
              this.setupEventHandlers(newWs);
              
              if (window.SessionState) {
                window.SessionState.setWebSocket(newWs);
              }
              
              // Reset reconnect attempts on success
              this.reconnectAttempts = 0;
              
              // Process queued messages
              this.processMessageQueue();
            });
          } else {
            // Manual reconnect
            this.connect();
          }
        }, delay);
        
      } catch (error) {
        window.RollbackManager && window.RollbackManager.recordError(error, 'reconnect');
        console.error('[WebSocketManager] Reconnect error:', error);
      }
    },
    
    // Send message with optional queueing
    send: function(data, options = {}) {
      try {
        const message = typeof data === 'string' ? data : JSON.stringify(data);
        
        if (this.isConnected()) {
          const ws = this.getConnection();
          ws.send(message);
          
          // Notify listeners
          this.notifyHandlers('message:sent', { data: data, raw: message });
          
          return true;
        } else if (this.queueEnabled || options.queue) {
          // Queue message for later
          console.log('[WebSocketManager] Queueing message (not connected)');
          this.messageQueue.push({ data: data, options: options });
          
          // Attempt reconnection
          if (!this.reconnectTimer) {
            this.reconnect();
          }
          
          return false;
        } else {
          console.warn('[WebSocketManager] Cannot send message (not connected)');
          return false;
        }
      } catch (error) {
        window.RollbackManager && window.RollbackManager.recordError(error, 'send');
        console.error('[WebSocketManager] Send error:', error);
        return false;
      }
    },
    
    // Process queued messages
    processMessageQueue: function() {
      if (this.messageQueue.length === 0) return;
      
      console.log(`[WebSocketManager] Processing ${this.messageQueue.length} queued messages`);
      
      const queue = [...this.messageQueue];
      this.messageQueue = [];
      
      queue.forEach(item => {
        this.send(item.data, item.options);
      });
    },
    
    // Setup event handlers for WebSocket
    setupEventHandlers: function(ws) {
      if (!ws) return;
      
      // Open event
      ws.addEventListener('open', (event) => {
        console.log('[WebSocketManager] Connected');
        this.reconnectAttempts = 0;
        
        // Update connection state
        if (window.SessionState) {
          window.SessionState.connection.isConnected = true;
        }
        
        // Process queued messages
        this.processMessageQueue();
        
        // Notify handlers
        this.notifyHandlers('connected', event);
      });
      
      // Message event
      ws.addEventListener('message', (event) => {
        // Notify handlers
        this.notifyHandlers('message:received', event);
        
        // Call original wsHandlers if available
        if (window.wsHandlers && window.wsHandlers.handleMessage) {
          window.wsHandlers.handleMessage(event);
        }
      });
      
      // Error event
      ws.addEventListener('error', (event) => {
        console.error('[WebSocketManager] Error:', event);
        
        // Notify handlers
        this.notifyHandlers('error', event);
        
        // Record error for rollback monitoring
        window.RollbackManager && window.RollbackManager.recordError(
          new Error('WebSocket error'),
          'websocket:error'
        );
      });
      
      // Close event
      ws.addEventListener('close', (event) => {
        console.log('[WebSocketManager] Disconnected:', event.code, event.reason);
        
        // Update connection state
        if (window.SessionState) {
          window.SessionState.connection.isConnected = false;
        }
        
        // Notify handlers
        this.notifyHandlers('disconnected', event);
        
        // Auto-reconnect if not intentional close
        if (event.code !== 1000 && event.code !== 1001) {
          this.reconnect();
        }
      });
    },
    
    // Ping/Pong for keep-alive
    startPing: function() {
      this.stopPing();
      
      this.pingTimer = setInterval(() => {
        if (this.isConnected()) {
          this.send({ type: 'ping' });
        }
      }, this.pingInterval);
    },
    
    stopPing: function() {
      if (this.pingTimer) {
        clearInterval(this.pingTimer);
        this.pingTimer = null;
      }
    },
    
    // Event handler management
    on: function(event, handler) {
      if (!this.handlers.has(event)) {
        this.handlers.set(event, []);
      }
      this.handlers.get(event).push(handler);
      return handler;
    },
    
    off: function(event, handler) {
      if (this.handlers.has(event)) {
        const handlers = this.handlers.get(event);
        const index = handlers.indexOf(handler);
        if (index > -1) {
          handlers.splice(index, 1);
        }
      }
    },
    
    notifyHandlers: function(event, data) {
      if (this.handlers.has(event)) {
        this.handlers.get(event).forEach(handler => {
          try {
            handler(data);
          } catch (error) {
            console.error(`[WebSocketManager] Handler error for ${event}:`, error);
          }
        });
      }
    },
    
    // Get default WebSocket URL
    getDefaultUrl: function() {
      const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
      const host = window.location.host;
      return `${protocol}//${host}/cable`;
    },
    
    // Get connection statistics
    getStats: function() {
      const ws = this.getConnection();
      return {
        connected: this.isConnected(),
        readyState: ws ? ws.readyState : null,
        reconnectAttempts: this.reconnectAttempts,
        queuedMessages: this.messageQueue.length,
        url: ws ? ws.url : null
      };
    },
    
    // Enable/disable message queueing
    setQueueing: function(enabled) {
      this.queueEnabled = enabled;
      console.log(`[WebSocketManager] Message queueing ${enabled ? 'enabled' : 'disabled'}`);
    }
  };
  
  // === Override global ws variable ===
  
  let _ws = window.ws;
  Object.defineProperty(window, 'ws', {
    get: function() {
      return window.WebSocketManager.getConnection();
    },
    set: function(value) {
      _ws = value;
      if (value) {
        window.WebSocketManager.connection = value;
        window.WebSocketManager.setupEventHandlers(value);
        
        if (window.SessionState) {
          window.SessionState.setWebSocket(value);
        }
      }
    }
  });
  
  // === Override connect_websocket function ===
  
  const originalConnectWebsocket = window.connect_websocket;
  window.connect_websocket = function() {
    console.log('[WebSocketMigration] Intercepting connect_websocket');
    
    try {
      // Use WebSocketManager for centralized handling
      return window.WebSocketManager.connect();
    } catch (error) {
      // Fallback to original
      if (originalConnectWebsocket) {
        return originalConnectWebsocket();
      }
      throw error;
    }
  };
  
  // === Override reconnect_websocket function ===
  
  const originalReconnectWebsocket = window.reconnect_websocket;
  window.reconnect_websocket = function(ws, callback) {
    console.log('[WebSocketMigration] Intercepting reconnect_websocket');
    
    try {
      // If callback provided, use original behavior but track connection
      if (originalReconnectWebsocket && callback) {
        originalReconnectWebsocket(ws, function(newWs) {
          window.WebSocketManager.connection = newWs;
          window.WebSocketManager.setupEventHandlers(newWs);
          
          if (window.SessionState) {
            window.SessionState.setWebSocket(newWs);
          }
          
          callback(newWs);
        });
      } else {
        // Use WebSocketManager reconnect
        window.WebSocketManager.reconnect(true);
      }
    } catch (error) {
      // Fallback to original
      if (originalReconnectWebsocket) {
        originalReconnectWebsocket(ws, callback);
      } else {
        throw error;
      }
    }
  };
  
  // === Integration with SessionState ===
  
  if (window.SessionState) {
    // Listen for connection events
    window.WebSocketManager.on('connected', function() {
      window.SessionState.notifyListeners('websocket:connected');
    });
    
    window.WebSocketManager.on('disconnected', function() {
      window.SessionState.notifyListeners('websocket:disconnected');
    });
    
    window.WebSocketManager.on('message:received', function(event) {
      window.SessionState.notifyListeners('websocket:message', event.data);
    });
  }
  
  // === Migration Status ===
  
  window.WebSocketMigration = {
    status: 'active',
    
    // Get migration statistics
    getStats: function() {
      return {
        enabled: window.MigrationConfig.features.websocket,
        managerActive: !!window.WebSocketManager,
        connectionStats: window.WebSocketManager ? window.WebSocketManager.getStats() : null,
        usingSessionState: !!(window.SessionState && window.SessionState.connection)
      };
    },
    
    // Test WebSocket operations
    testOperations: function() {
      console.group('[WebSocketMigration] Testing operations');
      
      const results = {};
      
      try {
        // Test getting connection
        results.getConnection = !!window.WebSocketManager.getConnection();
        
        // Test connection status
        results.isConnected = typeof window.WebSocketManager.isConnected() === 'boolean';
        
        // Test stats
        const stats = window.WebSocketManager.getStats();
        results.getStats = stats && typeof stats.connected === 'boolean';
        
        // Test send (dry run)
        if (window.WebSocketManager.isConnected()) {
          results.send = window.WebSocketManager.send({ type: 'test', dryRun: true });
        }
        
      } catch (error) {
        console.error('[WebSocketMigration] Test error:', error);
      }
      
      console.table(results);
      console.groupEnd();
      
      return results;
    }
  };
  
  console.log('[WebSocketMigration] WebSocket state migration complete');
  console.log('[WebSocketMigration] Stats:', window.WebSocketMigration.getStats());
  
})();