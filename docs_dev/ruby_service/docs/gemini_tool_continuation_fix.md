# Gemini Tool Rounds

This page describes how the Gemini adapter (`lib/monadic/adapters/vendors/gemini_helper.rb`) sets `tools` and `toolConfig` on user turns and on the follow-up requests that carry tool results (`role == "tool"`).

## User Turns

`configure_gemini_tools` builds the tools:

- The app's function declarations, filtered by progressive tool disclosure (`ProgressiveToolManager`) and by `ToolKeyRequirements`.
- With native web search requested, `gemini_web_search` is added to the declarations. Without declarations, `google_search` is used instead.
- With native web search, a `url_context` tool is added when the message contains a URL, or when there are no function declarations.
- `toolConfig.functionCallingConfig.mode` is `AUTO` whenever function declarations are present.
- For models without `tool_capability`, only `google_search` and `url_context` are kept.

## Tool-Result Requests

- `build_gemini_request_body` sets `tools` from `obj["tools"]` with `mode: AUTO`, so the model can call further tools. For apps other than Jupyter, `apply_tool_round_tools!` then rebuilds them as a user turn does: the filtered declarations (locked conditional tools stay out; tools unlocked in this turn are in), plus `gemini_web_search` when web search is on. Without declarations, native entries already in the request (such as `google_search`) are kept; when nothing is left, `tools` and `toolConfig` are removed.
- The assistant turn holding the `functionCall` parts (with their thought signatures) is rebuilt in front of the results, and the results are sent under role `user`.
- Screenshot images left by tools (`session[:pending_tool_images]`) are added as a user message, each image once per turn.
- When `session[:call_depth_per_turn]` reaches `MAX_FUNC_CALLS` (20), `tools` and `toolConfig` are removed so the model answers in text.

### Jupyter Apps

For apps whose name contains `jupyter`/`Jupyter`, the adapter decides from the tool results of the turn whether to allow more calls. `get_jupyter_cells_with_results` and `list_jupyter_notebooks` do not count. Tools are removed (and `thinkingConfig` with them) when any of these holds:

- `create_and_populate_jupyter_notebook` was called;
- a cell was added, updated or deleted;
- `execute_and_fix_jupyter_cells` or `run_code` was called;
- three different action tools were called.

Otherwise the app's tools are sent again with `mode: AUTO`.

## Tests

- `spec/integration/gemini_tool_continuation_integration_spec.rb`
- `spec/integration/gemini_jupyter_combined_function_spec.rb`
- `spec/integration/jupyter_notebook_gemini_spec.rb`
