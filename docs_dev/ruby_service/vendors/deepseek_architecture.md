# DeepSeek Architecture

This document describes the DeepSeek adapter, `lib/monadic/adapters/vendors/deepseek_helper.rb`. Model capabilities come from `model_spec.js` and are read through `Monadic::Utils::ModelSpec`.

## Request

- Endpoint: `https://api.deepseek.com/chat/completions`, OpenAI-compatible, streaming.
- Context: the system message plus the last `context_size + 1` messages.
- Web search uses the Tavily tools (`Monadic::SharedTools::TavilyDefinitions`) when web search is requested; the Tavily prompt is appended to the system message.
- JSON mode (`json true`) appends a JSON instruction to the system message and sets `response_format: {type: "json_object"}` (not on tool-result requests). Monadic mode does not add it.
- `prompt_suffix` is appended to the last user message (to its text part when the message carries images).
- Timeouts: `DEEPSEEK_OPEN_TIMEOUT` (10 s), `DEEPSEEK_READ_TIMEOUT` (120 s), `DEEPSEEK_WRITE_TIMEOUT` (120 s), read from the config.
- `post_json_with_retries` makes up to `MAX_RETRIES = 5` attempts, `RETRY_DELAY = 1` second apart.

## Thinking

Models with `reasoning_content: ["disabled", "enabled"]` in `model_spec.js`:

- `thinking: {type: "disabled"}` when the session's `reasoning_content` is `disabled`, otherwise `{type: "enabled"}`.
- With thinking enabled, `reasoning_effort` `high` or `max` is added to `thinking`; other values are not sent.
- Thinking arrives as `delta.reasoning_content` and is streamed as `thinking` messages.
- The reasoning of each tool round is sent back with the tool call (`assistant.reasoning_content`) and accumulated in `session[:deepseek_reasoning]`; the final message carries the whole trace.

`send_query` (Second Opinion, AI User, Context Extractor) sends `thinking: {type: "disabled"}`, a non-streaming request, `max_tokens` 1000 and `temperature` 0.7 unless the options set them. Without a model it uses the provider default.

## Images

Images are sent only as JPEG, PNG, GIF or WebP; other attachments (PDFs) are dropped. If the selected model lacks `vision_capability`, the request switches to the first `providerDefaults.deepseek.vision` model and the user gets a `system_info` message naming both models.

## Tool Calls

- Tools: the app's tools after progressive tool disclosure (`ProgressiveToolManager`), plus the Tavily tools when web search is on. `tool_choice: "auto"`.
- An assistant message with `tool_calls` is sent with `content: nil`.
- Text written before a tool call is saved as its own assistant message and shown with `more_coming: true`.
- At most `MAX_FUNC_CALLS = 20` rounds; beyond that the turn ends with "ERROR: Call depth exceeded".
- `should_stop_for_errors?` ends the turn on repeated tool errors ("Repeated errors detected.").
- A web search tool called while web search is off makes the next request go without tools.

### Terminal Tools

`TERMINAL_TOOLS` (`save_learning_progress`, `save_conversation_analysis`, `save_diagnosis_progress`, `save_analysis_result`) end the turn: after running them the adapter sends `DONE` and returns a response with empty `content` instead of making another request.

### DSML

The model sometimes writes tool calls as DSML text (`<｜DSML｜function_calls>`, `<｜DSML｜invoke name="…">`, `<｜DSML｜param name="…">`) instead of `tool_calls`.

- While streaming, fragments that contain DSML are not shown. The stream stops early when there are more than 2 `function_calls` blocks, or more than 3 `invoke` tags without a closing tag.
- After the stream, the content is normalized (fullwidth `｜` → `|`, `</|DSML|tag>` → `<|DSML|/tag>`, whitespace between tags) and parsed into `tool_calls` with generated ids. On the first round, a call to a tool name that is not among the app's tools (and the Tavily tools when web search is on) adds a user message listing the valid names to the session and retries.
- Malformed DSML (the same counts as above) is retried up to 4 times, waiting 1, 2, 3, 4 seconds and showing `RETRYING TOOL CALL (n/4)`. After that the user gets a "Tool Call Issue" notice and the DSML tags are removed from the text.
- DSML that yields no valid call is removed from the text.
- Tavily calls written as a fenced JSON block are also parsed (`parse_deepseek_json_function_call`).

## Logging

With `EXTRA_LOGGING=true`, the adapter logs the raw DSML (first 500 characters), the tag counts, early aborts and retries.

## Tests

- `spec/unit/deepseek_reasoning_spec.rb`
- `spec/unit/deepseek_terminal_tool_spec.rb`
- `spec/unit/deepseek_vision_spec.rb`
- `spec/unit/apps/deepseek_monadic_variants_spec.rb`
- `spec/unit/adapters/vendors/deepseek_send_query_default_model_spec.rb`
- API: `PROVIDERS=deepseek RUN_API=true bundle exec rspec spec/integration/provider_matrix/`
