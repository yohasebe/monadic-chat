# STT Error Handling Fix

## Problem
The `stt_api_request` method in `interaction_utils.rb` was returning a generic "Speech-to-Text API Error" message when the OpenAI API returned an error. This made it difficult for users to understand what went wrong (e.g., invalid API key, rate limit, unsupported format, etc.).

## Solution
Modified the error handling in `stt_api_request` to parse and include the actual error details from the OpenAI API response.

### Before (lines 1367-1368):
```ruby
else
  # Debug output removed
  { "type" => "error", "content" => "Speech-to-Text API Error" }
end
```

### After (lines 1367-1378):
```ruby
else
  # Parse error details from response body
  error_message = begin
    error_data = JSON.parse(response.body)
    formatted_error = format_api_error(error_data, "openai")
    "Speech-to-Text API Error: #{formatted_error}"
  rescue JSON::ParserError
    "Speech-to-Text API Error: #{response.status} - #{response.body}"
  end
  
  { "type" => "error", "content" => error_message }
end
```

## Benefits
1. **Better error messages**: Users now see specific error reasons like "Invalid API key", "Rate limit exceeded", etc.
2. **Provider context**: Errors are formatted with `[OPENAI]` prefix for clarity
3. **HTTP status codes**: When JSON parsing fails, the HTTP status code is included
4. **Consistent formatting**: Uses the existing `format_api_error` method for consistent error formatting across the codebase

## Example Error Messages

### Before:
- All errors: `"Speech-to-Text API Error"`

### After:
- Invalid API key: `"Speech-to-Text API Error: [OPENAI] Invalid API key provided"`
- Rate limit: `"Speech-to-Text API Error: [OPENAI] Rate limit exceeded"`
- Server error: `"Speech-to-Text API Error: 500 Internal Server Error - <response body>"`

## Testing
Run the diagnostic script to see the improved error handling:
```bash
cd docker/services/ruby
ruby scripts/diagnostics/test_stt_error.rb
```

The WebSocket handler in `websocket.rb` already adds additional context (format, model) to these errors when displaying them to users.