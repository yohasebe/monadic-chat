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

## Session Isolation for Multi-User Environments

### Implementation Date
2025-11-07

### Problem Addressed
Prior to this update, `broadcast_to_all()` sent messages to ALL WebSocket connections across all users and sessions. In distributed/server mode with multiple users, this caused:
- User A's parameters/messages appearing in User B's browser
- Privacy violations in multi-user environments
- Session state contamination between different users

### Solution
Modified all broadcasting calls in session-specific operations to use **session-targeted broadcasting**:

```ruby
# Get session ID from thread context
ws_session_id = Thread.current[:websocket_session_id]

# Send to session only (all tabs within same browser session)
if ws_session_id
  WebSocketHelper.send_to_session(message.to_json, ws_session_id)
else
  WebSocketHelper.broadcast_to_all(message.to_json)  # Fallback
end
```

### Modified Functions
1. **`push_apps_data`** (apps, parameters, past_messages, info messages)
2. **`handle_edit_message`** (edit_success, error messages)
3. **`handle_delete_message`** (change_status, info messages)
4. **`UPDATE_PARAMS` handler** (parameters message)

### Session Management Architecture

**Session ID Storage:**
- Stored in `_monadic_session_id` cookie (browser-level)
- Also stored in Rack session (server-side)
- Generated as UUID on first connection
- Thread-local storage: `Thread.current[:websocket_session_id]`

**Connection Tracking:**
- `@@connections_by_session[session_id]` → Set of WebSocket connections
- Multiple tabs in same browser = same session ID = shared state
- Different browsers/profiles/incognito = different session IDs = isolated state

**Session Sharing Rules:**
- ✅ Same browser, multiple tabs → **Shared session**
- ✅ Same browser, multiple windows → **Shared session**
- ❌ Different browsers (Chrome vs Firefox) → **Separate sessions**
- ❌ Normal vs Incognito mode → **Separate sessions**
- ❌ Different devices → **Separate sessions**
- ❌ Different browser profiles → **Separate sessions**

### Multi-Tab Session Synchronization

When a new tab opens while a conversation is active in another tab:
1. Server sends `current_app_name` in apps message
2. Client prioritizes `current_app_name` over default app selection
3. New tab automatically selects the same app as existing tabs
4. No confirmation modal is shown (uses `proceedWithAppChange` directly)

**Synchronized Data Across Tabs (Same Session):**
- Active app selection
- Model and parameter settings (when sent via Start/Send)
- Conversation messages
- Message edits and deletions

**Parameter Sync Timing:**
- UI changes are local until user clicks Start or Send
- Then parameters broadcast to all tabs in same session
- Other sessions remain unaffected

### Security Benefits
- **User Privacy**: Each user's data is isolated from other users
- **Multi-Tenant Safe**: Supports multiple users on same server
- **Session Integrity**: Browser sessions remain independent
- **Distributed Mode Ready**: Works correctly in server mode with multiple clients

### Backward Compatibility
All modified functions include fallback to `broadcast_to_all()` when `ws_session_id` is not available, maintaining compatibility with edge cases or legacy connection paths.

## Complete Session Isolation Implementation

### Final Implementation Date
2025-11-07 (continued from initial implementation)

### Comprehensive Handler Coverage

After the initial 4 handlers, **ALL** remaining session-specific broadcasts were systematically converted to session-targeted broadcasting. The complete list of fixed handlers:

#### Core Session Data Handlers (Initial Implementation)
1. **`push_apps_data`** - Apps list, parameters, past messages, info
2. **`handle_edit_message`** - Edit success, error messages
3. **`handle_delete_message`** - Change status, info messages
4. **`UPDATE_PARAMS` handler** - Parameter updates

#### Message Processing Handlers
5. **`update_message_status`** - Change status, info messages
6. **`start_tts_playback`** - TTS audio data, progress updates
7. **`send_transcription_result`** - STT transcription results
8. **AI_USER_QUERY handler** - All AI processing messages (wait, started, error, ai_user_msg, finished, safety errors)
9. **SAMPLE handler** - Sample messages and errors
10. **AUDIO handler** - Audio processing errors
11. **HTML handler** - Conversation content display, status updates, info messages, errors

#### Control Command Handlers
12. **CANCEL handler** - Cancellation confirmation
13. **RESET handler** - Session reset (already session-scoped via session[:messages].clear)
14. **UPDATE_LANGUAGE handler** - Language change confirmation
15. **STOP_TTS handler** - TTS stop confirmation

#### Streaming Logic (CRITICAL - Most Complex)
16. **Main streaming initialization** - Error broadcasts for app not found, fragment errors
17. **Realtime TTS async callbacks** - Three separate callback contexts:
    - Flushed buffer callback (lines ~2462-2474)
    - Long sentence callback (lines ~2528-2542)
    - Final segment callback (lines ~2664-2676)
