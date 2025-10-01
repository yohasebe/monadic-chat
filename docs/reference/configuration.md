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

1. **Environment Variables** (`~/monadic/config/env`)
   - User-defined settings take highest priority
   - Override all other configuration sources

2. **System Defaults** (`config/system_defaults.json`)
   - Provider-specific default models and settings
   - Applied when no environment variable is set

3. **Hardcoded Defaults**
   - Built-in fallback values in the code
   - Used as last resort when neither ENV nor system_defaults provide a value

### Example

For the OpenAI default model:
- If `OPENAI_DEFAULT_MODEL=gpt-4.1-mini` is set in `~/monadic/config/env`, it will be used
- Otherwise, the value from `system_defaults.json` (`gpt-4.1`) will be used
- If neither exists, the hardcoded default in the application will be applied

## API Keys

| Variable | Description | Required | Example |
|----------|-------------|----------|---------|
| `OPENAI_API_KEY` | OpenAI API key for GPT models | Yes (for OpenAI apps) | `sk-...` |
| `ANTHROPIC_API_KEY` | Anthropic API key for Claude models | Yes (for Claude apps) | `sk-ant-...` |
| `GEMINI_API_KEY` | Google API key for Gemini models | Yes (for Gemini apps) | `AIza...` |
| `MISTRAL_API_KEY` | Mistral AI API key | Yes (for Mistral apps) | `...` |
| `COHERE_API_KEY` | Cohere API key | Yes (for Cohere apps) | `...` |
| `DEEPSEEK_API_KEY` | DeepSeek API key | Yes (for DeepSeek apps) | `...` |
| `PERPLEXITY_API_KEY` | Perplexity API key | Yes (for Perplexity apps) | `pplx-...` |
| `XAI_API_KEY` | xAI API key for Grok models | Yes (for Grok apps) | `xai-...` |
| `TAVILY_API_KEY` | Tavily API key for web search | No | `tvly-...` |

## Model Settings

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `OPENAI_DEFAULT_MODEL` | Default model for OpenAI apps | `gpt-4.1` | `gpt-4.1-mini` |
| `ANTHROPIC_DEFAULT_MODEL` | Default model for Claude apps | `claude-sonnet-4-20250514` | `claude-3.5-haiku-20241022` |
| `TOKEN_COUNT_SOURCE` | Token counting source policy | `python_only` | `provider_only` / `hybrid` |
| `GEMINI_DEFAULT_MODEL` | Default model for Gemini apps | `gemini-2.5-flash` | `gemini-1.5-pro` |
| `MISTRAL_DEFAULT_MODEL` | Default model for Mistral apps | `mistral-large-latest` | `magistral-medium-2509` |
| `COHERE_DEFAULT_MODEL` | Default model for Cohere apps | `command-a-03-2025` | `command-a-reasoning-08-2025` |
| `DEEPSEEK_DEFAULT_MODEL` | Default model for DeepSeek apps | `deepseek-chat` | `deepseek-coder` |
| `PERPLEXITY_DEFAULT_MODEL` | Default model for Perplexity apps | `sonar-reasoning-pro` | `sonar-reasoning` |
| `XAI_DEFAULT_MODEL` | Default model for Grok apps | `grok-4-fast-reasoning` | `grok-4-fast-non-reasoning` |

## System Settings

| Variable | Description | Default | Range/Options |
|----------|-------------|---------|---------------|
| `FONT_SIZE` | Base font size for the interface | `16` | 10-24 |
| `AUTONOMOUS_ITERATIONS` | Number of autonomous mode iterations | `2` | 1-10 |
| `MAX_CHAR_COUNT` | Maximum message length | `200000` | 1000-500000 |
| `PDF_BOLD_FONT_PATH` | Path to bold font for PDF generation | (optional) | File path |
| `PDF_STANDARD_FONT_PATH` | Path to standard font for PDF generation | (optional) | File path |
| `ROUGE_THEME` | Syntax highlighting theme | `monokai.sublime` | See [available themes](../basic-usage/syntax-highlighting.md) |

## Voice Settings

| Variable | Description | Default | Options |
|----------|-------------|---------|---------|
| `STT_MODEL` | Speech-to-text model | `gpt-4o-transcribe` | `gpt-4o-transcribe`, `gpt-4o-mini-transcribe`, `whisper-1` |
| `TTS_DICT_PATH` | Path to TTS pronunciation dictionary | (optional) | File path |
| `TTS_DICT_DATA` | Inline TTS pronunciation data | (optional) | CSV format |

## Help System Settings

| Variable | Description | Default | Range |
|----------|-------------|---------|-------|
| `HELP_CHUNK_SIZE` | Characters per documentation chunk | `3000` | 1000-8000 |
| `HELP_OVERLAP_SIZE` | Character overlap between chunks | `500` | 100-2000 |
| `HELP_EMBEDDINGS_BATCH_SIZE` | Batch size for embedding API calls | `50` | 1-100 |
| `HELP_CHUNKS_PER_RESULT` | Number of chunks returned per search | `3` | 1-10 |

## Development Settings

| Variable | Description | Default | Options |
|----------|-------------|---------|---------|
| `DISTRIBUTED_MODE` | Enable multi-user server mode | `false` | `true`, `false` |
| `SESSION_SECRET` | Secret key for session management | (generated) | Any string |
| `MCP_SERVER_ENABLED` | Enable Model Context Protocol server | `false` | `true`, `false` |
| `PYTHON_PORT` | Port for Python container services | `5070` | 1024-65535 |
| `ALLOW_JUPYTER_IN_SERVER_MODE` | Enable Jupyter in server mode | `false` | `true`, `false` |

## Container Settings

| Variable | Description | Default | Note |
|----------|-------------|---------|------|
| `OLLAMA_AVAILABLE` | Ollama container availability | (auto-detected) | Set by system |
| `POSTGRES_HOST` | PostgreSQL host | `monadic-chat-pgvector-container` | For Docker networking |
| `POSTGRES_PORT` | PostgreSQL port | `5432` | Standard PostgreSQL port |
| `POSTGRES_USER` | PostgreSQL user | `postgres` | Database user |
| `POSTGRES_PASSWORD` | PostgreSQL password | `postgres` | Database password |

## Install Options

These options control which optional packages are installed in the Python container. Changes require rebuilding the Python container via **Actions → Build Python Container**.

| Variable | Description | Required For | Default |
|----------|-------------|--------------|---------|
| `INSTALL_LATEX` | LaTeX toolchain (TeX Live, dvisvgm, CJK packages) | Syntax Tree, Concept Visualizer | `false` |
| `PYOPT_NLTK` | Natural Language Toolkit | NLP applications | `false` |
| `PYOPT_SPACY` | spaCy NLP library (v3.7.5) | Advanced NLP tasks | `false` |
| `PYOPT_SCIKIT` | scikit-learn machine learning library | ML applications | `false` |
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
OPENAI_DEFAULT_MODEL=gpt-4.1

# UI Settings
FONT_SIZE=18
ROUGE_THEME=github
```

### Advanced Configuration
```bash
# Web Search and Voice
TAVILY_API_KEY=tvly-...
STT_MODEL=whisper-1

# PDF Processing
PDF_RAG_TOKENS=6000
PDF_RAG_OVERLAP_LINES=6

# Development
DISTRIBUTED_MODE=true
MCP_SERVER_ENABLED=true
```

## Notes

- Boolean values can be set as `true`/`false` or `1`/`0`
- File paths should be absolute paths
- Some settings require container restart to take effect
- API keys are never displayed in the GUI for security
