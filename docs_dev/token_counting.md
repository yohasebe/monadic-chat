# Token Counting

Token counts come from the `Tokenizer` class (`lib/monadic/utils/tokenizer.rb`), which wraps the `tiktoken_ruby` gem. `MonadicApp::TOKENIZER` is the shared instance. The `o200k_base` encoding is used for every model.

## Where Counts Are Made

- `StreamingHandler#check_past_messages` (`lib/monadic/utils/websocket/streaming_handler.rb`) gives each message of the current app a `tokens` value if it has none. It runs after a response (`html_handler.rb`), after a message edit or deletion (`message_editor.rb`) and when a session is loaded (`app_data.rb`).
- `mcp/cost_guard.rb` counts tokens of MCP tool payloads.

## Active Messages and Statistics

`check_past_messages` marks messages `active`, starting from the newest:

- Older messages are marked inactive while the total exceeds `max_input_tokens`, but not below `context_size` active messages when `context_size` is set. The browser sends `max_input_tokens` as the model's `context_window` maximum from `model_spec.js`, or `DEFAULT_MAX_INPUT_TOKENS` (4000) when the model has none.
- The text of an inactive non-system message longer than 500 characters is cut to 200 characters plus `[... content truncated ...]`; the full text is kept in `original_text` and restored when the message becomes active again.
- It returns the totals shown in the UI: system, input, output, active and all tokens, the message counts and the encoding name.

The history sent to the provider is chosen by the vendor helper by message count (in most helpers: the first message plus the last `context_size` messages), not by these token totals.

## Provider-Reported Usage

`TOKEN_COUNT_SOURCE` set to `provider_only` or `hybrid` makes `html_handler.rb` use the provider's `output_tokens` / `completion_tokens` for the `tokens` of the latest assistant message, when the response carries usage. Unset, every count comes from the tokenizer.

## Rules

- A message that already has `tokens` is not recounted; imported messages keep their `tokens`.
- Code that sets `tokens` from provider usage checks `TOKEN_COUNT_SOURCE` first.
