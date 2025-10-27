# Jupyter Controller Tests

This directory contains tests for the `jupyter_controller.py` script, which manages Jupyter notebooks for Monadic Chat.

## Test Files

1. **test_jupyter_controller.py** - Python unit tests
   - Tests all functions in isolation
   - Uses mocking to avoid file system dependencies
   - Verifies error handling and edge cases

2. **jupyter_controller_integration_spec.rb** - Ruby integration tests
   - Located in: `docker/services/ruby/spec/integration/`
   - Tests the script as called from Ruby code
   - Verifies command-line interface
   - Tests real file operations

## Running Tests

### Python Unit Tests

```bash
# Run all tests
python3 test_jupyter_controller.py

# Run with verbose output
python3 test_jupyter_controller.py -v

# Run specific test class
python3 test_jupyter_controller.py TestJupyterController

# Run with pytest (if installed)
python3 -m pytest test_jupyter_controller.py -v
```

### Ruby Integration Tests

From the Ruby service directory:
```bash
cd docker/services/ruby
bundle exec rspec spec/integration/jupyter_controller_integration_spec.rb
```

## Test Coverage

The tests cover:

### Core Functionality
- Creating new notebooks with timestamps
- Adding cells (markdown and code)
- Reading notebook contents
- Updating existing cells
- Deleting cells
- Searching for content in cells

### Cell Format Handling
- Standard format with 'content' field
- Alternative format with 'source' field (string)
- Alternative format with 'source' field (array)
- Mixed 'type' and 'cell_type' field names

### Error Handling
- Non-existent notebooks
- Invalid JSON input
- Invalid cell types
- Out-of-range cell indices
- File I/O errors with retry mechanism

### Command-Line Interface
- All subcommands (create, read, add, display, delete, update, search)
- JSON file input for batch operations
- Proper error messages and exit codes

## Implementation Notes

1. The controller uses retry mechanisms for file operations to handle temporary locks
2. Cell content can be provided in multiple formats for compatibility
3. All paths are relative to `/monadic/data/` in production
4. Timestamps are added to created notebooks to ensure uniqueness
