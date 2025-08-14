# Configuration Reference

This page provides a comprehensive reference for all configuration options in Monadic Chat. Configuration can be set in the `~/monadic/config/env` file or through the GUI settings panel.

## Configuration Categories

- [API Keys](#api-keys)
- [Model Settings](#model-settings)
- [System Settings](#system-settings)
- [Voice Settings](#voice-settings)
- [Help System Settings](#help-system-settings)
- [Development Settings](#development-settings)
- [Container Settings](#container-settings)

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
| `OPENAI_DEFAULT_MODEL` | Default model for OpenAI apps | `gpt-4o-mini` | `gpt-4o` |
| `ANTHROPIC_DEFAULT_MODEL` | Default model for Claude apps | `claude-3-5-sonnet-20241022` | `claude-3-5-haiku-20241022` |
| `GEMINI_DEFAULT_MODEL` | Default model for Gemini apps | `gemini-2.0-flash-exp` | `gemini-1.5-pro` |
| `MISTRAL_DEFAULT_MODEL` | Default model for Mistral apps | `mistral-small-latest` | `mistral-large-latest` |
| `COHERE_DEFAULT_MODEL` | Default model for Cohere apps | `command-r` | `command-r-plus` |
| `DEEPSEEK_DEFAULT_MODEL` | Default model for DeepSeek apps | `deepseek-chat` | `deepseek-coder` |
| `PERPLEXITY_DEFAULT_MODEL` | Default model for Perplexity apps | `llama-3.1-sonar-small-128k-online` | `llama-3.1-sonar-large-128k-online` |
| `XAI_DEFAULT_MODEL` | Default model for Grok apps | `grok-2-latest` | `grok-beta` |
| `AI_USER_MODEL` | Model for AI-generated user messages | `gpt-4o-mini` | `gpt-4o` |
| `WEBSEARCH_MODEL` | Model for web search queries | `gpt-4o-mini` | `gpt-4o` |
| `REASONING_EFFORT` | Reasoning effort for supported models¹ | (model default) | `minimal`, `low`, `medium`, `high` |

¹ Applies to OpenAI reasoning models (o1, o3, gpt-5 series) and Gemini 2.5 models when using function calling

## System Settings

| Variable | Description | Default | Range/Options |
|----------|-------------|---------|---------------|
| `AI_USER_MAX_TOKENS` | Max tokens for AI-generated user messages | `2000` | 100-4000 |
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

## PDF Processing Settings

| Variable | Description | Default | Range |
|----------|-------------|---------|-------|
| `PDF_RAG_TOKENS` | Tokens per PDF chunk | `4000` | 500-8000 |
| `PDF_RAG_OVERLAP_LINES` | Line overlap between PDF chunks | `4` | 0-20 |

## Setting Priority

Configuration values are read in the following priority order:

1. **GUI Settings** (for supported options)
2. **CONFIG Hash** - Loaded from `~/monadic/config/env`
3. **System Defaults** - Hardcoded fallback values

## Usage Examples

### Basic Configuration
```bash
# ~/monadic/config/env

# Essential API Keys
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...

# Model Preferences
OPENAI_DEFAULT_MODEL=gpt-4o
AI_USER_MODEL=gpt-4o-mini

# UI Settings
FONT_SIZE=18
ROUGE_THEME=github
```

### Advanced Configuration
```bash
# Web Search and Voice
TAVILY_API_KEY=tvly-...
WEBSEARCH_MODEL=gpt-4o-mini
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