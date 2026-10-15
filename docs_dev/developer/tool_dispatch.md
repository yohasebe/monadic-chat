# Tool Dispatch

A provider helper runs a tool call returned by the model only when the name was offered to the model, and calls it with `public_send`.

## Offered Tools

`Monadic::Utils::ToolDispatchGuard` (`lib/monadic/utils/tool_dispatch_guard.rb`):

- `record!(session, app, tools)` stores the tool names of a request, keyed by the session object and the app, in a fiber-local store (`Thread.current[:monadic_offered_tool_names]`). Every helper calls it right before it sends a chat request, with the request's `tools`, and reads the response and runs its tools on the same code path. A turn that overlaps it in the same session runs on another thread and keeps its own record. A request sent from inside a tool with a session of its own (the code agents, Conduit's agent) is stored under that session and leaves the outer record alone. A request without tools stores an empty list. The store keeps at most `MAX_RECORDS` records per code path and drops the oldest; a call checked against a dropped record is refused.
- `offered_names(tools)` reads names from every provider's shape: `{name:}`, `{function: {name:}}`, `{type: "function", name:}` and Gemini's `{function_declarations: [{name:}]}`. Entries without a name (native or server tools such as `google_search`) are skipped.
- `refusal(session, app, name)` returns nil when `name` is in the latest recorded list for the app. Otherwise, including when nothing was recorded, it returns `❌ Unknown tool: <name>. …`, which the helper sends back as the tool result without calling a method.

The check runs at the start of each helper's dispatch, before `request_tool` is handled:

| Provider | Method |
|---|---|
| OpenAI | `invoke_openai_tool_function` |
| Claude | `invoke_claude_tool_function` |
| Gemini | `process_functions` (`invoke_gemini_tool_function`) |
| Grok | `invoke_grok_tool_function` |
| Mistral | `invoke_mistral_tool_function` |
| Cohere | `invoke_cohere_tool_function` |
| DeepSeek | `invoke_deepseek_tool_function` (also for calls written as DSML or JSON in the content) |
| Ollama | `process_functions` (also for calls parsed from the text) |

## Live Conversation

`sts_offer_tools` records the names it sends to the bridge (`sts_ga_tools`, `sts_gemini_tools`) in `state[:offered_tool_names]`. `sts_execute_tool_safely` runs an `STS_TOOLS` entry only when the returned name is in that list.

## Tool Methods

- A declared tool must be a public method of the app. `spec/unit/apps/declared_tools_public_spec.rb` loads every built-in app and checks this.
- `MonadicApp#send_command`, `#send_code`, `#capture_command` and the Ruby-side helpers, and `MonadicHelper#write_to_file`, are private: tool methods call them after checking their arguments.
- Every shared tool group's module must be loaded by `dsl.rb`, because the DSL includes it with `include X if defined?(X)`. `spec/unit/shared_tools/registry_modules_loaded_spec.rb` checks this.

## Tests

- `spec/unit/utils/tool_dispatch_guard_spec.rb`: the guard, and each helper's dispatch with undeclared names (`send_command`, `exit`, `instance_eval`, `run_code`), a declared tool and a private method.
- `spec/unit/utils/tool_dispatch_recording_spec.rb`: each helper's `api_request` records the tools before it sends the request.
- `spec/unit/utils/websocket/sts_offered_tools_spec.rb`: Live Conversation runs only the tools sent to the bridge.
