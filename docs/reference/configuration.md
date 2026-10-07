# Configuration Reference

This page provides a comprehensive reference for all configuration options in Monadic Chat. Configuration can be set in the `~/monadic/config/env` file or through the GUI settings panel.

## Configuration Categories

- [Configuration Priority](#configuration-priority)
- [API Keys](#api-keys)
- [Model Settings](#model-settings)
- [System Settings](#system-settings)
- [Voice Settings](#voice-settings)
- [Help System Settings](#help-system-settings)
- [Development Settings](#development-settings)
- [Container Settings](#container-settings)
- [Install Options](#install-options)
- [PDF Processing Settings](#pdf-processing-settings)

## Configuration Priority

Monadic Chat uses the following priority order for configuration values (highest to lowest):

1. **An explicit `model` in an app's `llm` block** (model values only)
   - An app that pins a model keeps it regardless of the settings below
   - Apps that omit `model` fall through to the sources below

2. **Environment Variables** (`~/monadic/config/env`)
   - User-defined settings take priority over the shipped defaults

3. **Provider Defaults** (`providerDefaults` in `model_spec.js`)
   - Provider-specific default models defined as the single source of truth (SSOT)
   - Applied when no environment variable is set

4. **Hardcoded Defaults**
   - Built-in fallback values in the code
   - Used as last resort when neither ENV nor providerDefaults provide a value

### Example

For the OpenAI default model:
- If `OPENAI_DEFAULT_MODEL=<model-id>` is set in `~/monadic/config/env`, it will be used
- Otherwise, the value from `providerDefaults` in `model_spec.js` will be used
- If neither exists, the hardcoded default in the application will be applied

> **Note**: For current default values, refer to `providerDefaults` in `docker/services/ruby/public/js/monadic/model_spec.js`. Model names are updated frequently, so it's recommended to check the implementation files for the latest values.

## API Keys :id=api-keys

| Variable | Description | Required | Example |
|----------|-------------|----------|---------|
| `OPENAI_API_KEY` | OpenAI API key for GPT models | Yes (for OpenAI apps) | `sk-...` |
| `ANTHROPIC_API_KEY` | Anthropic API key for Claude models | Yes (for Claude apps) | `sk-ant-...` |
| `GEMINI_API_KEY` | Google API key for Gemini models | Yes (for Gemini apps) | `AIza...` |
| `MISTRAL_API_KEY` | Mistral AI API key | Yes (for Mistral apps) | `...` |
| `COHERE_API_KEY` | Cohere API key | Yes (for Cohere apps) | `...` |
| `DEEPSEEK_API_KEY` | DeepSeek API key | Yes (for DeepSeek apps) | `...` |
| `XAI_API_KEY` | xAI API key for Grok models | Yes (for Grok apps) | `xai-...` |
| `ELEVENLABS_API_KEY` | ElevenLabs API key for TTS, Scribe speech-to-text, and ElevenLabs Music in Music Generator | Yes (for ElevenLabs voices) | `...` |
| `TAVILY_API_KEY` | Tavily API key for web search — see [Provider Capabilities Overview](../basic-usage/basic-apps.md#provider-capabilities) | Required for web search through Tavily | `tvly-...` |

### Reading Keys from 1Password :id=onepassword-references

Any value in `~/monadic/config/env` can be a 1Password secret reference instead of the key itself:

```
OPENAI_API_KEY=op://Dev/OpenAI/credential
```

Values that do not start with `op://` are used as written, as before.

- **Requirements**: the 1Password desktop app and the [1Password CLI](https://developer.1password.com/docs/cli/) (`op`) on the computer that runs the app, with **Settings → Developer → Integrate with 1Password CLI** turned on in the desktop app. This setting is the same on macOS, Windows and Linux. On Windows, turn on Windows Hello in 1Password first. On Linux, turn on **Settings → Security → Unlock using system authentication** first; it needs PolKit and a running PolKit authentication agent. The Snap and Flathub packages of 1Password do not support this integration. See [1Password's instructions](https://developer.1password.com/docs/cli/app-integration/). Session variables set by signing in manually in a terminal are not passed to the app when it is started from the desktop. The app looks for `op` on `PATH` and in the usual install locations.
- **When the references are read**: when you press Start, all of them in one `op` call, so 1Password normally asks for confirmation once. If that call fails, each reference is read on its own to find which one failed, and 1Password may ask again. Once every reference has been read, the values are kept until the app quits, and Restart and container restarts do not read them again; if some could not be read, the next Start or Restart tries again. Changing a reference in the settings reads the references again at the next Start.
- **Where the values go**: `~/monadic/config/env` keeps the references. The values are held in the app's memory and handed to the Ruby container through a memory-only mount (tmpfs); they are not written to a file, the container's settings or its environment, and they are not logged. A memory-only mount lives in the memory of the Docker virtual machine; whether that memory can be swapped to its disk depends on Docker Desktop.
- **When a reference cannot be read**: the console names the key and the reason (`op` not found, 1Password locked or the CLI not signed in, the confirmation declined, the item or field not found). That key stays unset until the next Start; other keys and features keep working. The reference itself is never sent to a provider as a key.
- **A Ruby container built by an earlier version**: it cannot use the values, so the app does not hand them over and asks you to rebuild it (**Actions → Build Ruby Container**). This happens only when the container was not rebuilt after an update.
- **Development mode** (`rake server:debug`): the server runs on the host and reads the references itself with `op`.

## Model Settings

> **Note**: For default values, refer to `providerDefaults` in `docker/services/ruby/public/js/monadic/model_spec.js`. The table below shows variable names and usage only.

| Variable | Description | Usage Example |
|----------|-------------|---------------|
| `OPENAI_DEFAULT_MODEL` | Default model for OpenAI apps | `OPENAI_DEFAULT_MODEL=<model-id>` |
| `ANTHROPIC_DEFAULT_MODEL` | Default model for Claude apps | `ANTHROPIC_DEFAULT_MODEL=<model-id>` |
| `TOKEN_COUNT_SOURCE` | Token counting source policy | `TOKEN_COUNT_SOURCE=provider_only` (options: `provider_only`, `hybrid`) |
| `GEMINI_DEFAULT_MODEL` | Default model for Gemini apps | `GEMINI_DEFAULT_MODEL=<model-id>` |
| `MISTRAL_DEFAULT_MODEL` | Default model for Mistral apps | `MISTRAL_DEFAULT_MODEL=<model-id>` |
| `COHERE_DEFAULT_MODEL` | Default model for Cohere apps | `COHERE_DEFAULT_MODEL=<model-id>` |
| `DEEPSEEK_DEFAULT_MODEL` | Default model for DeepSeek apps | `DEEPSEEK_DEFAULT_MODEL=<model-id>` |
| `GROK_DEFAULT_MODEL` | Default model for Grok apps | `GROK_DEFAULT_MODEL=<model-id>` |
| `OLLAMA_DEFAULT_MODEL` | Default model for Ollama apps | `OLLAMA_DEFAULT_MODEL=<model-id>` |

### Model Selection in the UI

The **Model** dropdown shows a curated list of recommended models for the selected app. This list comes from the app's MDSL definition or the provider's default model set.

To see all available models from the provider, toggle the **All** switch next to the Model label. In "All" mode, models that are incompatible with the current app (e.g., models without tool support for apps that require tools) are automatically excluded. Your toggle preference is saved across sessions via a browser cookie.

## System Settings

| Variable | Description | Default | Range/Options |
|----------|-------------|---------|---------------|
| `MAX_STORED_MESSAGES` | Maximum number of messages stored in localStorage for session restoration | `1000` | 50-1000 (cannot exceed context size when enabled) |
| `ROUGE_THEME` | Syntax highlighting theme | `github:light` | See [available themes](../basic-usage/syntax-highlighting.md) |

> **Note**: `MAX_STORED_MESSAGES` determines how many conversation messages are persisted across browser sessions. When the context size setting is enabled in the Web UI, the actual limit will be the smaller of `MAX_STORED_MESSAGES` or the configured context size value.

## Voice Settings

| Variable | Description | Default | Range/Options |
|----------|-------------|---------|---------------|
| `TTS_DICT_PATH` | Path to a TTS pronunciation dictionary CSV. Set via the Electron Settings panel ("TTS Dictionary File Path"); the file is copied to `~/monadic/config/TTS_DICT.csv`, which the server reads | (optional) | File path |
| `TTS_DICT_DATA` | Inline TTS pronunciation data (legacy; used only when no dictionary file is available) | (optional) | CSV format |

> **Note**: The speech-to-text model is not configured via environment variables. Select it in the **Speech Settings** panel of the web UI; the selection is stored in the browser's local storage.

## Help System Settings

| Variable | Description | Default | Range |
|----------|-------------|---------|-------|
| `HELP_CHUNK_SIZE` | Characters per documentation chunk (build time) | `3000` | 1000-8000 |
| `HELP_OVERLAP_SIZE` | Character overlap between chunks (build time) | `500` | 100-2000 |
| `HELP_CHUNKS_PER_RESULT` | Number of chunks returned per search | `3` | 1-10 |

## Development Settings

| Variable | Description | Default | Options |
|----------|-------------|---------|---------|
| `DISTRIBUTED_MODE` | Enable multi-user server mode | `off` | `off`, `server` |
| `SESSION_SECRET` | Secret key for session management | (generated) | Any string |
| `MCP_SERVER_ENABLED` | Enable Model Context Protocol server | `false` | `true`, `false` |
| `MCP_SERVER_PORT` | Port for the Model Context Protocol server | `3100` | Any free port |
| `ALLOW_JUPYTER_IN_SERVER_MODE` | Enable Jupyter in server mode | `false` | `true`, `false` |
| `EXTRA_LOGGING` | Enable detailed logging | `false` | `true`, `false` |

### Application Modes

Monadic Chat supports two application modes that control network accessibility:

**Standalone Mode** (Default: `DISTRIBUTED_MODE=off` or unset)
- Server binds to `127.0.0.1` (localhost only)
- Accessible only from the local machine
- JupyterLab environment enabled
- Recommended for single-user local development

**Server Mode** (`DISTRIBUTED_MODE=server`)
- Server binds to `0.0.0.0` (all network interfaces)
- Accessible from any device on the network via local IP address (e.g., `http://192.168.1.10:4567`)
- Each connected device has its own session; conversation state is stored per browser session and is not shared across devices or browsers
- JupyterLab disabled by default for security (enable with `ALLOW_JUPYTER_IN_SERVER_MODE=true`)
- See [Advanced Configuration](/advanced-topics/advanced-configuration.md) for session isolation details

## Container Settings

| Variable | Description | Default | Note |
|----------|-------------|---------|------|
| `QDRANT_URL` | Full URL of the Qdrant service | `http://qdrant_service:6333` (in-container) / `http://localhost:6333` (dev) | Override only when relocating |
| `EMBEDDINGS_URL` | Full URL of the embeddings service | `http://embeddings_service:8000` (in-container) / `http://localhost:8002` (dev) | Override only when relocating |
| `EMBEDDINGS_DEV_PORT` | Embeddings host port in dev mode | `8002` | Exposed via `compose.dev.yml` |
| `QDRANT_DEV_PORT` | Qdrant host port in dev mode | `6333` | Exposed via `compose.dev.yml` |
| `START_HEALTH_TRIES` | Number of startup health probe attempts | `20` | See [Advanced Configuration](/advanced-topics/advanced-configuration.md#startup-health-tuning) |
| `START_HEALTH_INTERVAL` | Seconds between startup health probe attempts | `2` | See [Advanced Configuration](/advanced-topics/advanced-configuration.md#startup-health-tuning) |
| `FORCE_RUBY_REBUILD_NO_CACHE` | Force Ruby container rebuilds to run without Docker cache | `false` | See [Advanced Configuration](/advanced-topics/advanced-configuration.md#ruby-rebuild) |

## Install Options

These options control which optional packages are installed in the Python container. Changes require rebuilding the Python container via **Actions → Build Python Container**.

| Variable | Description | Required For | Default |
|----------|-------------|--------------|---------|
| `INSTALL_LATEX` | LaTeX toolchain (TeX Live, dvisvgm, CJK packages) | Syntax Tree, Concept Visualizer | `false` |
| `PYOPT_NLTK` | Natural Language Toolkit | NLP applications | `false` |
| `PYOPT_SPACY` | spaCy NLP library (v3.7.5) | Advanced NLP tasks | `false` |
| `PYOPT_GENSIM` | Topic modeling library | Text analysis | `false` |
| `PYOPT_LIBROSA` | Audio analysis library | Audio processing | `false` |
| `PYOPT_MEDIAPIPE` | Computer vision framework | Vision applications | `false` |
| `PYOPT_TRANSFORMERS` | Hugging Face Transformers | Deep learning NLP | `false` |
| `IMGOPT_IMAGEMAGICK` | ImageMagick image processing | Advanced image operations | `false` |

### Configuring Install Options

**Via GUI (Recommended):**
1. Open Electron app menu: **Actions → Install Options**
2. Toggle desired options
3. Click **Save**
4. Menu: **Actions → Build Python Container**

**Via Config File:**
```bash
# ~/monadic/config/env
INSTALL_LATEX=true
PYOPT_NLTK=true
PYOPT_LIBROSA=true
```

### Smart Build Caching

The build system automatically optimizes rebuild speed:

- **Options unchanged**: Fast rebuild using cache (~1-2 minutes)
- **Options changed**: Complete rebuild with `--no-cache` (~15-30 minutes)
- **Auto-restart**: Container automatically restarts after successful build

Previous build options are tracked in `~/monadic/log/python_build_options.txt`. The system compares current options with the previous build and uses `--no-cache` only when necessary to ensure reliability while maximizing speed.

### Important Notes

- LaTeX packages include full TeX Live, CJK language support, and dvisvgm for Japanese/Chinese/Korean text rendering
- NLTK and spaCy options install packages only; datasets/models must be downloaded separately via `pysetup.sh`
- Changes take effect immediately after rebuild; no manual container restart needed
- Failed builds preserve the current image (atomic updates)

## PDF Processing Settings

| Variable | Description | Default | Range |
|----------|-------------|---------|-------|
| `PDF_RAG_TOKENS` | Tokens per PDF chunk | `4000` | 500-8000 |
| `PDF_RAG_OVERLAP_LINES` | Line overlap between PDF chunks | `4` | 0-20 |

## Configuration Examples

### Basic Configuration
```bash
# ~/monadic/config/env

# Essential API Keys
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...

# Model Preferences
OPENAI_DEFAULT_MODEL=<model-id>

# UI Settings
ROUGE_THEME=github:light
```

### Advanced Configuration
```bash
# Web Search
TAVILY_API_KEY=tvly-...

# PDF Processing
PDF_RAG_TOKENS=6000
PDF_RAG_OVERLAP_LINES=6

# Development
DISTRIBUTED_MODE=server
MCP_SERVER_ENABLED=true
```

## Notes

- Boolean values can be set as `true`/`false` or `1`/`0`
- File paths should be absolute paths
- Some settings require container restart to take effect
- API keys are never displayed in the GUI for security
