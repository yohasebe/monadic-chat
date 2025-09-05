# Server Debug Mode (`rake server:debug`)

`rake server:debug` starts the Monadic server in a non-daemonized debug mode using the local Ruby environment, while other containers (Python, pgvector, Selenium, etc.) are started and reused as needed.

Key behavior:
- Forces `EXTRA_LOGGING=true` (Rakefile) for rich provider/debug logging.
- Detects the Ollama container; sets `OLLAMA_AVAILABLE` accordingly for UI behavior.
- Loads `~/monadic/config/env` if present (API keys, provider defaults, etc.).
- Invokes `./bin/monadic_server.sh debug` to run the Ruby Thin server locally.

When to use:
- Iterating on the Ruby service (`docker/services/ruby`) code.
- Inspecting provider requests/responses with Extra Logging.
- Avoids the extra indirection of running the Ruby app inside the Ruby container during development.

Related tasks:
- `rake server:start` — daemonized mode via `./bin/monadic_server.sh start`.
- `rake server:stop`, `rake server:restart` — manage the locally running server.
