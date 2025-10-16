# Video Generator Veo Tests

This test suite covers the `video_generator_veo.rb` script which generates videos using Google's Veo 3.1 API.

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
- **Command Line Parsing**: Tests option validation including Veo 3.1 features
- **Model Selection**: Tests automatic selection between fast and quality Veo 3.1 models
- **Negative Prompts**: Tests Veo 3.1's negative prompt functionality
- **Fast Mode**: Tests Veo 3.1's fast generation mode

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
5. **Model Selection**:
   - Veo 3.1 Preview: Standard quality model (veo-3.1-generate-preview)
   - Veo 3.1 Fast Preview: Fast model for quicker generation (veo-3.1-fast-generate-preview)
   - Configurable via fast_mode parameter or command line flag
6. **Veo 3.1 Features**:
   - Generates 4-8 second videos in 720p or 1080p with synchronized audio
   - Supports negative prompts to exclude unwanted elements
   - Fast mode trades quality for speed
   - Aspect ratio: 16:9 only

## Test Strategy

The tests use RSpec's double and allow/receive methods for mocking:
- HTTP responses are mocked with proper status codes and bodies
- File operations are stubbed to avoid actual disk I/O
- The test verifies behavior without side effects