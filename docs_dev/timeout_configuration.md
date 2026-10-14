# API Timeout Configuration

Each vendor helper declares its HTTP timeouts with `define_timeouts` (`lib/monadic/adapters/base_vendor_helper.rb`). The values can be changed in `~/monadic/config/env`.

## Defaults and Variables

`define_timeouts "PREFIX", open:, read:, write:` creates `open_timeout`, `read_timeout` and `write_timeout`, each reading `PREFIX_OPEN_TIMEOUT`, `PREFIX_READ_TIMEOUT` or `PREFIX_WRITE_TIMEOUT` from `CONFIG` (seconds), with the default below.

| Helper | Prefix | Open | Read | Write |
|---|---|---|---|---|
| OpenAI | `OPENAI` | 20 | 600 | 120 |
| Claude | `CLAUDE` | 10 | 600 | 120 |
| Gemini | `GEMINI` | 10 | 600 | 120 |
| Cohere | `COHERE` | 10 | 600 | 120 |
| Mistral | `MISTRAL` | 5 | 600 | 120 |
| Grok | `GROK` | 20 | 600 | 120 |
| DeepSeek | `DEEPSEEK` | 10 | 120 | 120 |
| Ollama | `OLLAMA` | 5 | 600 | 60 |
| Tavily | `TAVILY` | 10 | 60 | 60 |

Example:

```bash
OPENAI_READ_TIMEOUT=900
GEMINI_READ_TIMEOUT=300
```

- **Open**: time to establish the connection.
- **Read**: time to wait for the response after the request is sent.
- **Write**: time to send the request body (large attachments).

## OpenAI Overrides

`openai_helper.rb` chooses the read timeout per request:

| Request | Read timeout |
|---|---|
| Responses API | 1200 seconds (not configurable) |
| Chat Completions, reasoning model with `medium` or `high` effort | 600 seconds (not configurable) |
| Other | `OPENAI_READ_TIMEOUT` (default 600) |

## Other Timeouts

Code generation agents have their own timeouts (`OPENAI_CODE_TIMEOUT`, `GROK_CODE_TIMEOUT`; see [Agent Architecture](developer/agent_architecture.md)). Media analysis agents use fixed timeouts defined in each agent.

## Troubleshooting

- Errors while waiting for a long answer: raise `<PREFIX>_READ_TIMEOUT`.
- Errors when connecting on a slow network: raise `<PREFIX>_OPEN_TIMEOUT`.
- Errors while uploading large files: raise `<PREFIX>_WRITE_TIMEOUT`.
