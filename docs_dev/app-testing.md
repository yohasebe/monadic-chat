# App Testing Framework

## Overview

The Monadic Chat app testing framework provides comprehensive testing for all applications with special handling for expensive API operations like image and video generation.

## Test Modes

### Standard Mode (Default)

Runs all tests except those that incur significant API costs:

```bash
# Using rake default task
rake

# Explicitly run app tests
rake apps:test

# Individual test categories
rake apps:test_core
rake apps:test_productivity
rake apps:test_research
rake apps:test_specialized
```

### Full Mode (With Expensive Operations)

Includes tests for image and video generation:

```bash
# Run all tests including expensive operations
rake apps:test_with_expensive

# This will prompt for confirmation and run:
# - Image generation tests (OpenAI, Gemini, Grok)
# - Video generation tests (Gemini Veo)
# - Other expensive API operations
```

### Smoke Test Mode

Quick validation that all apps load correctly:

```bash
rake apps:smoke
```

## Test Categories

### Core Applications
- Chat
- Chat Plus (Monadic mode)

### Productivity Applications
- Code Interpreter
- Jupyter Notebook
- PDF Navigator
- Coding Assistant

### Creative Applications (Expensive)
- Image Generator (OpenAI, Gemini, Grok)
- Video Generator (Gemini Veo)
- Mermaid Grapher

### Research Applications
- Research Assistant
- Visual Web Explorer
- Wikipedia

### Specialized Applications
- Voice Chat
- Content Reader
- Second Opinion
- Video Describer
- Language Practice

## Provider Compatibility Testing

Test apps with different providers:

```bash
# Test all configured providers
rake apps:test_providers

# Test specific provider
rake spec_e2e:code_interpreter_provider[openai]
```

## Test Reports

Generate test coverage report:

```bash
rake apps:report
```

This shows:
- Total number of apps
- E2E test coverage
- Apps without dedicated tests

## Environment Variables

### Controlling Test Behavior

```bash
# Skip expensive operations (default)
SKIP_EXPENSIVE=true rake apps:test

# Include expensive operations
SKIP_EXPENSIVE=false rake apps:test_all

# Run only smoke tests
SMOKE_TEST=true rake apps:smoke
```

### API Key Requirements

Tests will automatically skip providers without configured API keys:

```bash
# Required for core tests
OPENAI_API_KEY=...
ANTHROPIC_API_KEY=...
GEMINI_API_KEY=...

# Optional for extended tests
MISTRAL_API_KEY=...
COHERE_API_KEY=...
PERPLEXITY_API_KEY=...
DEEPSEEK_API_KEY=...
XAI_API_KEY=...
```

## Service Dependencies

The test framework automatically manages required services:

1. **PostgreSQL (pgvector)** - For vector search tests
2. **Python container** - For code execution tests
3. **Selenium container** - For web automation tests
4. **Ruby server** - Main application server

Services are started automatically and kept running unless `KEEP_PGVECTOR=false` is set.

## Writing New App Tests

### 1. Create E2E Test File

Create a test file in `docker/services/ruby/spec/e2e/`:

```ruby
# spec/e2e/my_new_app_spec.rb
require 'e2e_helper'

RSpec.describe "My New App E2E Tests" do
  include E2ETestHelpers
  
  before(:all) do
    setup_e2e_test
    ensure_service_running
  end
  
  describe "Basic functionality" do
    it "loads the app successfully" do
      # Test implementation
    end
  end
  
  describe "API operations" do
    context "when expensive operations are enabled" do
      before do
        skip "Expensive operations disabled" if ENV['SKIP_EXPENSIVE'] == 'true'
      end
      
      it "generates content" do
        # Expensive API test
      end
    end
  end
end
```

### 2. Add to Rake Task

Update the appropriate test category in `Rakefile`:

```ruby
task :test_specialized do
  # ...
  sh "bundle exec rspec spec/e2e/my_new_app_spec.rb --format documentation"
end
```

### 3. Document Provider Requirements

Update `docs/reference/provider-limitations.md` if the app has specific provider requirements.

## Best Practices

1. **Always skip expensive tests by default** - Use `ENV['SKIP_EXPENSIVE']` guards
2. **Mock expensive operations in unit tests** - Save real API calls for E2E tests
3. **Test provider compatibility** - Ensure apps work with their declared providers
4. **Use smoke tests for quick validation** - Helps catch loading/syntax errors early
5. **Document API costs** - Add comments about expected costs for expensive tests

## Troubleshooting

### Tests Failing Due to Missing Services

```bash
# Manually start all services
rake apps:start_services

# Check service status
docker ps | grep monadic-chat
```

### API Rate Limits

If hitting rate limits, use environment variables to control test parallelization:

```bash
# Run tests sequentially
PARALLEL_TESTS=false rake apps:test
```

### Debugging Failed Tests

```bash
# Run with extra logging
EXTRA_LOGGING=true rake apps:test

# Run specific test with debugging
DEBUG=true bundle exec rspec spec/e2e/specific_app_spec.rb
```

## CI/CD Integration

For CI environments, use standard mode to avoid API costs:

```yaml
# .github/workflows/test.yml
- name: Run App Tests
  env:
    SKIP_EXPENSIVE: true
  run: rake apps:test
```

For nightly builds with full testing:

```yaml
# .github/workflows/nightly.yml
- name: Run Full App Tests
  env:
    SKIP_EXPENSIVE: false
    # Add API keys as secrets
  run: rake apps:test_all
```