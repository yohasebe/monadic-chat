# Frontend Architecture

This guide explains the JavaScript frontend architecture of Monadic Chat, particularly the centralized state management system.

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
    forceNew: false,    // Flag to force new session
    justReset: false    // Just reset flag
  },

  // Conversation messages and state
  conversation: {
    messages: [],           // Array of message objects
    currentQuery: null,     // Current user input
    isStreaming: false,     // Whether streaming response
    responseStarted: false, // Whether response has started
    callingFunction: false  // Whether calling function
  },

  // Application settings
  app: {
    current: null,      // Current app name
    params: {},         // App parameters
    originalParams: {}, // Original parameters
    model: null,        // Selected model
    modelOptions: []    // Available models
  },

  // UI state
  ui: {
    autoScroll: true,      // Auto scroll enabled
    isLoading: false,      // Loading state
    configVisible: true,   // Config panel visible
    mainPanelVisible: false // Main panel visible
  },

  // Audio playback state
  audio: {
    queue: [],              // Audio segment queue
    isPlaying: false,       // Currently playing
    currentSegment: null,   // Current audio segment
    enabled: false          // Audio enabled
  },

  // WebSocket connection (read-only reference)
  connection: {
    ws: null,              // WebSocket instance
    reconnectDelay: 1000,  // Reconnect delay
    pingInterval: null,    // Ping interval ID
    isConnected: false     // Connection state
  }
}
```

### Key Methods

#### Message Management

```javascript
// Add message to conversation
SessionState.addMessage({
  role: 'user',
  content: 'Hello',
  mid: 'unique-id'
});

// Remove message by index
SessionState.removeMessage(0);

// Clear all messages
SessionState.clearMessages();

// Update last message
SessionState.updateLastMessage('Updated content');

// Get all messages (returns copy)
const messages = SessionState.getMessages();
```

#### Session Management

```javascript
// Start new session
SessionState.startNewSession();

// Reset current session
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

SessionState has a built-in event system for reactive updates:

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

- `message:added` - New message was added
- `message:updated` - Message content was updated
- `message:deleted` - Message was deleted
- `messages:cleared` - All messages were cleared
- `session:new` - New session started
- `session:reset` - Session was reset
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

// Manual restore (occurs on load)
SessionState.restore();

// Validate state consistency
const isValid = SessionState.validateState();

// Get state snapshot for debugging
const snapshot = SessionState.getStateSnapshot();
```

### Safe Operations

Use safe wrapper functions for error-prone operations:

```javascript
// Safe operations return true/false instead of throwing errors
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

1. **Save Original Function**: Store original function before patching
2. **Override Function**: New implementation replaces original
3. **Extend Functionality**: Patches add features while preserving core behavior

### Example: Web Search Patch

```javascript
// Save original function
if (typeof window.originalDoResetActions === 'undefined') {
  window.originalDoResetActions = doResetActions;
}

// Override with extended version
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
- `utilities_websearch_patch.js` - Web search extensions
- `websocket.js` - WebSocket communication

## Internationalization (i18n) System

### Architecture

The i18n system provides multilingual support for the Web UI using a Promise-based initialization system.

#### Core Components

1. **WebUIi18n Class** (`public/js/i18n/translations.js`)
   - Manages translations for 5 languages (English, Japanese, Chinese, Korean, Spanish)
   - Provides Promise-based initialization
   - Handles dynamic UI updates

2. **Translation Structure**
   ```javascript
   {
     en: { ui: { messages: { readyForInput: "Ready for input" } } },
     ja: { ui: { messages: { readyForInput: "入力可能" } } },
     // ... other languages
   }
   ```

3. **Declarative Translations**
   ```html
   <!-- Text content -->
   <div data-i18n="ui.resetDescription">Pressing reset will...</div>

   <!-- Title attribute -->
   <button data-i18n-title="ui.cancel">Cancel</button>

   <!-- Placeholder -->
   <input data-i18n-placeholder="ui.messagePlaceholder" />
   ```

### Promise-Based Initialization

```javascript
// Global Promise for i18n readiness
window.i18nReady = webUIi18n.ready();

// Wait for initialization
window.i18nReady.then(() => {
  const text = webUIi18n.t('ui.messages.readyForInput');
  $("#status").text(text);
});

// Safe translation helper (works before initialization)
const text = safeTranslate('ui.messages.readyForInput', 'Ready for input');
```

### State Management for Streaming

The system tracks streaming response state to maintain proper UI feedback:

```javascript
// Streaming state flags
let responseStarted = false;    // Response has started
let streamingResponse = false;  // Currently streaming
let callingFunction = false;    // Calling function

// Spinner display logic
if (!callingFunction && !streamingResponse) {
  $("#monadic-spinner").hide();
}
```

### Language Separation

- **UI Language**: Controls interface elements (menus, buttons, status messages)
- **Conversation Language**: Controls AI response language and text direction
- Both can be set independently for maximum flexibility

## Best Practices

### 1. Always Use SessionState Methods

```javascript
// Good - use SessionState methods
SessionState.addMessage(message);

// Avoid - direct array manipulation
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
// Enable verbose state change logging
window.DEBUG_STATE_CHANGES = true;
```

### Inspect Current State

```javascript
// Get full state snapshot
const state = SessionState.getStateSnapshot();
console.log('Current state:', state);

// Validate state consistency
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

SessionState is tested using the actual implementation without mocks:

- Test file: `test/frontend/session-state.test.js`
- Uses `eval()` to use actual SessionState code
- Tests with real localStorage
- Validates actual behavior, not mocked responses

## Global Variable Compatibility

SessionState provides global variable proxies for compatibility:

```javascript
// Global variables are proxied to SessionState
messages.push(message);  // Proxied to SessionState.addMessage()
forceNewSession = true;  // Proxied to SessionState.session.forceNew
```

New code should use SessionState methods directly for type safety and clarity.

## Summary

The SessionState system provides:
- **Centralized state management** - All state in one place
- **Event-driven updates** - Components react to changes
- **Built-in persistence** - Automatic localStorage sync
- **Error handling** - Safe wrapper functions
- **Debugging tools** - State snapshots and validation
- **Global variable compatibility** - Seamless integration with existing code

This architecture makes the frontend maintainable, debuggable, and extensible.
