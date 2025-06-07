# Error Handling Improvements for Monadic Chat

## Overview
This document describes the improvements made to prevent infinite retry loops when AI assistants encounter repeated errors during function execution.

## Problem Statement
Previously, when Code Interpreter or Jupyter Notebook apps encountered system-level errors (e.g., font errors, missing modules), they would retry until reaching MAX_FUNC_CALLS (20 for most providers), creating a poor user experience.

## Solution Implementation

### 1. Error Pattern Detection Module
Created `/docker/services/ruby/lib/monadic/utils/error_pattern_detector.rb` that:
- Tracks error history per session
- Detects patterns in error messages (font errors, module errors, permission errors, etc.)
- Counts consecutive similar errors
- Provides context-aware suggestions after 3 similar errors

### 2. Function Call Error Handler
Created `/docker/services/ruby/lib/monadic/utils/function_call_error_handler.rb` that:
- Provides a mixin module for vendor helpers
- Handles error checking and session management
- Integrates with the error pattern detector

### 3. Updated Vendor Helpers
Modified the following files to include error pattern detection:
- `/docker/services/ruby/lib/monadic/adapters/vendors/openai_helper.rb`
- `/docker/services/ruby/lib/monadic/adapters/vendors/claude_helper.rb`
- `/docker/services/ruby/lib/monadic/adapters/vendors/gemini_helper.rb`

The helpers now:
- Track function execution errors
- Stop retrying after 3 similar errors
- Send helpful suggestions to users
- Wait for user input before continuing

### 4. Updated System Prompts
Modified Code Interpreter system prompts to guide AI behavior:
- `/docker/services/ruby/apps/code_interpreter/code_interpreter_openai.mdsl`
- `/docker/services/ruby/apps/code_interpreter/code_interpreter_claude.mdsl`

Key changes:
- Instructs AI to try only 1-2 times before stopping
- Lists specific error types that should not be retried
- Provides clear guidance on what to do when errors persist

### 5. Improved Error Messages
Updated `/docker/services/ruby/lib/monadic/app.rb` to provide clearer error messages from the `send_code` method.

## Error Types Detected

1. **Font Errors**
   - Pattern: `findfont:.*not found`, `cannot find font`, etc.
   - Suggestion: Use alternative fonts or plotting backends

2. **Module Errors**
   - Pattern: `No module named`, `ModuleNotFoundError`, `ImportError`
   - Suggestion: Install missing packages or use alternatives

3. **Permission Errors**
   - Pattern: `Permission denied`, `Access denied`
   - Suggestion: Check system configuration

4. **Resource Errors**
   - Pattern: `Out of memory`, `Disk full`
   - Suggestion: Process smaller datasets or free resources

## Testing
Created comprehensive test suite in `/docker/services/ruby/spec/error_pattern_detector_spec.rb`

## Usage Example

When an AI encounters repeated font errors:

```
Error 1: findfont: Font family 'Arial' not found
Error 2: findfont: Font family 'Helvetica' not found  
Error 3: Cannot find font Times

AI Response:
I'm encountering repeated font-related errors. This appears to be an environment issue.

Suggestions:
1. You can use a different plotting backend that doesn't require specific fonts
2. Try using `plt.rcParams['font.family'] = 'DejaVu Sans'` or another available font
3. Generate plots without text labels temporarily
4. Contact your system administrator to install the missing fonts

Would you like me to try one of these alternatives, or would you prefer to address the font issue first?
```

## Benefits
1. **Better User Experience**: No more watching the AI retry the same failing operation 20 times
2. **Clear Communication**: Users get helpful suggestions instead of repeated errors
3. **Efficiency**: Saves API calls and processing time
4. **Flexibility**: Users can choose how to proceed rather than being stuck in a loop

## Future Enhancements
1. Add more error patterns as they're discovered
2. Make the retry threshold configurable (currently hardcoded to 3)
3. Add error pattern statistics/logging for debugging
4. Extend to other app types beyond Code Interpreter