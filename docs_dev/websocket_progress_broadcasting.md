# WebSocket Progress Broadcasting Implementation

## Overview
This document describes the WebSocket progress broadcasting feature implemented for long-running OpenAI Code operations. The feature displays progress updates in the temp card (yellow warning area) during operations that may take 10+ minutes.

## Implementation Date
2025-09-28

## Problem Addressed
OpenAI Code operations can take 10-20 minutes or longer. Without progress updates, users couldn't tell if the system was still working or had frozen. Progress messages were appearing in console and #status-message but NOT in the content area's temp card where streaming text normally appears.

## Solution Architecture

### Key Components Modified

1. **`lib/monadic/utils/websocket.rb`**
   - Added progress broadcasting capabilities to WebSocketHelper module
   - Uses WebSocket connection broadcast for message delivery
   - Session management for tracking multiple connections per session

2. **`lib/monadic/agents/openai_code_agent.rb`**
   - Integrated with WebSocketHelper for progress updates
   - Sends 1-minute interval updates during long operations
   - Passes session context to progress threads

3. **`apps/auto_forge/auto_forge_tools.rb`**
   - Passes progress callbacks through to OpenAI Code agent

## Critical Implementation Details

### WebSocket Broadcasting Requirement
**IMPORTANT**: Messages MUST be sent through WebSocketHelper broadcasting methods to reach all connected clients. Use `WebSocketHelper.broadcast_progress()` or `WebSocketHelper.broadcast_to_all()`.

```ruby
# CORRECT - Messages appear in temp card for all clients
WebSocketHelper.broadcast_progress(fragment, target_session_id)

# CORRECT - Broadcast to all connections
WebSocketHelper.broadcast_to_all(message.to_json)

# INCORRECT - Sends to only one connection
ws.write(message.to_json)
```

### Message Format
Progress messages must have this format to trigger the temp card display:
```json
{
  "type": "wait",
  "content": "Progress message text",
  "timestamp": 1234567890.123
}
```

The JavaScript frontend handles `type: "wait"` messages by calling `setAlert(content, "warning")` which displays them in the yellow temp card area.

## Features Added

### 1. Session Management Structure
- `@@connections_by_session`: Hash mapping session IDs to Sets of WebSocket connections
- Supports multiple tabs/connections per session
- Broadcast currently goes to all connections via the channel while preserving per-session tracking for targeted messaging

### 2. Progress Broadcasting Methods
- `broadcast_progress(fragment, target_session_id)`: Main broadcasting method
- `send_to_session(message_json, session_id)`: Session-specific sending (uses WebSocket connections)
- `broadcast_to_all(message)`: Broadcast to all active connections

### 3. Feature Flag
- `WEBSOCKET_PROGRESS_ENABLED`: Controls whether progress broadcasting is active
- Defaults to `true` if not specified in config

## Design Decisions and Rationale

### Why Keep Session Management?
Although broadcasting currently goes to all subscribers, maintaining session management:
1. **Enables targeted messaging** without additional architectural changes
2. **Supports connection cleanup** by tracking and removing dead connections
3. **Assists debugging** by exposing which sessions have active connections
4. **Adds minimal overhead** thanks to set-based storage

### Why Include session_id in Messages?
Currently unused by JavaScript, but included for:
1. **Client-side filtering**: Clients can filter messages by session
2. **Debugging**: Track which session generated which message
3. **Backward compatibility**: Easy to add filtering without changing message format

### Why Use Direct WebSocket Connections?
The `send_to_session` method sends directly to WebSocket connections:
1. **Simplicity**: No need for intermediate channels or message queues
2. **Performance**: Direct connection sending is faster
3. **Compatibility**: Works with Async::WebSocket architecture

## Testing Considerations

The test file `spec/lib/monadic/utils/websocket_helper_spec.rb` tests direct WebSocket connection management:
1. Tests verify the WebSocket connection tracking and broadcasting logic
2. Integration tests verify actual message delivery through WebSocket connections
3. Tests use mock WebSocket connections to verify broadcast behavior

## Configuration

Add to `~/monadic/config/env` to control:
```bash
# Enable/disable progress broadcasting (default: true)
WEBSOCKET_PROGRESS_ENABLED=true

# Enable detailed logging for debugging
EXTRA_LOGGING=true
```

## Troubleshooting

### Progress Not Appearing in Temp Card
1. Check that WebSocket connections are active in `@@ws_connections`
2. Verify message has `type: "wait"`
3. Check browser console for WebSocket errors
4. Enable `EXTRA_LOGGING` to see detailed broadcast logs

### Messages Appear in Console but Not UI
This means messages may not be reaching the WebSocket connection. Verify that `WebSocketHelper.broadcast_progress()` or `broadcast_to_all()` is being called correctly.

## Code Locations

- Main implementation: `docker/services/ruby/lib/monadic/utils/websocket.rb:91-269`
- OpenAI Code integration: `docker/services/ruby/lib/monadic/agents/openai_code_agent.rb:start_progress_thread`
- AutoForge integration: `docker/services/ruby/apps/auto_forge/auto_forge_tools.rb`
- JavaScript handler: `docker/services/ruby/public/js/monadic/websocket.js:2427-2557`
- Tests: `docker/services/ruby/spec/lib/monadic/utils/websocket_helper_spec.rb`

## Notes

- The MDSL validation errors seen during server startup are unrelated to this feature
- Background bash processes (409abb, 4d556e) were test servers during development
- The implementation prioritizes working functionality over architectural purity
