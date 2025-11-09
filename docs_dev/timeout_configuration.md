# API Timeout Configuration

## Overview

Monadic Chat allows customization of HTTP timeout settings for each AI provider through environment variables. This enables users to adjust timeouts based on their network conditions, query complexity, and provider-specific requirements.

## Default Timeout Values

All providers are configured with the following default timeouts:

| Provider | OPEN_TIMEOUT | READ_TIMEOUT | WRITE_TIMEOUT |
|----------|--------------|--------------|---------------|
| OpenAI | 20 seconds | 600 seconds (10 min) | 120 seconds |
| Claude (Anthropic) | 10 seconds | 600 seconds (10 min) | 120 seconds |
| Gemini | 10 seconds | 600 seconds (10 min) | - |
| Cohere | 10 seconds | 600 seconds (10 min) | 120 seconds |
| DeepSeek | 10 seconds | 600 seconds (10 min) | 120 seconds |
| Mistral | 5 seconds | 600 seconds (10 min) | 120 seconds |
| Perplexity | 5 seconds | 600 seconds (10 min) | 120 seconds |
| Grok (XAI) | 20 seconds | 600 seconds (10 min) | 120 seconds |

## Environment Variables

Timeout values can be customized by adding the following variables to `~/monadic/config/env`:

### OpenAI
```bash
OPENAI_OPEN_TIMEOUT=20
OPENAI_READ_TIMEOUT=600
OPENAI_WRITE_TIMEOUT=120
```

### Claude (Anthropic)
```bash
CLAUDE_OPEN_TIMEOUT=10
CLAUDE_READ_TIMEOUT=600
CLAUDE_WRITE_TIMEOUT=120
```

### Gemini
```bash
GEMINI_OPEN_TIMEOUT=10
GEMINI_READ_TIMEOUT=600
```

### Cohere
```bash
COHERE_OPEN_TIMEOUT=10
COHERE_READ_TIMEOUT=600
COHERE_WRITE_TIMEOUT=120
```

### DeepSeek
```bash
DEEPSEEK_OPEN_TIMEOUT=10
DEEPSEEK_READ_TIMEOUT=600
DEEPSEEK_WRITE_TIMEOUT=120
```

### Mistral
```bash
MISTRAL_OPEN_TIMEOUT=5
MISTRAL_READ_TIMEOUT=600
MISTRAL_WRITE_TIMEOUT=120
```

### Perplexity
```bash
PERPLEXITY_OPEN_TIMEOUT=5
PERPLEXITY_READ_TIMEOUT=600
PERPLEXITY_WRITE_TIMEOUT=120
```

### Grok (XAI)
```bash
GROK_OPEN_TIMEOUT=20
GROK_READ_TIMEOUT=600
GROK_WRITE_TIMEOUT=120
```

## Timeout Types

### OPEN_TIMEOUT
Time allowed to establish a connection to the API server.
- **Default**: 5-20 seconds (varies by provider)
- **Recommendation**: Keep at default unless experiencing connection issues

### READ_TIMEOUT
Maximum time to wait for API response after the request is sent. This is the most important timeout for user experience.
- **Default**: 600 seconds (10 minutes)
- **Use Cases**:
  - Standard queries: 600 seconds is sufficient
  - Complex reasoning tasks: May need extension (e.g., 900-1200 seconds)
  - Simple queries: Can be reduced (e.g., 300 seconds)

### WRITE_TIMEOUT
Time allowed to send request data to the API server.
- **Default**: 120 seconds
- **Recommendation**: Keep at default unless uploading large files

## Special Timeout Handling

### OpenAI Responses API
The Responses API (used for GPT-5-Codex and o3-pro) automatically uses extended timeout:
- **READ_TIMEOUT**: 1200 seconds (20 minutes)
- This override is applied programmatically and cannot be changed via env variables

### OpenAI Reasoning Models
Reasoning models with `medium` or `high` effort levels automatically use extended timeout:
- **READ_TIMEOUT**: 600 seconds (10 minutes)
- This ensures reasoning tasks complete without timing out

## Troubleshooting

### Timeout Errors
If you experience timeout errors:

1. **Increase READ_TIMEOUT**: Most timeouts occur during response reading
   ```bash
   OPENAI_READ_TIMEOUT=900  # Increase to 15 minutes
   ```

2. **Check Network**: Slow network may require higher OPEN_TIMEOUT
   ```bash
   OPENAI_OPEN_TIMEOUT=30  # Increase connection timeout
   ```

3. **Provider-Specific Issues**: Some providers may be slower during peak hours
   - Consider increasing timeout for specific providers
   - Check provider status pages for ongoing issues

### Performance Considerations

**Short Timeouts (< 300 seconds)**:
- ✅ Faster failure detection
- ✅ Better for simple queries
- ❌ May interrupt complex tasks
- ❌ Poor user experience with reasoning models

**Long Timeouts (> 900 seconds)**:
- ✅ Supports complex reasoning tasks
- ✅ Better for large file processing
- ❌ Slower failure detection
- ❌ May hide API issues

**Recommended**: Keep default 600 seconds (10 minutes) unless specific needs require adjustment.

## Example Configuration

Example `~/monadic/config/env` with custom timeouts:

```bash
# API Keys (required)
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
GEMINI_API_KEY=AI...

# Custom Timeouts (optional)
# Only set these if you need different values from defaults

# Increase timeout for OpenAI reasoning tasks
OPENAI_READ_TIMEOUT=900

# Reduce timeout for Gemini (if experiencing hanging)
GEMINI_READ_TIMEOUT=300

# Increase timeout for Perplexity web search
PERPLEXITY_READ_TIMEOUT=900
```

## Implementation Details

Timeout constants are defined in each provider helper module:
- `lib/monadic/adapters/vendors/openai_helper.rb`
- `lib/monadic/adapters/vendors/claude_helper.rb`
- `lib/monadic/adapters/vendors/gemini_helper.rb`
- etc.

The pattern used:
```ruby
READ_TIMEOUT = (CONFIG["PROVIDER_READ_TIMEOUT"]&.to_i || 600)
```

This allows:
1. Environment variable override via CONFIG hash
2. Fallback to default value (600 seconds)
3. Type safety with `to_i` conversion
