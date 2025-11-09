# Tab Isolation Architecture

## Overview

Monadic Chat implements complete tab isolation, allowing users to maintain independent conversations and app states across multiple browser tabs. Each tab operates as a separate session with its own message history, parameters, and context.

## Key Components

### 1. Tab Identifier (`tab_id`)

**Generation**:
- Unique UUID generated per browser tab
- Created by `ensureMonadicTabId()` on page load
- Stored in `sessionStorage` (tab-specific, survives page refresh)

**Lifecycle**:
- Created: When tab opens or page loads
- Persists: Through page refreshes within same tab
- Destroyed: When tab closes (sessionStorage is cleared)

**Implementation**:
```javascript
// monadic/websocket.js (line ~559)
function ensureMonadicTabId() {
  let tabId = sessionStorage.getItem('monadic_tab_id');
  if (!tabId) {
    tabId = generateUUID();
    sessionStorage.setItem('monadic_tab_id', tabId);
  }
  window.monadicTabId = tabId;
  return tabId;
}
```

### 2. WebSocket Connection

**URL Format**:
```
ws://localhost:4567/?tab_id={UUID}
```

**Connection Flow**:
1. Page loads → `ensureMonadicTabId()` generates/retrieves `tab_id`
2. WebSocket connection established with `tab_id` as query parameter
3. Server extracts `tab_id` and uses it as session identifier

**Critical Timing**:
- WebSocket initialization MUST occur AFTER `ensureMonadicTabId()` is defined
- Originally initialized at module load (line 18) → caused `tab_id` to be undefined
- Fixed by moving initialization to end of file (line ~6286) after function definition

**Implementation**:
```javascript
// monadic/websocket.js
let ws;  // Declaration only at top of file

// ... rest of file ...

// Initialization at end of file (after ensureMonadicTabId is defined)
ws = connect_websocket();
window.ws = ws;
```

### 3. Server-Side Session Management

**Session Storage**:
```ruby
# lib/monadic/utils/websocket.rb
module WebSocketHelper
  @@session_state = {}  # Hash keyed by tab_id/session_id
end
```

**Session Structure**:
```ruby
@@session_state[ws_session_id] = {
  messages: [...],      # Array of message objects
  parameters: {...}     # App parameters hash
}
```

**Initialization Flow**:
```ruby
# 1. Extract tab_id from WebSocket query parameters
tab_id = Rack::Utils.parse_query(query_string)['tab_id']

# 2. Use tab_id as session ID (or generate fallback)
ws_session_id = tab_id || generate_session_id()

# 3. Always initialize empty session first (clear Rack session)
session[:messages] = []
session[:parameters] = {}

# 4. Restore saved state if exists (for page refresh)
if (saved_state = WebSocketHelper.fetch_session_state(ws_session_id))
  session[:messages] = saved_state[:messages]
  session[:parameters] = saved_state[:parameters]
end
```

### 4. Rack Session vs Session State

**Two Session Mechanisms**:

1. **Rack Session** (Cookie-based):
   - Shared across all tabs (same browser)
   - Used for temporary connection state
   - Always cleared on WebSocket connection

2. **`@@session_state` Hash** (Server-side):
   - Keyed by `tab_id`
   - Independent per tab
   - Persists across reconnections
   - Source of truth for session data

**Why Both?**:
- Rack session: Required by Rack middleware, used during single request/response
- `@@session_state`: Persistent storage across WebSocket reconnections

### 5. Session Persistence

**Page Refresh Flow**:
```
1. User refreshes tab
2. sessionStorage preserves tab_id
3. New WebSocket connects with same tab_id
4. Server finds saved_state for tab_id
5. Session (messages + parameters) restored
6. User sees "Continue Session" option
```

**Implementation**:
```ruby
# Save state on every message/parameter update
def sync_session_state!
  session_id = Thread.current[:websocket_session_id]
  WebSocketHelper.update_session_state(
    session_id,
    messages: session[:messages] || [],
    parameters: get_session_params || {}
  )
end
```

## Key Design Decisions

### 1. sessionStorage vs localStorage

**Choice**: `sessionStorage`

**Rationale**:
- Tab-specific (not shared across tabs)
- Survives page refresh
- Cleared when tab closes
- Perfect match for tab isolation requirements

**Alternative Rejected**: `localStorage`
- Shared across all tabs
- Would require complex tab tracking
- Doesn't match natural tab lifecycle

### 2. tab_id as Session Identifier

**Choice**: Use `tab_id` directly as `ws_session_id`

**Rationale**:
- Simple 1:1 mapping
- No lookup table needed
- Tab controls its own session
- Natural cleanup when tab closes

**Alternative**: Generate separate session ID
- Requires mapping table
- More complex state management
- No clear benefit

### 3. Always Initialize Empty Session

**Choice**: Clear `session[:messages]` and `session[:parameters]` on every connection

**Rationale**:
- Rack session is shared across tabs (cookie-based)
- Without clearing, new tab inherits old tab's data
- Forces explicit restoration from `@@session_state`
- Ensures tab isolation

**Code**:
```ruby
# Always clear first (prevent cross-tab contamination)
session[:messages] = []
session[:parameters] = {}

# Then restore saved state (if exists)
if (saved_state = WebSocketHelper.fetch_session_state(ws_session_id))
  session[:messages] = saved_state[:messages]
  session[:parameters] = saved_state[:parameters]
end
```

