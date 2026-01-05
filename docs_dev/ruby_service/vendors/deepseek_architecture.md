# DeepSeek Architecture

This document explains the architecture and design decisions in Monadic Chat's DeepSeek integration.

## Overview

The DeepSeek integration (`docker/services/ruby/lib/monadic/adapters/vendors/deepseek_helper.rb`) provides a Ruby adapter for DeepSeek's models. It handles:
- API request formatting
- Response streaming
- Tool/function calling (including DSML parsing)
- Reasoning content extraction
- Strict mode for function calling
- Auto-retry mechanism for malformed responses
- Error handling

## Available Models

| Model | Type | Tool Calling | Reasoning |
|-------|------|--------------|-----------|
| `deepseek-chat` | Chat (V3.2) | Yes | No |
| `deepseek-reasoner` | Reasoning (V3.2) | Yes | Yes |

## Design Decisions in deepseek_helper.rb

### 1. DSML (DeepSeek Markup Language) Parsing

**Problem**: DeepSeek models sometimes output tool calls in a proprietary DSML format instead of the standard OpenAI-compatible `tool_calls` JSON format.

**DSML Format Example**:
```
<｜DSML｜function_calls>
<｜DSML｜invoke name="write_file">
<｜DSML｜param name="filename">test.txt</｜DSML｜/param>
<｜DSML｜param name="content">Hello World</｜DSML｜/param>
</｜DSML｜/invoke>
</｜DSML｜/function_calls>
```

**Solution**: The helper includes a comprehensive DSML parser that:

1. **Normalizes variations**:
   - Fullwidth pipes (`｜`) → ASCII pipes (`|`)
   - Different closing tag formats (`</|DSML|tag>` → `<|DSML|/tag>`)
   - Whitespace around tag boundaries

2. **Supports multiple tag formats**:
   - `<|DSML|param>` and `<|DSML|invoke_arg>` (parameter tags)
   - Self-closing tags for empty values
   - Nested invoke blocks

3. **Extracts tool calls** into standard format:
```ruby
{
  "id" => "call_#{SecureRandom.hex(12)}",
  "type" => "function",
  "function" => {
    "name" => "write_file",
    "arguments" => '{"filename":"test.txt","content":"Hello World"}'
  }
}
```

**Related Code**: Lines 700-900 in `deepseek_helper.rb`

### 2. Malformed DSML Detection and Auto-Retry

**Problem**: DeepSeek occasionally produces incomplete or malformed DSML, particularly in infinite loop patterns where it repeatedly outputs opening tags without closing them.

**Detection Pattern**:
```ruby
dsml_invoke_count = content.scan(/<\|DSML\|invoke/).length
dsml_close_invoke_count = content.scan(/<\|DSML\|\/invoke>/).length
dsml_function_calls_count = content.scan(/<\|DSML\|function_calls>/).length

is_malformed = (dsml_invoke_count > 3 && dsml_close_invoke_count == 0) ||
               (dsml_function_calls_count > 2)
```

**Auto-Retry Mechanism**:
- Maximum 4 retries with exponential backoff (1s, 2s, 3s, 4s)
- UI displays retry progress: `<i class='fas fa-redo'></i> RETRYING TOOL CALL (X/4)`
- Silent retry without contaminating session history
- After max retries, returns error message to user

**Related Code**: Lines 788-825 in `deepseek_helper.rb`

### 3. Reasoner Model Tool Calling Support

**Background**: As of V3.2, `deepseek-reasoner` supports tool calling (previously it did not).

**Implementation**:
```ruby
if obj["model"].include?("reasoner")
  body.delete("temperature")
  body.delete("presence_penalty")
  body.delete("frequency_penalty")
  # Note: Reasoner now supports tool calling (as of V3.2)
  # Keep tools and tool_choice if they exist

  body["messages"] = body["messages"].map do |msg|
    msg["content"] = msg["content"]&.sub(/---\n\n/, "") || msg["content"]
    msg
  end
end
```

