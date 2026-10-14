# Video Generator (Gemini) Tests

`spec/unit/scripts/generators/video_generator_gemini_spec.rb` tests `scripts/generators/video_generator_gemini.rb`, the Veo video generator used by the Gemini variant of Video Generator. All HTTP requests and file writes are stubbed; no API is called.

## Coverage

| Group | What is checked |
|---|---|
| `#get_api_key` | Reading the key from the config |
| `#get_save_path` | Choosing and creating the output directory |
| `#encode_image_to_data_url` | Encoding valid images; rejecting invalid or oversized ones |
| `#resolve_image_path` | Finding an input image in the expected locations |
| `#request_video_generation` | The request body for text-to-video and image-to-video |
| `#check_operation_status` | Completed, pending and timed-out operations |
| `#save_video` | Downloading the result or writing a placeholder |
| `process_operation_result` | `raiMediaFilteredReasons` shown when content was filtered; the generic message otherwise |
| `#generate_video` retries | Every argument is kept on each retry, and retries stop after the given number of attempts |
| `#generate_video` | The whole flow with stubbed responses |
| `#parse_options` | Command-line options, aspect ratio and duration validation |

Error responses use symbol keys (`process_generation_response`); successful results use string keys (`process_operation_result`).

## Running

```bash
cd docker/services/ruby
bundle exec rspec spec/unit/scripts/generators/video_generator_gemini_spec.rb
```

The app-level tools are tested in `spec/unit/apps/video_generator_tools_spec.rb`.
