# Monadic Chat Ruby Testing

This directory contains tests for the Ruby components of Monadic Chat.

## Test Structure

The test suite is organized as follows:

- `spec_helper.rb` - Common setup and helper utilities for all tests
- `*_spec.rb` - Individual test files for different components
- `monadic_app_command_mock.rb` - Mock implementation of MonadicApp for testing command execution

## Shared Testing Utilities

We've implemented several shared testing utilities to improve code reuse and consistency:

1. **TestHelpers Module** - Common helper methods for all tests:
   - `mock_successful_response` - Creates a standard successful HTTP response
   - `mock_error_response` - Creates a standard error HTTP response
   - `mock_status` - Creates a standard OpenStruct for command status
   - `stub_http_client` - Sets up standard HTTP client mocks

2. **Shared Examples**:
   - `"a vendor API helper"` - Standard tests for all vendor API helpers
   - `"command execution"` - Standard tests for command execution scenarios

## Key Components Tested

1. **Command Execution**
   - `bash_command_helper_spec.rb` - Tests for the MonadicHelper module that provides command execution functionality
   - `monadic_app_command_spec.rb` - Tests for the MonadicApp class methods related to command execution

2. **Text Processing**
   - `pdf_text_extractor_spec.rb` - Tests for PDF extraction
   - `string_utils_spec.rb` - Tests for string utility functions

3. **API Integrations**
   - `interaction_utils_spec.rb` - Tests for API interactions
   - `flask_app_client_spec.rb` - Tests for Flask API client
   - `embeddings_spec.rb` - Tests for vector embeddings
   - `websocket_spec.rb` - Tests for WebSocket functionality

4. **Vendor Helpers**
   - `claude_helper_spec.rb` - Tests for Claude API integration
   - `cohere_helper_spec.rb` - Tests for Cohere API integration
   - `gemini_helper_spec.rb` - Tests for Google Gemini API integration
   - `openai_helper_spec.rb` - Tests for OpenAI API integration
   - `mistral_helper_spec.rb` - Tests for Mistral API integration
   - `perplexity_helper_spec.rb` - Tests for Perplexity API integration

5. **Thinking/Reasoning Process Display**
   - `openai_reasoning_spec.rb` - Tests for OpenAI o1/o3 reasoning content extraction
   - `claude_thinking_spec.rb` - Tests for Claude Sonnet 4.5+ thinking content blocks
   - `deepseek_reasoning_spec.rb` - Tests for DeepSeek reasoner/r1 reasoning content
   - `gemini_thinking_spec.rb` - Tests for Gemini 2.0 thinking mode with thought parts
   - `grok_reasoning_spec.rb` - Tests for Grok reasoning content extraction
   - `mistral_reasoning_spec.rb` - Tests for Mistral reasoning content extraction
   - `cohere_thinking_spec.rb` - Tests for Cohere thinking content (JSON format)
   - `perplexity_thinking_spec.rb` - Tests for Perplexity dual-format thinking (JSON + tags)

## Test Design Principles

1. **Isolation** - Tests use namespaces to avoid conflicts between different test files
2. **Mocking** - Dependencies are mocked to avoid external service calls
3. **Shared Utilities** - Common test code is extracted into helper modules and shared examples
4. **Comprehensive Coverage** - Edge cases and error conditions are tested

## Running Tests

Run all tests:
```
bundle exec rspec spec
```

Run a specific test file:
```
bundle exec rspec spec/bash_command_helper_spec.rb
```

## Test Structure for Command Testing

The command execution testing is structured to avoid loading the entire application.
We've created a namespaced mock version of MonadicApp in `monadic_app_command_mock.rb` 
that provides just enough functionality to test the command execution features.

### Namespace Structure

- `MonadicAppTest` - Main namespace for command testing
  - `MonadicHelper` - Mock implementation of the helper module
  - `MonadicApp` - Mock implementation of the app class

This approach prevents conflicts with the real MonadicApp class when running all tests together.