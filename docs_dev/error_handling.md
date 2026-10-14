# Error Handling in Tool Loops

This page describes the safeguards that stop a tool loop: repeated tool errors, tool call cycles and the per-turn tool call limit.

## Error Detection (`FunctionCallErrorHandler`)

`lib/monadic/utils/function_call_error_handler.rb` is included by the vendor helpers.

- `function_return_is_error?` treats a tool result as an error when it is:
  - a string starting with `ERROR:`, `Error:`, `Error executing code`, `Error occurred` or `❌`;
  - a Hash with `success: false` (symbol or string key);
  - a string containing `"success":false` or `"success": false`.
- `handle_function_error` records the error in `ErrorPatternDetector`, marks the last recorded tool call as errored, and, when the detector says to stop, sends the suggestion as a fragment and sets `session[:parameters]["stop_retrying"] = true`.
- `should_stop_for_errors?` is true when `stop_retrying` is set or a tool call cycle is detected. `stop_message_for_session` returns the cycle message or the error suggestion.
- `reset_error_tracking(session)` clears the error history, the tool call sequence and `stop_retrying`.

Tool methods return errors as strings starting with `❌`.

## Error Patterns (`ErrorPatternDetector`)

`lib/monadic/utils/error_pattern_detector.rb`:

- `detect_pattern` matches the message against `SYSTEM_ERROR_PATTERNS` (fonts, missing modules, permissions, resources, plotting, file I/O, network).
- Three errors in a row with the same pattern stop retrying (`similar_count >= 2`). An error with no pattern resets the count.
- `session[:error_patterns][:history]` keeps the last 10 errors. `get_error_suggestion` builds a suggestion for the matched pattern and lists the last three errors.

## Tool Call Cycles

`record_tool_call` appends each tool call to `session[:tool_call_sequence]`. `detect_tool_call_cycle` looks for a repeated cycle of 1, 2 or 3 tool names (from 4 recorded calls on):

| Cycle length | Repetitions when a call in the window errored | Repetitions when all succeeded |
|---|---|---|
| 1 | 5 | 8 |
| 2 or 3 | 3 | 5 |

## Tool Call Limit per Turn (`MAX_FUNC_CALLS`)

Each vendor helper defines `MAX_FUNC_CALLS` (20; 30 in the Mistral helper). `session[:call_depth_per_turn]` is reset to 0 when the user sends a message and increases with each round of tool calls. When the limit is reached, the helper ends the tool loop: most helpers send a "Maximum function call depth exceeded" notice and end the turn; the Claude helper removes `tools` and `tool_choice` so the model answers in text.

## Debugging

- `session[:error_patterns]` shows the matched pattern, the count and the history; `session[:parameters]["stop_retrying"]` shows whether the loop was stopped.
- To add an error category, extend `SYSTEM_ERROR_PATTERNS` and its suggestion text in `get_error_suggestion`.

## Tests

- `spec/unit/utils/error_pattern_detector_spec.rb`
- `spec/unit/utils/function_call_error_handler_spec.rb`
