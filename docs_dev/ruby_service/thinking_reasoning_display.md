# Thinking/Reasoning Display

The vendor helpers stream a model's thinking or reasoning to the UI separately from the answer, and attach the whole trace to the final message.

## Streaming

Each helper sends WebSocket messages of type `thinking` or `reasoning` with a text fragment in `content`:

| Provider | Source in the API response | Message type |
|---|---|---|
| OpenAI | Responses API reasoning summary events | `reasoning` |
| Anthropic | `thinking` content blocks (`thinking_delta`) | `thinking` |
| Gemini | parts with `thought: true` | `thinking` |
| DeepSeek | `delta.reasoning_content` | `thinking` |
| xAI | Responses API reasoning summary events (`delta.reasoning_content` as a fallback) | `thinking` |
| Mistral | `thinking` content parts | `thinking` |
| Cohere | `content.thinking` | `thinking` |
| Ollama | `message.thinking` | `thinking` |

`ws-thinking-handler.js` (`handleThinking`) skips empty content, creates `#temp-reasoning-card` titled "Thinking Process" or "Reasoning Process" (`ui.messages.thinkingProcess` / `reasoningProcess`), and appends each fragment.

## Final Message

- OpenAI and Ollama put the trace in `message["reasoning_content"]`; the other helpers in `message["thinking"]`. Traces from earlier tool rounds of the same turn are merged in.
- `html_handler.rb` takes `thinking`, then `reasoning_content`, and stores the result as the message's `thinking`.
- `websocket-handlers.js` renders it above the answer with `renderThinkingBlock` (collapsible, Markdown). PDF export (`pdf_export.js`) includes it.

## Show Thinking

The Show Thinking checkbox (`#show-thinking`, parameter `show_thinking`) is shown only for models with `supports_thinking: true`, never in Live Conversation, and is unchecked unless the saved parameters say otherwise.

| Provider | Effect of `show_thinking: false` |
|---|---|
| Anthropic | Adaptive-thinking models get `thinking.display: "omitted"` (blocks keep their signature, no text is streamed). With the checkbox on, models whose default display is omitted (`ModelSpec.thinking_display_default_omitted?`) get `display: "summarized"` |
| Gemini | `thinkingConfig.includeThoughts: false` |
| Ollama | `think: true` is not sent, and thinking fragments are not streamed (they are still kept in `reasoning_content`) |
| Others | No request change |

## Request Parameters

The thinking parameters of each provider (effort, budgets, on/off) are set by the vendor helpers from `reasoning_effort` and the model's flags in `model_spec.js` (`supports_thinking`, `supports_adaptive_thinking`, `supports_thinking_level`, `thinking_budget`, `reasoning_effort`, `reasoning_content`). See [anthropic_architecture.md](vendors/anthropic_architecture.md) and [deepseek_architecture.md](vendors/deepseek_architecture.md).

## Tests

`spec/unit/openai_reasoning_spec.rb`, `claude_thinking_spec.rb`, `gemini_thinking_spec.rb`, `deepseek_reasoning_spec.rb`, `grok_reasoning_spec.rb`, `mistral_reasoning_spec.rb`, `cohere_thinking_spec.rb` (all in `spec/unit/`).

## Related Documentation

- `docs_dev/websocket_progress_broadcasting.md`
