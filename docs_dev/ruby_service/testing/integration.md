# Integration Tests

This document describes the integration test structure for Monadic Chat's Ruby service.

## Test Location

Integration tests are located in `docker/services/ruby/spec/integration/`.

## Test Structure

### Provider Matrix Tests (`provider_matrix/`)

The main comprehensive test suite for validating all providers and apps:

**File:** `all_providers_all_apps_spec.rb`

**Purpose:**
- Tests all provider × app combinations systematically
- Validates response quality using AI-based evaluation (ResponseEvaluator)
- Verifies tool calling functionality across all providers
- Detects runtime errors in responses

**Supported Providers:**
- OpenAI, Anthropic, Gemini, xAI/Grok, Mistral, Cohere, DeepSeek, Perplexity, Ollama

**Running:**
```bash
# All providers
RUN_API=true bundle exec rspec spec/integration/provider_matrix/

# Specific providers
PROVIDERS=openai,anthropic RUN_API=true bundle exec rspec spec/integration/provider_matrix/

# With debug output
DEBUG=true PROVIDERS=openai RUN_API=true bundle exec rspec spec/integration/provider_matrix/
```

### Docker Infrastructure Tests

| File | Description |
|------|-------------|
| `docker_infrastructure_spec.rb` | Container communication, health checks |
| `flask_app_client_docker_spec.rb` | Python Flask container integration |
| `code_interpreter_*.rb` | Code execution in containers |

### Feature-Specific Tests

| Category | Files | Description |
|----------|-------|-------------|
| Jupyter | `jupyter_*.rb` | Notebook creation, execution, advanced features |
| Voice | `voice_*.rb` | TTS/STT integration, voice chat |
| Web | `selenium_*.rb` | Browser automation, web scraping |
| Database | `pgvector_*.rb`, `embeddings_*.rb` | Vector DB, embeddings |
| WebSocket | `websocket_*.rb` | Real-time communication |

### API Tests (`api_media/`)

Media generation tests requiring external API calls:

| File | Description |
|------|-------------|
| `image_generation_all_providers_spec.rb` | Image generation across providers |
| `video_generation_openai_spec.rb` | Video generation (OpenAI Sora) |
| `voice_pipeline_spec.rb` | Voice synthesis pipeline |

**Note:** Requires `RUN_MEDIA=true` environment variable.

## ResponseEvaluator

The `ResponseEvaluator` utility provides AI-based response validation:

```ruby
require_relative '../../../lib/monadic/utils/response_evaluator'

RE = Monadic::Utils::ResponseEvaluator

result = RE.evaluate(
  response: "The capital of France is Paris.",
  expectation: "The AI correctly identified Paris as the capital",
  prompt: "What is the capital of France?",
  criteria: "Factual accuracy"
)

expect(result.match).to be(true)
expect(result.confidence).to be >= 0.7
```

**Features:**
- AI-powered response validation (uses OpenAI API)
- Confidence scoring
- Batch evaluation for multiple expectations
- Context-aware evaluation

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `RUN_API` | Enable API-dependent tests | `false` |
| `PROVIDERS` | Comma-separated list of providers to test | all configured |
| `RUN_MEDIA` | Enable media generation tests | `false` |
| `DEBUG` | Enable debug output | `false` |
| `OPENAI_API_KEY` | Required for ResponseEvaluator | - |

## Adding New Tests

### Adding Apps to Provider Matrix

Edit `APP_TEST_CONFIGS` in `all_providers_all_apps_spec.rb`:

```ruby
APP_TEST_CONFIGS = {
  # ...existing apps...
  'MyNewApp' => {
    prompt: 'Test prompt for my app.',
    expectation: 'The AI responded with relevant information',
    skip_ai_evaluation: false  # Set true for process-oriented apps
  }
}
```

### Adding Providers

1. Add to `PROVIDER_CONFIG`:
```ruby
PROVIDER_CONFIG = {
  # ...existing providers...
  'newprovider' => { suffix: 'NewProvider', timeout: 60 }
}
```

2. Implement tool support in `provider_matrix_helper.rb`

3. Add provider to helper's tool support list

## Best Practices

1. **Use permissive expectations** - Focus on "app works" not "response quality"
2. **Handle timeouts gracefully** - Skip rather than fail for infrastructure issues
3. **Check for runtime errors** - Pattern match for Ruby exceptions in responses
4. **Use ResponseEvaluator** - For semantic validation instead of string matching