### 4. Parameters Broadcast Strategy

**Choice**: Always send parameters message, even if empty

**Rationale**:
- Client-side localStorage may have stale parameters
- Sending empty `{}` clears client cache
- Prevents parameter bleeding between apps/tabs
- Explicit state sync

**Original Bug**:
```ruby
# Bad: Only send if non-empty
if session[:parameters] && !session[:parameters].empty?
  send_parameters(session[:parameters])
end
```

**Fixed**:
```ruby
# Good: Always send (even if empty)
send_parameters(session[:parameters] || {})
```

## Common Pitfalls

### 1. WebSocket Timing Race

**Problem**: WebSocket connects before `ensureMonadicTabId()` is defined

**Symptom**: `ws.url` shows `ws://localhost:4567/` without `tab_id`

**Solution**: Move WebSocket initialization to end of file

**Detection**:
```javascript
console.log(window.ws.url);
// Bad: ws://localhost:4567/
// Good: ws://localhost:4567/?tab_id=xxx-xxx-xxx
```

### 2. Rack Session Contamination

**Problem**: Rack session is shared across tabs, causing data bleed

**Symptom**: New tab shows messages from other tab

**Solution**: Always clear `session[:messages]` and `session[:parameters]` on connect

### 3. localStorage Pollution

**Problem**: Using `localStorage` for tab-specific data

**Symptom**: All tabs share same state

**Solution**: Use `sessionStorage` for tab-specific data

### 4. Missing Parameters Broadcast

**Problem**: Not sending parameters when empty

**Symptom**: Client keeps old parameters in localStorage

**Solution**: Always send parameters message (even if `{}`)

## Testing Tab Isolation

### Manual Test Procedure

1. **Open Tab A**: Select "Chat" app, send message "Hello from A"
2. **Open Tab B**: Should show fresh UI (no messages)
3. **Select Different App**: Choose "Mermaid Grapher" in Tab B
4. **Check Tab A**: Should still show "Chat" with "Hello from A"
5. **Refresh Tab A**: Should restore "Chat" with "Hello from A" (Continue Session)
6. **Refresh Tab B**: Should restore "Mermaid Grapher" with empty session
7. **Close Tab A**: Should not affect Tab B
8. **Check Console**: All WebSocket URLs should include `?tab_id=...`

### Automated Testing

**Implementation**: `spec/integration/websocket_tab_isolation_spec.rb`

The tab isolation feature is tested through 13 comprehensive integration tests that verify:

1. **Session State Isolation**: Different tab_ids maintain separate sessions
2. **Session Restoration**: Same tab_id restores previous session on reconnection
3. **Tab ID Changes**: New tab_id creates independent session
4. **Deep Cloning**: Fetched session data doesn't affect other tabs
5. **Thread Safety**: Concurrent access from multiple threads
6. **App Switching**: Messages preserved when switching apps within same tab
7. **Edge Cases**: Nil handling, empty sessions, etc.

**Test Results**: All 13 tests passing (0.01s duration)

**Key Testing Approach**:
```ruby
# Tests the core session state management directly
WebSocketHelper.update_session_state(tab_id, messages:, parameters:)
state = WebSocketHelper.fetch_session_state(tab_id)
expect(state[:messages]).to eq(expected_messages)
```

**Note**: Tests focus on the `@@session_state` hash mechanism rather than full WebSocket connections, ensuring fast and reliable unit-style integration tests.

## Debugging Tab Isolation Issues

### Check WebSocket URL

```javascript
// In browser console
console.log(window.ws.url);
// Expected: ws://localhost:4567/?tab_id=xxx-xxx-xxx
// If missing tab_id, WebSocket initialized too early
```

### Check tab_id in sessionStorage

```javascript
// In browser console
console.log(sessionStorage.getItem('monadic_tab_id'));
// Should return a UUID
```

### Check Server Logs (EXTRA_LOGGING=true)

```bash
# ~/monadic/log/extra.log
[WebSocket] Session initialized: xxx-xxx-xxx (tab_id: yyy-yyy-yyy)
[WebSocket] Session state: restored (xxx-xxx-xxx)
```

### Verify Session Independence

```bash
# In extra.log, check that different tabs have different session IDs
[WebSocket] Session initialized: aaa-aaa-aaa (tab_id: aaa-aaa-aaa)  # Tab 1
[WebSocket] Session initialized: bbb-bbb-bbb (tab_id: bbb-bbb-bbb)  # Tab 2
```

## Future Improvements

1. **Session Cleanup**: Implement timeout-based cleanup for abandoned sessions
2. **Session Metrics**: Track number of active sessions, average lifetime
3. **Session Limits**: Prevent unlimited session accumulation
4. **Cross-Tab Communication**: Optional feature for users to merge/share sessions
5. **Session Export/Import**: Allow users to save/restore specific tab sessions

## Related Documentation

- **Client-Side Rendering**: `docs_dev/frontend/client_side_rendering.md`
- **WebSocket Architecture**: `docs_dev/ruby_service/websocket_architecture.md` (if exists)
- **Session State Management**: Frontend session state handling

## Changelog

- **2025-01-09**: Initial tab isolation implementation
  - Added `tab_id` generation and WebSocket parameter passing
  - Implemented server-side session isolation
  - Fixed WebSocket timing race condition
  - Added session persistence on page refresh
