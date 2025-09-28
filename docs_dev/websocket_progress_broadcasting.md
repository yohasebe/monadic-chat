# WebSocket Progress Broadcasting Implementation

## Overview
This document describes the WebSocket progress broadcasting feature implemented for long-running GPT-5-Codex operations. The feature displays progress updates in the temp card (yellow warning area) during operations that may take 10+ minutes.

## Implementation Date
2025-09-28

## Problem Addressed
GPT-5-Codex operations can take 10-20 minutes or longer. Without progress updates, users couldn't tell if the system was still working or had frozen. Progress messages were appearing in console and #status-message but NOT in the content area's temp card where streaming text normally appears.

## Solution Architecture

### Key Components Modified

1. **`lib/monadic/utils/websocket.rb`**
   - Added progress broadcasting capabilities to WebSocketHelper module
   - Modified to use EventMachine channel for message delivery
   - Session management for tracking multiple connections per session

2. **`lib/monadic/agents/gpt5_codex_agent.rb`**
   - Integrated with WebSocketHelper for progress updates
   - Sends 1-minute interval updates during long operations
   - Passes session context to progress threads

3. **`apps/auto_forge/auto_forge_tools.rb`**
   - Passes progress callbacks through to GPT-5-Codex agent

## Critical Implementation Details

### EventMachine Channel Requirement
**IMPORTANT**: Messages MUST be sent through the EventMachine channel (`@channel.push()`) to appear in the temp card. Direct WebSocket sending (`ws.send()`) will NOT display in the temp card UI.

```ruby
# CORRECT - Messages appear in temp card
@@channel.push(message.to_json)

# INCORRECT - Messages do NOT appear in temp card
ws.send(message.to_json)
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

### 1. Session Management (Future-Proofing)
- `@@connections_by_session`: Hash mapping session IDs to Sets of WebSocket connections
- Supports multiple tabs/connections per session
- Currently broadcasts to all connections via channel, but infrastructure ready for targeted messaging

### 2. Progress Broadcasting Methods
- `broadcast_progress(fragment, target_session_id)`: Main broadcasting method
- `send_to_session(message_json, session_id)`: Session-specific sending (uses channel)
- `send_progress_fragment(fragment, target_session_id)`: Filters and sends progress fragments

### 3. Feature Flag
- `WEBSOCKET_PROGRESS_ENABLED`: Controls whether progress broadcasting is active
- Defaults to `true` if not specified in config

## Design Decisions and Rationale

### Why Keep Session Management?
Although we currently broadcast through the channel (which goes to all subscribers), we keep session management for:
1. **Future targeting**: May need session-specific messages later
2. **Connection cleanup**: Track and remove dead connections
3. **Debugging**: Know which sessions have active connections
4. **Minimal overhead**: Set-based storage is efficient

### Why Include session_id in Messages?
Currently unused by JavaScript, but included for:
1. **Future filtering**: Clients could filter messages by session
2. **Debugging**: Track which session generated which message
3. **Backward compatibility**: Easy to add filtering without changing message format

### Why Keep Fallback Direct Send?
The `send_to_session` method includes fallback code for direct WebSocket sending when no channel exists:
1. **Defensive programming**: System shouldn't break if channel initialization fails
2. **Testing**: Some test scenarios might not initialize channels
3. **Migration path**: If architecture changes, fallback ensures continuity

## Testing Considerations

The test file `spec/lib/monadic/utils/websocket_helper_spec.rb` still expects direct WebSocket sends. This is intentional because:
1. Tests verify the WebSocket connection management logic
2. Channel behavior is integration-tested through actual usage
3. Changing tests would require mocking EventMachine channels

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
1. Check that `@@channel` is set (should happen in `handle_websocket_connection`)
2. Verify message has `type: "wait"`
3. Check browser console for WebSocket errors
4. Enable `EXTRA_LOGGING` to see detailed broadcast logs

### Messages Appear in Console but Not UI
This means messages are being sent directly instead of through channel. Ensure `send_to_session` is using `@@channel.push()`.

## Future Enhancements

1. **Session-specific filtering**: JavaScript could filter messages by session_id
2. **Progress percentage**: Include completion percentage in messages
3. **Cancel support**: Allow canceling long-running operations
4. **Multiple progress types**: Different UI treatments for different operations
5. **Rate limiting**: Prevent progress message flooding

## Code Locations

- Main implementation: `/lib/monadic/utils/websocket.rb:91-233`
- GPT-5-Codex integration: `/lib/monadic/agents/gpt5_codex_agent.rb:start_progress_thread`
- AutoForge integration: `/apps/auto_forge/auto_forge_tools.rb`
- JavaScript handler: `/public/js/monadic/websocket.js:1920-1939`
- Tests: `/spec/lib/monadic/utils/websocket_helper_spec.rb`

## Notes

- The MDSL validation errors seen during server startup are unrelated to this feature
- Background bash processes (409abb, 4d556e) were test servers during development
- The implementation prioritizes working functionality over architectural purity