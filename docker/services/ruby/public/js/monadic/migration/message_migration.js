// Message Management Migration
// This file contains the migrated message management functions using SessionState

(function() {
  'use strict';
  
  // Enable migration based on environment or flag
  const ENABLE_MESSAGE_MIGRATION = window.location.hostname === 'localhost' || 
                                   window.ENABLE_STATE_MIGRATION || 
                                   false;
  
  if (!ENABLE_MESSAGE_MIGRATION) {
    console.log('[Migration] Message migration not enabled');
    return;
  }
  
  console.log('[Migration] Starting message management migration');
  
  // Store original references
  const originalMessages = window.messages || [];
  
  // === Migrated Functions ===
  
  // Replace direct messages array access with SessionState
  Object.defineProperty(window, 'messages', {
    get: function() {
      // Return messages from SessionState if available
      if (window.SessionState && window.SessionState.conversation) {
        return window.SessionState.conversation.messages;
      }
      return originalMessages;
    },
    set: function(value) {
      // Update both for compatibility during migration
      if (window.SessionState && window.SessionState.conversation) {
        window.SessionState.conversation.messages = value;
        // Notify listeners of change
        if (value.length === 0) {
          window.SessionState.notifyListeners('messages:cleared');
        }
      }
      // Keep original array in sync during migration
      originalMessages.length = 0;
      originalMessages.push(...value);
    }
  });
  
  // === Enhanced Message Operations ===
  
  window.MessageManager = {
    // Add a message with validation and events
    addMessage: function(message) {
      if (!message || typeof message !== 'object') {
        console.error('[MessageManager] Invalid message:', message);
        return null;
      }
      
      // Ensure message has required fields
      if (!message.role) {
        console.warn('[MessageManager] Message missing role:', message);
      }
      
      // Add message ID if not present
      if (!message.mid) {
        message.mid = 'msg_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
      }
      
      // Add timestamp if not present
      if (!message.timestamp) {
        message.timestamp = new Date().toISOString();
      }
      
      // Use SessionState if available
      if (window.SessionState && window.SessionState.addMessage) {
        return window.SessionState.addMessage(message);
      } else {
        // Fallback to direct array manipulation
        window.messages.push(message);
        return message;
      }
    },
    
    // Clear all messages
    clearMessages: function() {
      if (window.SessionState && window.SessionState.clearMessages) {
        window.SessionState.clearMessages();
      } else {
        window.messages = [];
      }
      
      // Clear UI
      $("#discourse").empty();
      
      // Update stats
      if (typeof setStats === 'function' && typeof formatInfo === 'function') {
        setStats(formatInfo([]), "info");
      }
      
      // Update start button label
      $("#start-label").text("Start Session");
    },
    
    // Get messages safely
    getMessages: function() {
      if (window.SessionState && window.SessionState.getMessages) {
        return window.SessionState.getMessages();
      }
      return window.messages || [];
    },
    
    // Get message count
    getMessageCount: function() {
      return this.getMessages().length;
    },
    
    // Find message by ID
    findMessage: function(mid) {
      const messages = this.getMessages();
      return messages.find(m => m.mid === mid);
    },
    
    // Find message index by ID
    findMessageIndex: function(mid) {
      const messages = this.getMessages();
      return messages.findIndex(m => m.mid === mid);
    },
    
    // Update message by ID
    updateMessage: function(mid, updates) {
      const index = this.findMessageIndex(mid);
      if (index !== -1) {
        const messages = this.getMessages();
        Object.assign(messages[index], updates);
        
        // Notify listeners if using SessionState
        if (window.SessionState && window.SessionState.notifyListeners) {
          window.SessionState.notifyListeners('message:updated', {
            index: index,
            message: messages[index]
          });
        }
        
        return messages[index];
      }
      return null;
    },
    
    // Delete message by ID
    deleteMessage: function(mid) {
      const index = this.findMessageIndex(mid);
      if (index !== -1) {
        if (window.SessionState && window.SessionState.deleteMessage) {
          return window.SessionState.deleteMessage(index);
        } else {
          const messages = this.getMessages();
          return messages.splice(index, 1)[0];
        }
      }
      return null;
    },
    
    // Check if conversation has started
    hasConversation: function() {
      return this.getMessageCount() >= 2;
    },
    
    // Get last message
    getLastMessage: function() {
      const messages = this.getMessages();
      return messages.length > 0 ? messages[messages.length - 1] : null;
    },
    
    // Get messages by role
    getMessagesByRole: function(role) {
      return this.getMessages().filter(m => m.role === role);
    },
    
    // Remove temporary messages
    removeTempMessages: function() {
      const messages = this.getMessages();
      const tempMessages = messages.filter(m => m.temp === true);
      tempMessages.forEach(m => this.deleteMessage(m.mid));
      return tempMessages.length;
    }
  };
  
  // === Event Listeners for State Changes ===
  
  if (window.SessionState) {
    // Listen for message additions
    window.SessionState.on('message:added', function(message) {
      console.log('[Migration] Message added:', message.role, message.mid);
      
      // Update UI if needed
      if (message.role === 'user' || message.role === 'assistant') {
        // Update start button label
        $("#start-label").text("Continue Session");
        
        // Enable AI User button if appropriate
        updateAIUserButton();
      }
    });
    
    // Listen for messages cleared
    window.SessionState.on('messages:cleared', function() {
      console.log('[Migration] Messages cleared');
      
      // Update start button label
      $("#start-label").text("Start Session");
      
      // Disable AI User button
      $("#ai_user").prop("disabled", true);
    });
    
    // Listen for session reset
    window.SessionState.on('session:reset', function() {
      console.log('[Migration] Session reset');
      
      // Clear UI
      $("#discourse").empty();
      
      // Reset stats
      if (typeof setStats === 'function' && typeof formatInfo === 'function') {
        setStats(formatInfo([]), "info");
      }
    });
  }
  
  // === Helper Functions ===
  
  function updateAIUserButton() {
    // AI User should only be enabled if there are at least 2 messages
    const hasConversation = window.MessageManager.hasConversation();
    $("#ai_user").prop("disabled", !hasConversation);
    
    if (hasConversation) {
      $("#ai_user").attr("title", "Generate AI user response based on conversation");
    } else {
      $("#ai_user").attr("title", "Start a conversation first");
    }
  }
  
  // === Migration Patches ===
  
  // Patch Array.push for messages array to use our manager
  const originalPush = Array.prototype.push;
  let isAddingMessage = false; // Prevent recursion
  
  Array.prototype.push = function(...args) {
    // Check if this is the messages array and we're not already adding
    if (this === window.messages && window.MessageManager && !isAddingMessage) {
      // Prevent recursion
      isAddingMessage = true;
      
      // Use original push to actually add to array
      const result = originalPush.apply(this, args);
      
      // Notify SessionState about the change (without re-adding)
      if (window.SessionState) {
        args.forEach(item => {
          window.SessionState.notifyListeners('message:added', item);
        });
      }
      
      isAddingMessage = false;
      return result;
    }
    // Use original push for other arrays or when already adding
    return originalPush.apply(this, args);
  };
  
  // === Migration Status ===
  
  window.MessageMigration = {
    status: 'active',
    
    // Get migration statistics
    getStats: function() {
      return {
        enabled: ENABLE_MESSAGE_MIGRATION,
        messageCount: window.MessageManager.getMessageCount(),
        usingSessionState: !!(window.SessionState && window.SessionState.conversation),
        listeners: window.SessionState ? window.SessionState.listeners.size : 0
      };
    },
    
    // Test migration consistency
    testConsistency: function() {
      const directMessages = window.messages;
      const sessionMessages = window.SessionState ? window.SessionState.conversation.messages : [];
      const managerMessages = window.MessageManager.getMessages();
      
      const directCount = directMessages ? directMessages.length : 0;
      const sessionCount = sessionMessages.length;
      const managerCount = managerMessages.length;
      
      const consistent = directCount === sessionCount && sessionCount === managerCount;
      
      return {
        consistent: consistent,
        counts: {
          direct: directCount,
          session: sessionCount,
          manager: managerCount
        },
        details: {
          directMessages: directMessages,
          sessionMessages: sessionMessages,
          managerMessages: managerMessages
        }
      };
    },
    
    // Enable/disable migration
    setEnabled: function(enabled) {
      if (enabled) {
        console.log('[Migration] Message migration enabled');
        window.ENABLE_STATE_MIGRATION = true;
      } else {
        console.log('[Migration] Message migration disabled');
        window.ENABLE_STATE_MIGRATION = false;
      }
    }
  };
  
  console.log('[Migration] Message management migration complete');
  console.log('[Migration] Stats:', window.MessageMigration.getStats());
  
})();