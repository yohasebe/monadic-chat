# Session Restoration Improvements

## Server Restart Detection Feature

### Purpose
Automatically detect when the server has been restarted and clear stale messages from localStorage to prevent showing outdated conversation history.

### Problem
When the server restarts (e.g., `rake server:debug`), the server-side session is cleared but client-side localStorage retains old messages. This causes:
- Old messages appear after page reload
- #start button shows "Continue Session" even though server has no history
- Potential confusion about conversation state

### Solution Approach

#### Detection Mechanism
When the WebSocket receives a `past_messages` event during session restoration:
1. Compare server messages count vs localStorage messages count
2. If server has 0 messages but localStorage has messages → server was restarted
3. Clear localStorage and DOM to sync with server's fresh state

#### Implementation Location
File: `/docker/services/ruby/public/js/monadic/websocket.js`
Event: `case "past_messages"`
Condition: `window.isRestoringSession === true`

#### Code Pattern (Commented Out)
```javascript
case "past_messages": {
  if (window.isRestoringSession) {
    const serverMessages = data["content"] || [];
    const localMessages = window.SessionState.getMessages() || [];

    // Server restart detection
    if (serverMessages.length === 0 && localMessages.length > 0) {
      console.log('[Session] Server restart detected - clearing local messages');
      window.SessionState.clearMessages();
      $("#discourse").empty();
      setStats(formatInfo([]), "info");

      // Update START button to "Start Session"
      if (window.i18nReady) {
        window.i18nReady.then(() => {
          const startText = webUIi18n.t('ui.session.startSession');
          $("#start-label").text(startText);
        });
      } else {
        $("#start-label").text('Start Session');
      }
      break;
    }

    // Normal restoration continues...
  }
}
```

### Challenges Encountered and Solutions

#### Issue 1: Timing of Message Rendering (SOLVED)
**Problem**: Original implementation delayed message rendering until `past_messages` confirmation, but this caused issues with `messages` global variable initialization.

**Impact**: `messages.length` check in `#start` button handler failed, leading to incorrect SYSTEM_PROMPT behavior.

**Solution**: Render messages immediately on page load (line 136-182 in monadic.js), then clear them AFTER if server restart is detected. This preserves the global `messages` variable initialization while still detecting server restarts.

#### Issue 2: Race Conditions (SOLVED)
**Problem**: WebSocket `past_messages` arrives asynchronously, but UI state must be consistent.

**Solution**: Since `window.messages` is a proxy to `SessionState.conversation.messages` (session_state.js:607-629), calling `SessionState.clearMessages()` automatically clears both localStorage AND the global `messages` variable. This ensures atomic state updates.

#### Issue 3: Visual Flicker (ACCEPTABLE)
**Minor Issue**: Messages briefly appear on screen before being cleared when server restart is detected.

**Decision**: Acceptable trade-off. The flicker lasts ~100-200ms and only occurs on actual server restart, which is rare. The benefit of reliable server restart detection outweighs the minor visual glitch.

### Requirements for Future Implementation

1. **Preserve Current Behavior**: Normal page reload must show restored messages immediately
2. **Detect Server Restart**: Reliably identify when server has restarted vs normal reload
3. **Atomic State Updates**: All state (localStorage, DOM, button text, messages array) must update together
4. **No False Positives**: Don't clear messages when server intentionally has no history (new session)

### Alternative Approaches

#### Option 1: Server-Side Session ID
Add a session ID that changes on server restart. Client can detect mismatch and clear localStorage.

**Pros**: Reliable detection
**Cons**: Requires server-side changes

#### Option 2: Timestamp Comparison
Store server startup timestamp. Client compares with last-seen timestamp.

**Pros**: No complex state management
**Cons**: Requires server to expose startup time

#### Option 3: Explicit Reset Flag
Server sends explicit "session_reset" message on first connection after restart.

**Pros**: Clear, explicit behavior
**Cons**: Requires WebSocket protocol changes

### Related Files
- `/docker/services/ruby/public/js/monadic.js` (lines 136-182): Message rendering during page load
- `/docker/services/ruby/public/js/monadic/websocket.js` (lines 4210-4241): past_messages handler
- `/docker/services/ruby/public/js/monadic/session_state.js` (lines 269-279): clearMessages with save()

### Status
- **Current**: ✅ IMPLEMENTED (as of 2025-11-01)
- **Implementation**: Lines 4210-4265 in `/docker/services/ruby/public/js/monadic/websocket.js`
- **Approach**: Detect server restart after page load, then clear stale messages
- **Key Insight**: Messages are rendered immediately on page load (preserves global `messages` initialization), then cleared if server restart is detected

### Test Cases for Future Implementation

1. **Normal Page Reload**
   - Start conversation → reload page → messages should restore

2. **Server Restart Detection**
   - Start conversation → restart server → reload page → messages should clear

3. **Reset Button**
   - Start conversation → click Reset → new session without old messages

4. **App Switching**
   - Conversation in App A → switch to App B → only App B messages shown

5. **Import Conversation**
   - Import .json file → messages should appear correctly

### Notes
- This feature is important for user experience
- Must not interfere with normal session restoration
- Must handle edge cases (empty conversations, multiple tabs, etc.)
