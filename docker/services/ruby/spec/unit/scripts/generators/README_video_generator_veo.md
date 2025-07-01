# Video Generator Veo Tests

This test suite covers the `video_generator_veo.rb` script which generates videos using Google's Veo 2.0 API.

## Test Coverage

The tests cover all major functionality without making actual API calls:

### Core Functionality
- **API Key Retrieval**: Tests reading from config files
- **Save Path Logic**: Tests directory selection and creation
- **Image Encoding**: Tests base64 encoding and validation
- **Image Path Resolution**: Tests finding images in various locations
- **Video Generation**: Tests the full workflow with mocked API responses
- **Operation Status Checking**: Tests polling for video generation completion
- **Video Saving**: Tests downloading and placeholder creation
- **Command Line Parsing**: Tests option validation

### Error Handling
- Invalid API responses
- Network timeouts
- File I/O errors
- Invalid command line arguments
- Oversized images
- Missing configuration

## Running Tests

```bash
cd docker/services/ruby
bundle exec rspec spec/unit/scripts/generators/video_generator_veo_spec.rb
```

## Implementation Notes

1. **No API Calls**: All HTTP requests are mocked to avoid API costs
2. **File Operations**: File I/O is mocked to avoid creating test artifacts
3. **Output Silencing**: STDOUT and STDERR are captured during tests
4. **Return Format**: The script returns hashes with different key types:
   - Symbol keys for error responses from `process_generation_response`
   - String keys for successful responses from `process_operation_result`

## Test Strategy

The tests use RSpec's double and allow/receive methods for mocking:
- HTTP responses are mocked with proper status codes and bodies
- File operations are stubbed to avoid actual disk I/O
- The test verifies behavior without side effects