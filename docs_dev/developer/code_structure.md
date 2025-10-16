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

- See [Developing Apps](../../docs/advanced-topics/develop_apps.md) for a complete tutorial
- Check [Monadic DSL](../../docs/advanced-topics/monadic_dsl.md) for syntax reference
- Use existing apps as templates for your own