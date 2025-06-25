# End-to-End (E2E) Tests

This directory contains end-to-end tests that verify complete user workflows in Monadic Chat.

## Overview

E2E tests simulate real user interactions with the system, testing the integration of all components including:
- WebSocket communication
- AI model interactions
- File processing
- Database operations
- Container orchestration

## Test Structure

```
e2e/
├── chat_workflow_spec.rb              # Basic chat functionality
├── code_interpreter_basic_spec.rb     # Core Code Interpreter tests
├── code_interpreter_multi_provider_spec.rb  # Provider-specific tests
├── code_interpreter_workflow_spec.rb  # Complex Code Interpreter workflows
├── image_generator_workflow_spec.rb   # Image generation tests
├── monadic_help_workflow_spec.rb      # Help system tests
├── pdf_navigator_workflow_spec.rb     # PDF search tests
├── shared_examples/                   # Reusable test examples
├── e2e_helper.rb                      # WebSocket connection helpers
├── validation_helper.rb               # Flexible validation methods
└── run_e2e_tests.sh                   # Test runner script
```

## Running Tests

### All E2E Tests (automatic setup)
```bash
rake spec_e2e
```

### Specific App Tests
```bash
rake spec_e2e:chat              # Chat app only
rake spec_e2e:code_interpreter   # All Code Interpreter tests
rake spec_e2e:image_generator    # Image Generator only
rake spec_e2e:pdf_navigator      # PDF Navigator only
rake spec_e2e:help              # Monadic Help only
```

### Provider-Specific Tests
```bash
rake spec_e2e:code_interpreter_provider[openai]
rake spec_e2e:code_interpreter_provider[claude]
rake spec_e2e:code_interpreter_provider[gemini]
# etc.
```

### Manual Test Execution
```bash
cd docker/services/ruby
bundle exec rspec spec/e2e/chat_workflow_spec.rb
bundle exec rspec spec/e2e/code_interpreter_workflow_spec.rb:23  # specific line
```

## Test Philosophy

1. **Functional Validation**: Tests focus on whether features work, not exact output matching
2. **Flexible Assertions**: Use pattern matching and existence checks rather than exact string comparisons
3. **Provider Agnostic**: Tests adapt to different provider response formats
4. **Minimal Redundancy**: Each test covers unique functionality
5. **Clean Retry**: Custom retry mechanism provides clear feedback during retries

## Key Testing Patterns

### Code Execution Validation
```ruby
expect(code_execution_attempted?(response)).to be true
```

### Flexible Content Matching
```ruby
expect(response.downcase).to match(/keyword1|keyword2|keyword3/i)
```

### System Error Handling
```ruby
skip "System error or tool failure" if system_error?(response)
```

## Prerequisites

- Docker containers (automatically started by `rake spec_e2e`)
- Server on localhost:4567 (automatically started if needed)
- API keys configured in `~/monadic/config/env`

## Writing New E2E Tests

### Basic Structure
```ruby
require_relative 'e2e_helper'

RSpec.describe "Feature E2E Workflow", type: :e2e do
  include E2EHelper

  before(:all) do
    unless check_containers_running
      skip "E2E tests require all containers to be running"
    end
    
    unless wait_for_server
      skip "E2E tests require server to be running"
    end
  end

  it "completes user workflow" do
    ws_connection = create_websocket_connection
    
    send_chat_message(ws_connection, "Your message", app: "AppName")
    response = wait_for_response(ws_connection)
    
    expect(response).to include("expected content")
    
    ws_connection[:client].close
  end
end
```

### Best Practices

1. **Always check prerequisites** in `before(:all)` blocks
2. **Clean up resources** in `after` blocks
3. **Use descriptive test names** that explain the workflow
4. **Test both success and failure paths**
5. **Include performance expectations** where relevant
6. **Mock external services** when necessary for reliability

## Debugging

### Enable verbose output:
```bash
VERBOSE=true bundle exec rspec spec/e2e
```

### Common Issues

1. **"Server not running" errors**
   - Ensure server is started: `rake server`
   - Check port 4567 is not in use

2. **"Containers not running" errors**
   - Start containers: `./docker/monadic.sh start`
   - Verify with: `docker ps | grep monadic`

3. **Timeout errors**
   - Increase timeout in `wait_for_response`
   - Check API keys are valid
   - Verify network connectivity

4. **WebSocket connection failures**
   - Check firewall settings
   - Ensure WebSocket port (4567) is accessible
   - Look for errors in server logs

## CI/CD Integration

These tests are designed to run in CI environments:

```yaml
# Example GitHub Actions configuration
- name: Start services
  run: |
    ./docker/monadic.sh build
    ./docker/monadic.sh start
    rake server &
    sleep 10

- name: Run E2E tests
  run: |
    cd docker/services/ruby
    bundle exec rspec spec/e2e --format documentation
```

## Performance Benchmarks

Expected response times under normal conditions:
- Simple chat queries: < 5 seconds
- Code execution: < 10 seconds  
- PDF search: < 15 seconds
- Multi-step workflows: < 30 seconds

## Future Enhancements

Planned improvements:
- [ ] Parallel test execution
- [ ] Visual regression testing for generated charts
- [ ] Load testing with multiple concurrent users
- [ ] Cross-browser testing for web UI
- [ ] Mobile app integration tests