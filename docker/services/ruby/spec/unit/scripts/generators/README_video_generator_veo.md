# Video Generator Veo Tests

This test suite covers the `video_generator_veo.rb` script which generates videos using Google's Veo 2.0 and Veo 3.0 APIs.

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
- **Command Line Parsing**: Tests option validation including new Veo 3 features
- **Model Selection**: Tests automatic selection between Veo 2.0 and Veo 3.0
- **Negative Prompts**: Tests Veo 3's negative prompt functionality
- **Fast Mode**: Tests Veo 3's fast generation mode

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
   - Veo 2.0 is used for image-to-video generation
   - Veo 3.0 is used for text-to-video generation (configurable)
   - Veo 3.0 Fast model available for quicker generation
6. **Veo 3.0 Features**:
   - Generates 8-second 720p videos with synchronized audio
   - Supports negative prompts to exclude unwanted elements
   - Fast mode trades quality for speed

## Test Strategy

The tests use RSpec's double and allow/receive methods for mocking:
- HTTP responses are mocked with proper status codes and bodies
- File operations are stubbed to avoid actual disk I/O
- The test verifies behavior without side effects