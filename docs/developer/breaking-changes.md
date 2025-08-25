# Breaking Changes for Version 1.0.0

This page documents all breaking changes from previous versions to help users migrate to Monadic Chat 1.0.0.

## Version 1.0.0-beta.2

### Web Search in Chat Apps

#### What Changed
- **Chat apps now have web search disabled by default**
- This change gives users explicit control over when web search is used
- Helps manage API costs and maintain privacy

#### Why This Change?
- **Cost Control**: Web search operations can consume additional API calls
- **Privacy**: Users may not want all queries to trigger web searches
- **Predictability**: Users have explicit control over when current information is fetched
- **Reliability**: The web search feature is now stable and well-tested

#### How to Enable Web Search
1. Open any Chat app
2. Click on the Settings button
3. Toggle "Web Search" to enable it
4. The setting persists for that session

#### Apps Affected
- All Chat apps (OpenAI, Claude, Gemini, Mistral, Cohere, Perplexity, Grok, DeepSeek, Ollama)
- Research Assistant apps continue to have web search enabled by default

## Version 1.0.0-beta.1

### Configuration System Changes

The most significant change in 1.0.0 is the unified configuration system.

#### What Changed
- **All API keys and settings must now be in `~/monadic/config/env`**
- Environment variables are no longer used as fallbacks for any user settings
- This ensures consistency between UI and backend behavior

#### Affected Settings
- All API keys: `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, etc.
- Default models: `OPENAI_DEFAULT_MODEL`, `ANTHROPIC_DEFAULT_MODEL`, etc.
- Feature settings: `AI_USER_MAX_TOKENS`, `DISTRIBUTED_MODE`
- Other settings: `PYTHON_PORT`, `HELP_EMBEDDINGS_BATCH_SIZE`, `TTS_DICT_DATA`

#### Migration Steps
1. Check your environment variables for any API keys or settings
2. Copy these values to `~/monadic/config/env`
3. Remove the environment variables to avoid confusion

#### Why This Change?
- Single source of truth for all configuration
- UI and backend now behave consistently
- Easier debugging and troubleshooting
- Better alignment with Electron app's GUI configuration

### Embedding Model Changes

#### What Changed
- **Now uses `text-embedding-3-large` (3072 dimensions) exclusively**
- The `text-embedding-3-small` option has been removed from settings
- Help database schema has changed to accommodate larger dimensions

#### Migration Steps
1. After updating to 1.0.0, rebuild the help database:
   ```bash
   rake help:rebuild
   ```
2. For PDF Navigator users, existing embeddings will continue to work
3. New embeddings will use the new model automatically

#### Why This Change?
- Better quality embeddings for more accurate search results
- Simplified configuration (no need to choose embedding models)
- Consistent performance across all embedding features

### API and Code Changes

#### Removed Methods
- `run_script` method has been removed
- All providers now use `run_code` exclusively

#### Migration for App Developers
If you have custom apps using `run_script`:
```ruby
# Old way (no longer works)
run_script(script: "example.py", args: ["arg1", "arg2"])

# New way
run_code(code: File.read("example.py"), command: "python", extension: "py")
```

#### Python Script Reorganization
Scripts have been reorganized into categorical directories:
- `utilities/` - System and utility scripts
- `cli_tools/` - Command-line tools
- `converters/` - File format converters
- `services/` - API services

#### File Renames
- `sysinfo` → `sysinfo.sh`
- `app.py` → `flask_server.py`

### Ruby Version Requirement

- Minimum Ruby version is now 2.6.10
- This ensures compatibility with all dependencies

### Speech-to-Text Note

The Speech Input feature uses OpenAI's Whisper API and requires `OPENAI_API_KEY` in the configuration file to function. This is not a change, but worth noting as environment variable fallback is no longer available.

## Checking Your Current Version

To check your current version:
1. Click on **File** → **About Monadic Chat** in the desktop app
2. Or check the `version.rb` file in the source code

## Getting Help

If you encounter issues during migration:
1. Check the [Troubleshooting Guide](troubleshooting.md)
2. Review the [Changelog](../changelog.md) for detailed changes
3. Open an issue on [GitHub](https://github.com/yohasebe/monadic-chat/issues)