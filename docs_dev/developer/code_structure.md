# File Organization for App Developers

This guide shows you where to place your custom apps and scripts in Monadic Chat.

## User Directory Structure

Your Monadic Chat user directory (`~/monadic/`) contains:

```text
~/monadic/
├── config/           # Your configuration files
│   ├── env           # API keys and settings
│   ├── rbsetup.sh    # Ruby setup script (optional)
│   ├── pysetup.sh    # Python setup script (optional)
│   └── olsetup.sh    # Ollama setup script (optional)
├── data/             # Your data and custom content
│   ├── apps/         # Your custom apps go here
│   ├── scripts/      # Your custom scripts
│   ├── plugins/      # MCP server plugins
│   └── help/         # Help system documents
└── logs/             # Application logs
```

## Creating Custom Apps

### App Directory Structure
Place your apps in `~/monadic/data/apps/`:

```text
~/monadic/data/apps/
└── my_custom_app/
    ├── my_custom_app_openai.mdsl    # App definition
    ├── my_custom_app_tools.rb       # Shared tools (optional)
    └── my_custom_app_openai.rb      # Ruby implementation (optional)
```

### Naming Convention
**Important**: Your app name must match the Ruby class name:
- File: `chat_assistant_openai.mdsl`
- App name: `app "ChatAssistantOpenAI"`
- Class name: `class ChatAssistantOpenAI < MonadicApp`

## Custom Scripts

Place your custom scripts in `~/monadic/data/scripts/`:
- Scripts are automatically made executable
- They're added to PATH so you can call them by name
- Supports `.sh`, `.py`, `.rb` and other executable formats

Example:
```text
~/monadic/data/scripts/
├── my_analyzer.py
├── data_processor.rb
└── utility.sh
```

## Built-in App Locations

The built-in apps are located in the Docker container at:
```text
/monadic/apps/
├── chat/
├── code_interpreter/
├── research_assistant/
└── ...
```

You can use these as examples for your own apps.

## Logs and Debugging

- Application logs: `~/monadic/logs/`
- Enable "Extra Logging" in Console Panel for detailed logs
- Use `puts` statements in Ruby code for debugging

## Best Practices

1. **Organize by Function**: Group related apps in subdirectories
2. **Use Clear Names**: Make app purposes obvious from their names
3. **Keep Backups**: Save copies of working apps before major changes
4. **Test Incrementally**: Test each feature as you add it

## Common File Types

| Extension | Purpose | Example |
|-----------|---------|---------|
| `.mdsl` | App definition | `chat_bot_openai.mdsl` |
| `.rb` | Ruby implementation | `chat_bot_tools.rb` |
| `.py` | Python scripts | `data_analyzer.py` |
| `.sh` | Shell scripts | `backup.sh` |

## Next Steps

- See [Developing Apps](./develop_apps.md) for a complete tutorial
- Check [Monadic DSL](../advanced-topics/monadic_dsl.md) for syntax reference
- Use existing apps as templates for your own

## Runtime Modes (Debug vs Electron)

- Ruby (Sinatra):
  - Debug (`rake server:debug`): Runs locally (no Ruby container)
  - Electron/Build (`electron .`): Runs inside Ruby container

- Tooling Containers (Python/Jupyter, pgvector, Selenium, Ollama):
  - Used in both modes; started via Docker Compose

- Data paths (user-facing vs filesystem):
  - Display in HTML: `/data/...` (URL served by Sinatra)
  - Filesystem access (Ruby): `Environment.data_path` (auto-resolves to `/monadic/data` in container or `~/monadic/data` in debug)

- Ports (typical):
  - App server: `localhost:4567` (debug)
  - PostgreSQL/pgvector: container `pgvector_service:5432`; local debug/tests exposed at `localhost:5433`
  - Python health: `localhost:5070/health`
  - Selenium hub: `http://localhost:4444/wd/hub/status`

Checklist
- Start required containers when running integration/E2E tests (handled by test bootstrap)
- In debug mode, remember: Ruby is local, tools run in containers
- Use `/data/...` for HTML references; use `Environment.data_path` for Ruby file IO
- If JavaScript logs are missing, ensure debug logging is explicitly enabled (quiet mode is default)
- Avoid file name collisions in shared folder: include a timestamp and random suffix (e.g., `result_${Date.now()}_${Math.random().toString(16).slice(2)}`)

### Debug logging tips

- Enable verbose logging in the Web UI:
  - Add `?debug=true` to the URL, or
  - In DevTools console: `localStorage.setItem('ENABLE_DEBUG_LOGGING','true'); location.reload();`
- Disable it: `localStorage.removeItem('ENABLE_DEBUG_LOGGING'); location.reload();`
- Some modules use additional flags (set in console as needed):
  - `window.DEBUG_STATE_CHANGES = true` (session state)
  - `window.DEBUG_MODE = true` (performance monitor)
  - `window.DEBUG_WS_INIT = true` (WebSocket init flow)

### Environment path helpers (Ruby)

- `Environment.data_path` — Filesystem base for shared data (auto-resolves: container `/monadic/data`, debug `~/monadic/data`)
- `Environment.data_file_path(filename)` — `data_path` + safe filename
- `Environment.data_file_exists?(filename)` — Existence check under `data_path`
- `Environment.safe_data_file_path(filename)` — Basename-sanitized absolute path under `data_path`
- `Environment.data_url(filename)` — Web UI URL (served by Sinatra), e.g. `/data/result.png`
