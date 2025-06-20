# Edit Message Image Fix Summary

## Issues Fixed

1. **Server-side (websocket.rb)**: Images were not being updated when editing messages
   - Added code to update `message_to_edit["images"]` from `obj["images"]` when provided
   - Added debug logging to track image updates

2. **Client-side (websocket.js)**: Mask images were not properly rendered after editing
   - Implemented the same image grouping logic used in `createCard` function
   - Properly handles mask overlay containers with base and mask images
   - Updates the client-side messages array with new images

3. **Debug logging added**:
   - cards.js: Logs when sending edit messages with images
   - websocket.js: Logs received edit_success data including image counts
   - websocket.rb: Logs image updates when EXTRA_LOGGING is enabled

## How to Test

1. Enable extra logging in `~/monadic/config/env`:
   ```
   EXTRA_LOGGING=true
   ```

2. Test scenarios:
   - Edit a message with regular images
   - Edit a message with PDF attachments
   - Edit a message with mask images (from Image Analyzer app)
   - Edit assistant messages (should show "Processing..." then update)

3. Check browser console for debug logs:
   - `[Edit] Sending message with images: X images`
   - `[edit_success] Received data: {...}`
   - `[edit_success] Updated message images in array: X images`

## Expected Behavior

- When editing messages with images/PDFs, they should be preserved
- Mask images should display with their overlay structure
- Assistant messages should show "Processing..." temporarily, then display the formatted content
- All image types (regular, PDF, mask overlays) should be properly restored