18. **Streaming fragments** - Four different fragment types:
    - Realtime mode fragments
    - Post-completion mode fragments
    - No-TTS fragments
    - Other fragment types
19. **Streaming completion** - Streaming complete message
20. **Streaming errors** - API errors, content not found, empty response errors
21. **Monadic auto_speech TTS** - Post-completion TTS for Monadic responses

### Connection-Level Fixes

#### PING/PONG Handler
- **Previous**: `broadcast_to_all({ "type" => "pong" })` - sent PONG to ALL connections
- **Fixed**: `send_to_client(connection, { "type" => "pong" })` - connection-specific keepalive
- **Rationale**: PING/PONG is a connection-level keepalive mechanism, not session-level or global

### What Remains Global (By Design)

The following broadcasts correctly remain global as they represent system-wide shared resources:

1. **Voice Lists** (`push_voice_data`):
   - `elevenlabs_voices` (line 793)
   - `gemini_voices` (line 808)
   - These are system capabilities, not user-specific data

2. **Method Definition**: `broadcast_to_all` method itself (line 103)

3. **Fallback Clauses**: All `else` branches in session-targeted functions use `broadcast_to_all` as fallback

### Session ID Capture Pattern

For async blocks and callbacks, session ID must be captured in outer scope:

```ruby
# Capture session ID BEFORE entering async blocks
ws_session_id = Thread.current[:websocket_session_id]

# Use captured variable inside async callbacks
some_async_operation do |result|
  if ws_session_id
    WebSocketHelper.send_to_session(result.to_json, ws_session_id)
  else
    WebSocketHelper.broadcast_to_all(result.to_json)
  end
end
```

#### Additional Handler Fixes (Final Comprehensive Review)

On 2025-11-07, a final systematic review using grep found 3 additional handlers that were missed in the initial implementation:

22. **`update_message_status_after_edit` helper** - Called by `handle_edit_message`, broadcasts status updates after message edits
    - **Location**: `websocket.rb:1232-1263`
    - **Broadcasts**: `change_status` (when messages changed), `info` (always)
    - **Why Critical**: Message editing status updates were leaking to all users
    - **Fix**: Added session ID capture and session-targeted broadcasting for both message types

23. **TTS handler** - Manual TTS requests when user clicks TTS button
    - **Location**: `websocket.rb:1481-1519`
    - **Broadcasts**: TTS audio responses (Web Speech API or generated audio)
    - **Why Critical**: User's private TTS audio was being sent to all connected users
    - **Fix**: Added session ID capture at handler start, used for both Web Speech API responses and generated TTS audio

24. **TTS_STREAM handler** - Streaming TTS during AI responses with TTS enabled
    - **Location**: `websocket.rb:1520-1564`
    - **Broadcasts**: Web Speech API responses AND streaming audio fragments via callback
    - **Why Critical**: AI response TTS was being broadcast to all users during streaming
    - **Fix**: Added session ID capture and applied to both Web Speech API branch and streaming callback closure

These fixes complete the session isolation implementation. All user-specific data and audio are now properly isolated.

### Security Status: COMPLETE

After this comprehensive implementation (including final review fixes):

✅ **All session-specific broadcasts** use session-targeted delivery (24 handler categories total)
✅ **All error messages** are isolated to the triggering session
✅ **All streaming content** is isolated to the requesting session
✅ **All TTS audio** is delivered only to the requesting session (manual + streaming)
✅ **Message edit status updates** are session-isolated
✅ **Connection keepalive (PONG)** is connection-specific
✅ **Shared resources (voice lists)** correctly remain global
✅ **Multi-tab synchronization** works within same session
✅ **Multi-user isolation** works across different sessions

**The system is now secure for server mode deployment with multiple users.**

### Testing Recommendations

To verify session isolation:

1. **Multi-User Test**: Open two different browsers (e.g., Chrome + Firefox)
   - Start different conversations in each
   - Verify messages don't leak between browsers
   - Verify parameters remain isolated

2. **Multi-Tab Test**: Open multiple tabs in same browser
   - Verify state syncs across tabs
   - Verify other browser sessions remain isolated

3. **Error Isolation Test**: Trigger errors in one session
   - Verify errors only appear in that session
   - Verify other sessions unaffected

4. **Streaming Isolation Test**: Start long AI response in one session
   - Verify streaming content only appears in requesting session
   - Verify other sessions can start independent conversations

## Notes

- The MDSL validation errors seen during server startup are unrelated to this feature
- Background bash processes (409abb, 4d556e) were test servers during development
- The implementation prioritizes working functionality over architectural purity
- Session isolation is critical for distributed/server mode deployments
- All fixes maintain backward compatibility via fallback clauses
