# GPT-5-Codex Agent Implementation

## Overview

GPT-5-Codex is a specialized OpenAI model optimized for agentic coding tasks. Unlike regular chat models, it uses the Responses API and requires specific implementation patterns to function correctly.

## Key Characteristics

### Model Properties (model_spec.js)
```javascript
"gpt-5-codex": {
  "context_window": [1, 400000],      // 400K context
  "max_output_tokens": [1, 128000],   // 128K output
  "api_type": "responses",            // Uses Responses API
  "supports_temperature": false,      // No temperature parameter
  "supports_top_p": false,            // No sampling parameters
  "is_agent_model": true,            // Agent-only model
  "agent_type": "coding",            // Specialized for coding
  "adaptive_reasoning": true         // Adjusts reasoning time
}
```

### API Differences
- **Endpoint**: `/v1/responses` instead of `/v1/chat/completions`
- **No streaming**: Currently non-streaming implementation
- **No sampling parameters**: Temperature, top_p, etc. are not supported
- **Minimal prompting**: "Less is more" principle applies

## Implementation Pattern

### 1. Agent Tool Definition (MDSL)
```ruby
define_tool "gpt5_codex_agent", "Delegate complex coding tasks to GPT-5-Codex" do
  parameter :task, "string", "Description of the coding task", required: true
  parameter :context, "string", "Additional context or requirements", required: false
  parameter :files, "array", "Array of file objects with path and content", required: false
end
```

### 2. Tool Implementation
```ruby
def gpt5_codex_agent(task:, context: nil, files: nil)
  # Build minimal prompt
  prompt = task

  # Add file context if needed (limited)
  if files && files.is_a?(Array)
    files.take(3).each do |file|
      content_preview = file[:content].to_s[0..1000]
      prompt += "\n#{file[:path]}:\n```\n#{content_preview}\n```\n"
    end
  end

  # Create session for API call
  session = {
    parameters: { "model" => "gpt-5-codex" },
    messages: [{ "role" => "user", "content" => prompt }]
  }

  # Use OpenAIHelper's api_request (handles Responses API automatically)
  results = api_request("user", session, call_depth: 0)

  # Parse response
  if results && results.first
    content = results.first["content"] || results.first.dig("choices", 0, "message", "content")
    { code: content, success: true, model: "gpt-5-codex" }
  else
    { error: "No response from GPT-5-Codex", success: false }
  end
end
```

## Critical Implementation Notes

### Avoiding Infinite Loops

**Problem**: Direct calls to `send_query` or recursive tool calls can cause infinite loops.

**Solution**: Use `api_request` method from OpenAIHelper:
```ruby
# CORRECT: Uses OpenAIHelper's api_request
results = api_request("user", session, call_depth: 0)

# WRONG: Can cause recursion
response = send_query(parameters, model: "gpt-5-codex")
```

### Session Object Structure

The session object must match OpenAIHelper's expectations:
```ruby
session = {
  parameters: {
    "model" => "gpt-5-codex"  # Required for model detection
  },
  messages: [                  # Standard messages format
    {
      "role" => "user",
      "content" => prompt
    }
  ]
}
```

### Responses API Detection

OpenAIHelper automatically detects Responses API models via ModelSpec:
```ruby
# In ModelSpec
def responses_api?(model_name)
  get_model_property(model_name, "api_type") == "responses"
end

# In OpenAIHelper
use_responses_api = Monadic::Utils::ModelSpec.responses_api?(model)
if use_responses_api
  target_uri = "#{API_ENDPOINT}/responses"
  # ... special handling for Responses API
end
```

## Usage Pattern

### Architecture
```
User <-> GPT-5 (Main) <-> GPT-5-Codex (Agent)
           |
           v
      File Operations
```

1. User interacts with GPT-5 (main model)
2. GPT-5 determines when to delegate to GPT-5-Codex
3. GPT-5 calls `gpt5_codex_agent` tool for complex coding tasks
4. GPT-5-Codex processes the task and returns code
5. GPT-5 can save the code using file operations

### When to Use GPT-5-Codex

Delegate to GPT-5-Codex for:
- Writing complete applications
- Complex refactoring tasks
- Detailed code reviews
- Performance optimization
- Tasks requiring deep coding expertise

Keep with GPT-5 for:
- Simple code explanations
- Basic debugging
- User interaction and planning
- File management decisions

## Prompting Guidelines

Following the "less is more" principle from GPT-5-Codex documentation:

### DO:
- Keep prompts minimal and direct
- Provide only essential context
- Use clear, concise task descriptions
- Limit file content to relevant portions

### DON'T:
- Add verbose instructions
- Include unnecessary preambles
- Request specific formatting (it's built-in)
- Provide full file contents when snippets suffice

## Error Handling

```ruby
begin
  results = api_request("user", session, call_depth: 0)
  # ... process results
rescue StandardError => e
  {
    error: "Error calling GPT-5-Codex: #{e.message}",
    suggestion: "Try breaking the task into smaller pieces",
    success: false
  }
end
```

## Testing Considerations

1. **API Key**: Ensure `OPENAI_API_KEY` is set
2. **Model Access**: Verify account has access to gpt-5-codex
3. **Rate Limits**: Responses API may have different limits
4. **Latency**: GPT-5-Codex uses adaptive reasoning, response times vary

## Common Issues and Solutions

### Issue: Infinite function call loops
**Cause**: Using `send_query` or similar recursive calls
**Solution**: Use `api_request` with proper session structure

### Issue: Missing model in response
**Cause**: Improper session object structure
**Solution**: Include `parameters: { "model" => "gpt-5-codex" }`

### Issue: Sampling parameters rejected
**Cause**: GPT-5-Codex doesn't support temperature/top_p
**Solution**: Remove all sampling parameters from request

### Issue: Content truncation
**Cause**: Large file contents in prompt
**Solution**: Limit to 1000 chars per file, max 3 files

## References

- [OpenAI GPT-5-Codex Documentation](https://platform.openai.com/docs/models/gpt-5-codex)
- [Responses API Guide](https://platform.openai.com/docs/api-reference/responses)
- `lib/monadic/adapters/vendors/openai_helper.rb` - Responses API implementation
- `public/js/monadic/model_spec.js` - Model specifications
- `apps/coding_assistant/coding_assistant_tools.rb` - Agent implementation