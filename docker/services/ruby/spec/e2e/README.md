# End-to-End (E2E) Tests

This directory contains end-to-end tests that verify complete user workflows in Monadic Chat.

## Overview

E2E tests simulate real user interactions with the system, testing the integration of all components including:
- WebSocket communication
- AI model interactions
- File processing
- Database operations
- Container orchestration

## Prerequisites

### Required Setup

1. **All Docker containers must be running:**
   ```bash
   ./docker/monadic.sh start
   ```

2. **Ruby server must be running:**
   ```bash
   rake server
   ```

3. **Required gems:**
   ```bash
   gem install websocket-client-simple prawn
   ```

### Environment Variables

Ensure your `~/monadic/config/env` file contains:
- `OPENAI_API_KEY` (for ChatOpenAI and CodeInterpreter tests)
- `POSTGRES_*` variables (for PDF Navigator tests)

## Test Structure

### chat_workflow_spec.rb
Tests basic chat application functionality:
- Simple Q&A interactions
- Context management across messages
- Error handling
- Different model configurations
- Performance characteristics

### code_interpreter_workflow_spec.rb
Tests code execution and data analysis:
- Python code execution
- Data science library usage
- File I/O operations
- Multi-step analysis workflows
- Error handling in code execution

### pdf_navigator_workflow_spec.rb
Tests PDF processing and search:
- PDF upload and text extraction
- Semantic search capabilities
- Multi-PDF queries
- Complex technical queries
- Edge cases and error handling

## Running the Tests

### Run all E2E tests:
```bash
cd docker/services/ruby
bundle exec rspec spec/e2e --format documentation
```

### Run specific test file:
```bash
bundle exec rspec spec/e2e/chat_workflow_spec.rb
```

### Run with specific example:
```bash
bundle exec rspec spec/e2e/chat_workflow_spec.rb:23
```

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