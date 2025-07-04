# Monadic Chat Development Guide

## Setting Up Development Environment

### Prerequisites

- Ruby 3.0+ 
- Docker Desktop
- ImageMagick (for image processing tests)

### Initial Setup

1. Clone the repository
2. Navigate to `docker/services/ruby`
3. Install dependencies:
   ```bash
   bundle install
   ```

### Running Tests

#### Unit Tests (Fast)
```bash
rake spec_unit
```

#### All Tests
```bash
rake spec
```

#### Running Specific Test Files
```bash
# Run office2txt tests
bundle exec rspec spec/unit/scripts/office2txt_minimal_spec.rb

# Run PDF processing tests  
bundle exec rspec spec/unit/scripts/pdf2txt_docker_spec.rb
```

### Test Organization

- **Unit Tests** (`spec/unit/`): Fast, isolated tests
- **Integration Tests** (`spec/integration/`): Tests with external dependencies
- **System Tests** (`spec/system/`): Full application tests
- **E2E Tests** (`spec/e2e/`): End-to-end workflow tests

### Writing Tests for Scripts

#### Ruby Scripts
- Test locally without Docker
- Mock external dependencies when possible
- Use actual file operations with temp files

#### Python Scripts
- Always test through Docker container
- Use shared volume (`~/monadic/data`) for test files
- Clean up test artifacts after each test

### Common Issues

1. **Docker not running**: Start Docker Desktop before running Python script tests
2. **Permission errors**: Ensure `~/monadic/data` directory exists and is writable
3. **ImageMagick not found**: Install ImageMagick for image tests (`brew install imagemagick` on macOS)

### Code Style

Run RuboCop for code style checks:
```bash
bundle exec rubocop
```