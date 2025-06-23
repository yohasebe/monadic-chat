# Docker Integration Tests

This directory contains integration tests that verify the interaction between Monadic Chat and Docker containers.

## Prerequisites

1. Docker must be installed and running
2. Monadic Chat containers must be built and running:
   ```bash
   ./docker/monadic.sh build
   ./docker/monadic.sh start
   ```

## Running the Tests

### Run all integration tests:
```bash
rake spec_integration
```

### Run only Docker-specific tests:
```bash
rake spec_docker
```

### Run specific test files:
```bash
cd docker/services/ruby
bundle exec rspec spec/integration/docker_integration_spec.rb
```

## Test Coverage

### docker_integration_spec.rb
- Basic container communication
- Python code execution
- File sharing between containers
- Error handling

### app_docker_integration_spec.rb
- Code Interpreter functionality
- Data science libraries (pandas, matplotlib, numpy)
- File processing tools
- Multi-container workflows

### container_helpers_integration_spec.rb
- PythonContainerHelper methods
- BashCommandHelper methods
- ReadWriteHelper methods
- Cross-helper integration

### pgvector_integration_spec.rb
- PostgreSQL/pgvector connectivity (placeholder)
- Vector operations (placeholder)
- Embedding storage (placeholder)

## Writing New Docker Integration Tests

When writing new Docker integration tests:

1. Always check if Docker is available:
   ```ruby
   before(:all) do
     skip "Docker tests require Docker environment" unless docker_available?
   end
   ```

2. Use helper methods for container interaction:
   ```ruby
   result = execute_in_container(
     code: "print('Hello')",
     command: "python",
     container: "python"
   )
   ```

3. Clean up generated files:
   ```ruby
   # Cleanup
   File.delete(test_file) if File.exist?(test_file)
   ```

4. Test both success and failure cases

## Troubleshooting

### Tests are skipped
- Ensure Docker is running: `docker ps`
- Ensure containers are running: `./docker/monadic.sh status`

### Permission errors
- Check file permissions in ~/monadic/data
- Ensure current user has Docker permissions

### Container not found
- Verify container names match the pattern: `monadic-chat-{service}-container`
- Check containers are running: `docker ps | grep monadic`