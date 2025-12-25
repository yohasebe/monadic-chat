# Integration Tests

This directory contains integration tests that verify the interaction between Monadic Chat components, including Docker containers and API providers.

## Prerequisites

1. Docker must be installed and running
2. Monadic Chat containers must be built and running:
   ```bash
   ./docker/monadic.sh build
   ./docker/monadic.sh start
   ```
3. API keys configured in `~/monadic/config/env` for API tests

## Test Structure

### Provider Matrix Tests (`provider_matrix/`)

The main comprehensive test suite for all providers and apps:

```bash
# Run with specific providers
PROVIDERS=openai,anthropic RUN_API=true bundle exec rspec spec/integration/provider_matrix/all_providers_all_apps_spec.rb

# Run all configured providers
RUN_API=true bundle exec rspec spec/integration/provider_matrix/all_providers_all_apps_spec.rb
```

**Features:**
- Tests all provider × app combinations (OpenAI, Anthropic, Gemini, xAI, Mistral, Cohere, DeepSeek, Perplexity)
- Uses ResponseEvaluator for AI-based response validation
- Validates both text responses and tool calls
- Detects runtime errors in responses

### Docker Infrastructure Tests

- `docker_infrastructure_spec.rb` - Container communication and health checks
- `flask_app_client_docker_spec.rb` - Python Flask container integration

### Feature-Specific Tests

- `jupyter_*.rb` - Jupyter Notebook functionality
- `voice_*.rb` - Voice chat and TTS/STT integration
- `selenium_*.rb` - Browser automation tests
- `pgvector_*.rb` - Vector database integration
- `websocket_*.rb` - WebSocket communication

### API Tests (`api_media/`)

Media generation tests (requires `RUN_MEDIA=true`):
- `image_generation_all_providers_spec.rb`
- `video_generation_openai_spec.rb`
- `voice_pipeline_spec.rb`

## Running Tests

### Quick Start

```bash
cd docker/services/ruby

# Run all integration tests (no API calls)
bundle exec rspec spec/integration/

# Run with API calls
RUN_API=true bundle exec rspec spec/integration/

# Run provider matrix only
PROVIDERS=openai RUN_API=true bundle exec rspec spec/integration/provider_matrix/
```

### Using Rake Tasks

```bash
# Standard integration test run
rake spec_integration

# With specific providers
rake test:profile[ci]
```

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `RUN_API` | Enable API tests | `false` |
| `PROVIDERS` | Comma-separated provider list | all configured |
| `RUN_MEDIA` | Enable media generation tests | `false` |
| `DEBUG` | Enable debug output | `false` |

## Writing New Integration Tests

### Provider Matrix Tests

Add new apps to `APP_TEST_CONFIGS` in `all_providers_all_apps_spec.rb`:

```ruby
'MyNewApp' => {
  prompt: 'Test prompt for my app.',
  expectation: 'The AI responded appropriately'
}
```

### Docker Integration Tests

Always check if Docker is available:

```ruby
before(:all) do
  skip "Docker tests require Docker environment" unless docker_available?
end
```

### Using ResponseEvaluator

For AI-based response validation:

```ruby
result = RE.evaluate(
  response: response_text,
  expectation: 'The AI provided helpful information',
  prompt: original_prompt,
  criteria: 'Response quality'
)
expect(result.match).to be(true)
```

## Troubleshooting

### Tests are skipped
- Ensure Docker is running: `docker ps`
- Check API keys: `grep API_KEY ~/monadic/config/env`
- Verify `RUN_API=true` is set for API tests

### Provider not found
- Check provider is configured in env file
- Verify model availability with provider

### Timeout errors
- Increase timeout for slow providers
- Check network connectivity
- Consider rate limiting
