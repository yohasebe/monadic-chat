# Monadic Chat Ruby Testing

This directory contains tests for the Ruby components of Monadic Chat.

## Test Structure

The test suite is organized as follows:

- `spec_helper.rb` - Common setup for all tests
- `*_spec.rb` - Individual test files for different components
- `monadic_app_command_mock.rb` - Mock implementation of MonadicApp for testing command execution

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

## Test Design Principles

1. **Isolation** - Tests use namespaces to avoid conflicts between different test files
2. **Mocking** - Dependencies are mocked to avoid external service calls
3. **Comprehensive Coverage** - Edge cases and error conditions are tested

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