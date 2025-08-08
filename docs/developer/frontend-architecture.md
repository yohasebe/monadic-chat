# Frontend Architecture

This guide explains the JavaScript frontend architecture of Monadic Chat, focusing on the centralized state management system.

## Overview

Monadic Chat's frontend uses a centralized state management system called **SessionState** to manage all application state in a single, organized location.

## SessionState System

### Core Structure

SessionState is the single source of truth for all application state:

```javascript
window.SessionState = {
  // Core session information
  session: {
    id: null,           // Unique session identifier
    started: false,     // Whether session has started
    forceNew: false,    // Force new session flag
    justReset: false    // Just reset flag
  },
  
  // Conversation messages and state
  conversation: {
    messages: [],           // Array of message objects
    currentQuery: null,     // Current user input
    isStreaming: false,     // Whether streaming response
    responseStarted: false, // Response has begun
    callingFunction: false  // Function call in progress
  },
  
  // Application configuration
  app: {
    current: null,      // Current app name
    params: {},         // App parameters
    originalParams: {}, // Original parameters
    model: null,        // Selected model
    modelOptions: []    // Available models
  },
  
  // UI state
  ui: {
    autoScroll: true,      // Auto-scroll enabled
    isLoading: false,      // Loading state
    configVisible: true,   // Config panel visible
    mainPanelVisible: false // Main panel visible
  },
  
  // Audio playback state
  audio: {
    queue: [],              // Audio segments queue
    isPlaying: false,       // Currently playing
    currentSegment: null,   // Current audio segment
    enabled: false          // Audio enabled
  },
  
  // WebSocket connection (read-only reference)
  connection: {
    ws: null,              // WebSocket instance
    reconnectDelay: 1000,  // Reconnect delay
    pingInterval: null,    // Ping interval ID
    isConnected: false     // Connection status
  }
}
```

### Key Methods

#### Message Management

```javascript
// Add a message to the conversation
SessionState.addMessage({ 
  role: 'user', 
  content: 'Hello',
  mid: 'unique-id' 
});

// Remove a message by index
SessionState.removeMessage(0);

// Clear all messages
SessionState.clearMessages();

// Update the last message
SessionState.updateLastMessage('Updated content');

// Get all messages (returns a copy)
const messages = SessionState.getMessages();
```

#### Session Management

```javascript
// Start a new session
SessionState.startNewSession();

// Reset the current session
SessionState.resetSession();

// Set reset flags
SessionState.setResetFlags();

// Clear reset flags
SessionState.clearResetFlags();

// Check if should force new session
if (SessionState.shouldForceNewSession()) {
  // Handle new session
}
```

#### Application State

```javascript
// Set current app and parameters
SessionState.setCurrentApp('Chat', { 
  model: 'gpt-4',
  temperature: 0.7 
});

// Update app parameters
SessionState.updateAppParams({ 
  temperature: 0.9 
});

// Get current app
const app = SessionState.getCurrentApp();

// Get app parameters
const params = SessionState.getAppParams();
```

### Event System

SessionState includes a built-in event system for reactive updates:

```javascript
// Listen for events
SessionState.on('message:added', (message) => {
  console.log('New message:', message);
});

// One-time listener
SessionState.once('session:reset', () => {
  console.log('Session was reset');
});

// Remove listener
const handler = (data) => console.log(data);
SessionState.on('app:changed', handler);
SessionState.off('app:changed', handler);
```

#### Available Events

- `message:added` - New message added
- `message:updated` - Message content updated
- `message:deleted` - Message removed
- `messages:cleared` - All messages cleared
- `session:new` - New session started
- `session:reset` - Session reset
- `flags:reset` - Reset flags changed
- `app:changed` - App selection changed
- `app:params-updated` - App parameters updated
- `state:saved` - State saved to localStorage
- `state:restored` - State restored from localStorage

### State Persistence

SessionState automatically persists to localStorage:

```javascript
// Manual save (usually automatic)
SessionState.save();

// Manual restore (happens on load)
SessionState.restore();

// Validate state integrity
const isValid = SessionState.validateState();

// Get state snapshot for debugging
const snapshot = SessionState.getStateSnapshot();
```

### Safe Operations

For error-prone operations, use the safe wrapper functions:

```javascript
// Safe operations return true/false instead of throwing
if (safeSessionState.isAvailable()) {
  // SessionState is ready
  
  if (safeSessionState.addMessage(message)) {
    // Message added successfully
  }
  
  if (safeSessionState.clearMessages()) {
    // Messages cleared successfully
  }
}
```

## JavaScript Patch System

Monadic Chat uses a patch system to extend functionality without modifying core files.

### How It Works

1. **Original Function Storage**: Original functions are saved before patching
2. **Function Override**: New implementation replaces the original
3. **Extended Functionality**: Patches add features while preserving core behavior

### Example: Web Search Patch

```javascript
// Store original function
if (typeof window.originalDoResetActions === 'undefined') {
  window.originalDoResetActions = doResetActions;
}

// Override with enhanced version
window.doResetActions = function() {
  // Call original functionality
  if (window.originalDoResetActions) {
    window.originalDoResetActions.call(this);
  }
  
  // Add new functionality
  window.SessionState.setResetFlags();
  // ... additional features
};
```

### Patch Files

- `utilities.js` - Core utility functions
- `utilities_websearch_patch.js` - Web search enhancements
- `websocket.js` - WebSocket communication

## Best Practices

### 1. Always Use SessionState Methods

```javascript
// Good - Using SessionState methods
SessionState.addMessage(message);

// Avoid - Direct array manipulation
messages.push(message);
```

### 2. Listen for State Changes

```javascript
// React to state changes instead of polling
SessionState.on('conversation:updated', updateUI);
```

### 3. Handle Errors Gracefully

```javascript
// Use safe wrappers for critical operations
if (!safeSessionState.addMessage(message)) {
  console.error('Failed to add message');
  // Handle error appropriately
}
```

### 4. Clean Up Event Listeners

```javascript
// Remove listeners when no longer needed
const handler = (data) => updateDisplay(data);
SessionState.on('message:added', handler);

// Later...
SessionState.off('message:added', handler);
```

## Debugging

### Enable Debug Logging

```javascript
// Enable detailed state change logging
window.DEBUG_STATE_CHANGES = true;
```

### Inspect Current State

```javascript
// Get full state snapshot
const state = SessionState.getStateSnapshot();
console.log('Current state:', state);

// Validate state integrity
if (!SessionState.validateState()) {
  console.warn('State validation failed');
}
```

### Monitor State Changes

```javascript
// Log all state changes
SessionState.on('*', (event, data) => {
  console.log(`[State Change] ${event}:`, data);
});
```

## Testing

SessionState is tested using real implementations without mocks:

- Test file: `test/frontend/session-state.test.js`
- Uses actual SessionState code via `eval()`
- Tests with real localStorage
- Verifies actual behavior, not mocked responses

## Global Variable Compatibility

SessionState provides global variable proxies for compatibility:

```javascript
// Global variables are proxied to SessionState
messages.push(message);  // Proxied to SessionState.addMessage()
forceNewSession = true;  // Proxied to SessionState.session.forceNew
```

New code should use SessionState methods directly for better type safety and clarity.

## Summary

The SessionState system provides:
- **Centralized state management** - All state in one place
- **Event-driven updates** - Components react to changes
- **Built-in persistence** - Automatic localStorage sync
- **Error handling** - Safe wrapper functions
- **Debugging tools** - State snapshots and validation
- **Global variable compatibility** - Seamless integration with existing code

This architecture makes the frontend maintainable, debuggable, and extensible.