# Configuration Reference

This page lists the settings in `~/monadic/config/env`. Most of them are also in the **Settings** window (**Open → Settings**), which writes the same file.

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

The model an app uses is decided in this order (highest first):

1. **An explicit `model` in the app's `llm` block**
   - An app that names a model keeps it regardless of the settings below
2. **Environment variables** (`~/monadic/config/env`), such as `OPENAI_DEFAULT_MODEL`
3. **Provider defaults** (`providerDefaults` in `model_spec.js`)

### Example

For the OpenAI default model:
- If `OPENAI_DEFAULT_MODEL=<model-id>` is set in `~/monadic/config/env`, it is used
- Otherwise, the first chat model in `providerDefaults` for OpenAI is used

When the app starts, it writes the provider default into `~/monadic/config/env` for each `*_DEFAULT_MODEL` that is not set yet (except Ollama). From then on, the value in the file is used; to follow a newer default, delete the line or change the value.

> **Note**: The default models are listed in `providerDefaults` in `docker/services/ruby/public/js/monadic/model_spec.js`.

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

Values that do not start with `op://` are used as written.

- **Requirements**: the 1Password desktop app and the [1Password CLI](https://developer.1password.com/docs/cli/) (`op`) on the computer that runs the app, with **Settings → Developer → Integrate with 1Password CLI** turned on in the desktop app. This setting is the same on macOS, Windows and Linux. On Windows, turn on Windows Hello in 1Password first. On Linux, turn on **Settings → Security → Unlock using system authentication** first; it needs PolKit and a running PolKit authentication agent. The Snap and Flathub packages of 1Password do not support this integration. See [1Password's instructions](https://developer.1password.com/docs/cli/app-integration/). Session variables set by signing in manually in a terminal are not passed to the app when it is started from the desktop. The app looks for `op` on `PATH` and in the usual install locations.
- **When the references are read**: when you press Start, all of them in one `op` call, so 1Password normally asks for confirmation once. If that call fails, each reference is read on its own to find which one failed, and 1Password may ask again. Once every reference has been read, the values are kept until the app quits, and Restart and container restarts do not read them again; if some could not be read, the next Start or Restart tries again. Changing a reference in the settings reads the references again at the next Start.
- **Where the values go**: `~/monadic/config/env` keeps the references. The values are held in the app's memory and handed to the Ruby container through a memory-only mount (tmpfs); they are not written to a file, the container's settings or its environment, and they are not logged. A memory-only mount lives in the memory of the Docker virtual machine; whether that memory can be swapped to its disk depends on Docker Desktop.
- **When a reference cannot be read**: the console names the key and the reason (`op` not found, 1Password locked or the CLI not signed in, the confirmation declined, the item or field not found). That key stays unset until the next Start; other keys and features keep working. The reference itself is never sent to a provider as a key.
- **A Ruby container that is older than the app**: it cannot use the values, so the app does not hand them over and asks you to rebuild it (**Actions → Build Ruby Container**).
- **Development mode** (`rake server:debug`): the server runs on the host and reads the references itself with `op`.

## Model Settings

> **Note**: For default values, refer to `providerDefaults` in `docker/services/ruby/public/js/monadic/model_spec.js`. The table below shows variable names and usage only.

| Variable | Description | Usage Example |
|----------|-------------|---------------|
| `OPENAI_DEFAULT_MODEL` | Default model for OpenAI apps | `OPENAI_DEFAULT_MODEL=<model-id>` |
| `ANTHROPIC_DEFAULT_MODEL` | Default model for Claude apps | `ANTHROPIC_DEFAULT_MODEL=<model-id>` |
| `GEMINI_DEFAULT_MODEL` | Default model for Gemini apps | `GEMINI_DEFAULT_MODEL=<model-id>` |
| `MISTRAL_DEFAULT_MODEL` | Default model for Mistral apps | `MISTRAL_DEFAULT_MODEL=<model-id>` |
| `COHERE_DEFAULT_MODEL` | Default model for Cohere apps | `COHERE_DEFAULT_MODEL=<model-id>` |
| `DEEPSEEK_DEFAULT_MODEL` | Default model for DeepSeek apps | `DEEPSEEK_DEFAULT_MODEL=<model-id>` |
| `GROK_DEFAULT_MODEL` | Default model for Grok apps | `GROK_DEFAULT_MODEL=<model-id>` |
| `OLLAMA_DEFAULT_MODEL` | Default model for Ollama apps | `OLLAMA_DEFAULT_MODEL=<model-id>` |
| `TOKEN_COUNT_SOURCE` | How output tokens are counted in the usage display. Unset: counted with a local tokenizer. `provider_only` or `hybrid`: the count the provider reports | `TOKEN_COUNT_SOURCE=provider_only` |

### Model Selection in the UI :id=model-selection-in-the-ui

The **Model** dropdown shows a curated list of recommended models for the selected app. This list comes from the app's MDSL definition or the provider's default model set.

To see all available models from the provider, toggle the **All** switch next to the Model label. In "All" mode, models that are incompatible with the current app (e.g., models without tool support for apps that require tools) are automatically excluded. Your toggle preference is saved across sessions via a browser cookie.

## System Settings

| Variable | Description | Default | Options |
|----------|-------------|---------|---------|
| `UI_LANGUAGE` | Language of the interface | `en` | `en`, `ja`, `zh`, `ko`, `es`, `fr`, `de` |
| `BROWSER_MODE` | Where the web interface opens | `internal` | `internal` (the app's window), `external` (your browser) |
| `OPEN_AT_LOGIN` | Start Monadic Chat when you log in | `false` | `true`, `false` |
| `MENU_BAR_MODE` | Run from the menu bar or system tray | `false` | `true`, `false` |
| `MAX_STORED_MESSAGES` | Number of messages kept in the browser to restore a session | `1000` | A number |
| `ROUGE_THEME` | Syntax highlighting theme | `github:light` | See [available themes](../basic-usage/syntax-highlighting.md) |
| `PRIVACY_FILTER` | Start the Privacy container and allow the Privacy Filter | `true` | `true`, `false` |
| `PRIVACY_LANGS` | Languages the Privacy Filter loads, besides English | `en` | Comma-separated codes (`en`, `de`, `es`, `fr`, `it`, `ja`, `nl`, `pt`, `zh`) |
| `EXTRACTOR_SERVICE` | Use the Knowledge Base Quality Pack container | `false` | `true`, `false` |
| `EXTRACTOR_LANGS` | OCR languages of the Knowledge Base Quality Pack | `en,ja,zh,ko` | Comma-separated codes |
| `LIBRARY_IMPORT_MAX_BYTES` | Largest file the Knowledge Base imports, in bytes | `104857600` (100 MiB) | A number |
| `GEMINI_MAX_INLINE_PDF_MB` | Largest PDF sent to Gemini inline, in MB | `20` | A number |

> **Note**: When the context size setting is on in the web interface, the number of stored messages is also limited by it.

## Voice Settings

| Variable | Description | Default | Range/Options |
|----------|-------------|---------|---------------|
| `TTS_DICT_PATH` | Path to a TTS pronunciation dictionary CSV. Set it in the Settings window ("TTS Dictionary File Path"); the file is copied to `~/monadic/config/TTS_DICT.csv`, which the server reads | (optional) | File path |
| `AUTO_TTS_MAX_BYTES` | Most text, in bytes, that Auto Speech reads aloud after a response; longer text is cut at a sentence boundary | `400` | A number |

> **Note**: The speech-to-text model is not configured via environment variables. Select it in the **Speech** panel of the web UI; the choice is kept in a browser cookie.

## Help System Settings

| Variable | Description | Default |
|----------|-------------|---------|
| `HELP_CHUNKS_PER_RESULT` | Number of chunks returned for each document in a search result | `3` |
| `HELP_CHUNK_SIZE` | Characters per documentation chunk, used only when building the help data (`rake help:build`) | `3000` |
| `HELP_OVERLAP_SIZE` | Characters shared by adjacent chunks, used only when building the help data | `500` |

## Development Settings

| Variable | Description | Default | Options |
|----------|-------------|---------|---------|
| `MCP_SERVER_ENABLED` | Enable the Model Context Protocol server | `false` | `true`, `false` |
| `MCP_SERVER_PORT` | Port of the MCP server. In the packaged app the published port is fixed at 3100, so change this only in development mode | `3100` | A port number |
| `CONDUIT_TOKEN_BUDGET` | Token budget for MCP tools that spend provider tokens | `1000000` | A number |
| `CONDUIT_AGENT_WALL_CLOCK` | Time limit of the MCP `monadic_agent` tool, in seconds | `300` | A number |
| `EXTRA_LOGGING` | Enable detailed logging to `~/monadic/log/extra.log` | `false` | `true`, `false` |

## Container Settings

| Variable | Description | Default | Note |
|----------|-------------|---------|------|
| `START_HEALTH_TRIES` | Number of startup health probe attempts | `20` | See [Advanced Configuration](/advanced-topics/advanced-configuration.md#startup-health-tuning) |
| `START_HEALTH_INTERVAL` | Seconds between startup health probe attempts | `2` | See [Advanced Configuration](/advanced-topics/advanced-configuration.md#startup-health-tuning) |
| `AUTO_REFRESH_RUBY_ON_HEALTH_FAIL` | Rebuild the Ruby container once when it is unhealthy at Start | `true` | See [Advanced Configuration](/advanced-topics/advanced-configuration.md#startup-health-tuning) |
| `FORCE_RUBY_REBUILD_NO_CACHE` | Force Ruby container rebuilds to run without Docker cache | `false` | See [Advanced Configuration](/advanced-topics/advanced-configuration.md#ruby-rebuild) |
| `QDRANT_URL` | Full URL of the Qdrant service | `http://qdrant_service:6333` (in-container) / `http://localhost:6333` (development mode) | Change only when the service is elsewhere |
| `EMBEDDINGS_URL` | Full URL of the embeddings service | `http://embeddings_service:8000` (in-container) / `http://localhost:8002` (development mode) | Change only when the service is elsewhere |

## Install Options

These options choose optional packages for the Python container. After changing them, rebuild it with **Actions → Build Python Container**. The Privacy Filter languages and the Knowledge Base Quality Pack, which are in the same Install Options panel, are in [System Settings](#system-settings).

| Variable | Description | Required For | Default |
|----------|-------------|--------------|---------|
| `INSTALL_LATEX` | LaTeX (a minimal set for diagrams, with CJK support and dvisvgm) | Syntax Tree, Concept Visualizer | `false` |
| `PYOPT_NLTK` | Natural Language Toolkit | NLP applications | `false` |
| `PYOPT_SPACY` | spaCy NLP library | Advanced NLP tasks | `false` |
| `PYOPT_GENSIM` | Topic modeling library | Text analysis | `false` |
| `PYOPT_LIBROSA` | Music Analysis: librosa and madmom, with soundfile, midiutil and pretty_midi | Music Lab, Music Analyst | `false` |
| `PYOPT_MEDIAPIPE` | Computer vision framework (CPU) | Vision applications | `false` |
| `PYOPT_TRANSFORMERS` | Hugging Face Transformers and Accelerate (CPU) | Deep learning NLP | `false` |
| `IMGOPT_IMAGEMAGICK` | ImageMagick image processing | Advanced image operations | `false` |

### Configuring Install Options

**In the Settings window (recommended):**
1. Choose **Actions → Install Options**; the Settings window opens at Install Options
2. Turn on the options you want
3. Click **Save**
4. Choose **Actions → Build Python Container**

**In the config file:**
```bash
# ~/monadic/config/env
INSTALL_LATEX=true
PYOPT_NLTK=true
PYOPT_LIBROSA=true
```

### Smart Build Caching

- **No options and no `pysetup.sh`**: the prebuilt Python image is downloaded instead of built
- **Some options on**: the image is built on your computer, using the prebuilt image as a cache, so only the layers of the enabled options are built
- **`~/monadic/config/pysetup.sh` exists**: the image is always built on your computer, and the script runs at the end of the build
- **After a successful build**: a running Python container is created again from the new image; otherwise the new image is used at the next Start

The options of the last build are written to `~/monadic/log/python_build_options.txt`.

### Important Notes

- NLTK and spaCy options install packages only; download datasets and models in `~/monadic/config/pysetup.sh`, which runs at the end of the Python image build
- A failed build keeps the current image

## PDF Processing Settings

These settings apply to PDFs that the MCP server imports into the Knowledge Base. PDFs imported in the web interface use their own fixed chunk sizes.

| Variable | Description | Default |
|----------|-------------|---------|
| `PDF_RAG_TOKENS` | Tokens per PDF chunk | `4000` |
| `PDF_RAG_OVERLAP_LINES` | Line overlap between PDF chunks | `4` |

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

# Development
MCP_SERVER_ENABLED=true
```

## Notes

- Write on/off settings as `true` or `false`. Other spellings (such as `1` or `0`) are read as numbers by the server, not as on and off
- File paths should be absolute paths
- Some settings require a restart of Monadic Chat to take effect
- API keys are never displayed in the GUI