**Key Points**:
- Temperature and penalty parameters are removed (not supported by reasoner)
- Tools and tool_choice are preserved (unlike earlier versions)
- Special content cleanup for reasoning separator markers

**Related Code**: Lines 427-439 in `deepseek_helper.rb`

### 4. Content Field Handling with Tool Calls

**Problem**: DeepSeek API returns error `duplicate field 'content'` when both `content` and `tool_calls` are present in assistant messages.

**Solution**: Set `content` to `nil` when tool_calls are present:
```ruby
res = {
  "role" => "assistant",
  "content" => nil,  # DeepSeek API requires content to be null/empty when tool_calls is present
  "tool_calls" => tools_data.map do |tool|
    {
      "id" => tool["id"],
      "type" => "function",
      "function" => tool["function"]
    }
  end
}
```

**Note**: This differs from Mistral (which requires content field) and other providers. Each API has different requirements.

**Related Code**: Lines 1109-1122 in `deepseek_helper.rb`

### 5. Strict Mode for Function Calling

**Pattern**: DeepSeek supports strict mode for enhanced schema validation.

```ruby
def use_strict_mode?(settings)
  settings.dig("features", "strict_mode") == true
end

def convert_to_strict_tools(tools)
  tools.map do |tool|
    tool["function"]["strict"] = true
    tool["function"]["parameters"]["additionalProperties"] = false
    tool
  end
end
```

**Behavior**:
- When enabled, adds `strict: true` to function definitions
- Sets `additionalProperties: false` on parameter schemas
- Provides better validation but may be more restrictive

**Note**: The beta API (`/beta`) with strict mode has schema validation issues; use standard API for reliability.

**Related Code**: `deepseek_strict_mode_spec.rb` (225 lines of tests)

### 6. Terminal Tool Handling

**Problem**: Some tools signal the end of a tool sequence (e.g., `save_learning_progress` in Math Tutor). After such "terminal" tools, making additional API requests causes empty responses and `content_not_found` errors.

**Solution**: Detect terminal tools and properly complete the turn without additional API requests.

**Detection**:
```ruby
# List of terminal tools that signal end of tool sequence
TERMINAL_TOOLS = %w[save_learning_progress save_response].freeze

def terminal_tool?(name)
  TERMINAL_TOOLS.include?(name)
end
```

**Completion Flow**:
```ruby
if terminal_tool_called
  # 1. Send DONE message to frontend (signals streaming complete)
  done_res = { "type" => "message", "content" => "DONE", "finish_reason" => "stop" }
  block&.call done_res

  # 2. Return properly structured response for websocket.rb processing
  final_response = {
    "choices" => [{
      "message" => { "role" => "assistant", "content" => "" },
      "finish_reason" => "stop"
    }]
  }
  return [final_response]
end
```

**Key Points**:
- The `done_res` message tells the frontend to stop spinners and complete UI
- The `final_response` has the `choices[0].message.content` structure that `websocket.rb` expects
- Empty string content (`""`) is valid; only `nil` triggers `content_not_found` error
- Without this handling, the model would be called again with tools disabled, returning empty content

**Related Code**: Lines 1342-1369 in `deepseek_helper.rb`

### 7. Reasoning Content Extraction

**Pattern**: Extract reasoning content from `deepseek-reasoner` responses.

```ruby
def extract_reasoning_content(response)
  response.dig("choices", 0, "message", "reasoning_content")
end
```

**Display**:
- Reasoning content is displayed in a collapsible panel in the UI
- Separate from main response content
- Supports streaming with fragment joining

**SSOT Configuration**:
```javascript
// model_spec.js
"deepseek-reasoner": {
  "supports_reasoning_content": true,
  "reasoning_content_field": "reasoning_content"
}
```

**Related Documentation**: `docs_dev/ruby_service/thinking_reasoning_display.md`

### 7. Timeout Configuration

DeepSeek operations can be long-running, especially with reasoning models:

```ruby
DEEPSEEK_OPEN_TIMEOUT = ENV.fetch("DEEPSEEK_OPEN_TIMEOUT", 10).to_i
DEEPSEEK_READ_TIMEOUT = ENV.fetch("DEEPSEEK_READ_TIMEOUT", 600).to_i
DEEPSEEK_WRITE_TIMEOUT = ENV.fetch("DEEPSEEK_WRITE_TIMEOUT", 120).to_i
```

**Environment Variables**:
- `DEEPSEEK_OPEN_TIMEOUT`: Connection timeout (default: 10s)
- `DEEPSEEK_READ_TIMEOUT`: Response read timeout (default: 600s / 10 minutes)
- `DEEPSEEK_WRITE_TIMEOUT`: Request write timeout (default: 120s)

## App-Specific Considerations

### Research Assistant (DeepSeek)

The DeepSeek version of Research Assistant is intentionally simplified:
- **Simpler system prompt** to avoid complex tool sequences
- **No monadic mode** to prevent tool loop issues
- **Uses Tavily** for web search instead of complex agent patterns

```ruby
# research_assistant_deepseek.mdsl
# Note: monadic mode disabled for DeepSeek due to tool loop issues
```

### Coding Assistant (DeepSeek)

Uses `deepseek-reasoner` as default for better tool calling reliability:
```ruby
llm do
  provider "deepseek"
  # Reasoner is default for better tool calling reliability
  # Chat is faster but may have DSML formatting issues with file operations
  model ["deepseek-reasoner", "deepseek-chat"]
end
```

## Troubleshooting

### Common Issues

1. **Infinite DSML loops**
   - Symptom: Response keeps generating DSML tags without completing
   - Solution: Auto-retry mechanism handles this; check logs for retry counts

2. **File write failures**
   - Symptom: File operations fail repeatedly
   - Cause: DSML escaping issues with special characters
   - Solution: Use `deepseek-reasoner` model; simplify file content

3. **Tool calls not recognized**
   - Symptom: Model outputs DSML but tools don't execute
   - Cause: DSML format variation not handled
   - Solution: Enable EXTRA_LOGGING to see raw DSML; report new patterns

4. **"Content not found in response" error after tool calls**
   - Symptom: Error appears after terminal tool (e.g., `save_learning_progress`) completes
   - Cause: Terminal tool handling not returning properly structured response
   - Solution: See "Terminal Tool Handling" section above; verify `final_response` structure

### Debugging

Enable extra logging to see raw DSML output:
```bash
# In ~/monadic/config/env
EXTRA_LOGGING=true
```

Check logs for:
- `[DeepSeekHelper] Raw DSML content:` - Original DSML before parsing
- `[DeepSeekHelper] Parsed tools:` - Extracted tool calls
- `RETRYING TOOL CALL` - Auto-retry in progress

## Testing

Related test files:
- `spec/unit/deepseek_reasoning_spec.rb` - Reasoning content extraction
- `spec/lib/monadic/adapters/vendors/deepseek_strict_mode_spec.rb` - Strict mode (225 lines)
- `spec/integration/provider_matrix/all_providers_all_apps_spec.rb` - Integration tests

Run DeepSeek-specific tests:
```bash
PROVIDERS=deepseek RUN_API=true bundle exec rspec spec/integration/provider_matrix/
```

## SSOT Migration Status

| Feature | Current Location | SSOT Field | Status |
|---------|-----------------|------------|--------|
| Reasoning content | Helper code | `supports_reasoning_content` | ✅ Migrated |
| Context window | Helper code | `context_window` | ✅ Migrated |
| Tool capability | Helper code | `tool_capability` | ✅ Migrated |
| Strict mode | Helper code | N/A | Not applicable (runtime setting) |
| DSML parsing | Helper code | N/A | Provider-specific, not suitable for SSOT |
