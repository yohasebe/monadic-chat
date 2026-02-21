# Anthropic/Claude Architecture

This document explains the architecture and design decisions in Monadic Chat's Anthropic/Claude integration.

## Overview

The Claude integration (`docker/services/ruby/lib/monadic/adapters/vendors/claude_helper.rb`) provides a Ruby adapter for Anthropic's Claude models. It handles:
- API request formatting
- Response streaming
- Tool/function calling
- Extended thinking support
- Prompt caching
- Error handling

## Design Decisions in claude_helper.rb

This section documents hardcoded behavior patterns in `claude_helper.rb` and explains the rationale behind each design decision. These patterns are candidates for eventual migration to the SSOT (Single Source of Truth) system via `model_spec.js`.

### 1. Beta Feature Flags

**Pattern**: Thinking capability determined via SSOT (`supports_thinking` flag in `model_spec.js`)

```ruby
# SSOT-based (current implementation)
supports_thinking = Monadic::Utils::ModelSpec.supports_thinking?(obj["model"])
use_adaptive = supports_thinking &&
               Monadic::Utils::ModelSpec.supports_adaptive_thinking?(obj["model"])
```

**Rationale**:
- Thinking support is defined per model in `model_spec.js` (SSOT)
- Opus 4.6+ uses adaptive thinking (`thinking: {type: "adaptive"}` + `output_config: {effort: ...}`)
- Older models use legacy thinking (`thinking: {type: "enabled", budget_tokens: N}`)
- Feature availability is model-specific, managed via `supports_thinking` and `supports_adaptive_thinking` flags

**SSOT Status**: ✅ Migrated
- `ModelSpec.supports_thinking?(model)` — returns true for all thinking-capable models
- `ModelSpec.supports_adaptive_thinking?(model)` — returns true for Opus 4.6+

### 2. Streaming Defaults

**Pattern**: All Claude models default to streaming enabled

```ruby
def default_streaming
  true  # Claude's streaming is stable and provides better UX
end
```

**Rationale**:
- Claude's streaming implementation is production-ready
- Provides better user experience with progressive response display
- Lower perceived latency for long responses
- All Claude models support streaming without quality degradation

**SSOT Migration Path**:
- Maps to `streaming_default` in `model_spec.js`
- Accessor: `ModelSpec.streaming_default(model, 'anthropic')`

### 3. Tool Call Limits

**Pattern**: Maximum 20 tool calls per conversation turn

```ruby
MAX_TOOL_CALLS = 20

def check_tool_call_limit(count)
  raise ToolCallLimitError if count >= MAX_TOOL_CALLS
end
```

**Rationale**:
- Balance between capability and cost/safety
- Prevents infinite loops in tool calling scenarios
- Anthropic API doesn't enforce hard limit, but excessive calls indicate logic errors
- 20 calls sufficient for complex multi-step workflows

**SSOT Migration Path**:
- Maps to `max_tool_calls` in `model_spec.js`
- Accessor: `ModelSpec.max_tool_calls(model, 'anthropic')`

### 4. Context Window Handling

**Pattern**: Context windows vary by model series

```ruby
# SSOT-based (current implementation)
context_window = Monadic::Utils::ModelSpec.get_model_property(model, "context_window")
```

**Rationale**:
- Context window is fundamental model capability
- Determines how much conversation history can be included
- Affects prompt caching effectiveness
- Must be accurate to avoid API errors

**SSOT Migration Path**:
- Maps to `context_window` in `model_spec.js`
- Accessor: `ModelSpec.context_window(model, 'anthropic')`

### 5. Output Token Limits

**Pattern**: Maximum output tokens vary by model

```ruby
# SSOT-based (current implementation)
max_output = Monadic::Utils::ModelSpec.get_model_property(model, "max_output_tokens")
```

**Rationale**:
- Output limit is API constraint, not user preference
- Newer models support longer outputs
- Conservative defaults prevent API errors for unknown models
- Affects response truncation behavior

**SSOT Migration Path**:
- Maps to `max_output_tokens` in `model_spec.js`
- Accessor: `ModelSpec.max_output_tokens(model, 'anthropic')`

### 6. Vision Capability Detection

**Pattern**: Detect vision support based on model name

```ruby
def supports_vision?(model)
  !model.to_s.downcase.include?('haiku-3.0')  # All except old Haiku
end
```

**Rationale**:
- Vision support is architectural model feature
- Haiku 3.0 is text-only, all other Claude models support images
- Required for proper image handling in requests
- Affects tool availability (image analysis tools)

**SSOT Migration Path**:
- Maps to `vision_capability` in `model_spec.js`
- Accessor: `ModelSpec.supports_vision?(model, 'anthropic')`

### 7. Prompt Caching Support

**Pattern**: All Claude 3.5+ models support prompt caching

```ruby
def supports_prompt_caching?(model)
  model.to_s.match?(/sonnet-4|opus-4|haiku-4/)
end
```

**Rationale**:
- Prompt caching reduces costs for repeated context
- Only available in Claude 3.5 series and later
- Requires specific API parameter formatting
- Cost optimization feature, not functional requirement

**SSOT Migration Path**:
- Maps to `supports_prompt_caching` in `model_spec.js`
- Accessor: `ModelSpec.supports_prompt_caching?(model, 'anthropic')`

### 8. Thinking Budget Constraints

**Pattern**: Extended thinking has configurable budget limits

```ruby
def thinking_budget_tokens(budget_setting)
  case budget_setting
  when 'low'
    10_000
  when 'medium'
    20_000
  when 'high'
    50_000
  else
    20_000  # Default medium
  end
end
```

**Rationale**:
- Extended thinking consumes additional tokens
- User should control cost vs depth tradeoff
- Different use cases need different budgets (quick chat vs research)
- Budget affects reasoning quality and response time

**SSOT Migration Path**:
- Maps to `thinking_budget_options` in `model_spec.js`
- Accessor: `ModelSpec.thinking_budget_tokens(model, budget, 'anthropic')`

## API Request Format

### Standard Messages API

```ruby
POST https://api.anthropic.com/v1/messages

{
  "model": "claude-sonnet-4-5-20250929",
  "max_tokens": 4096,
  "messages": [
    {"role": "user", "content": "Hello"}
  ],
  "system": "You are a helpful assistant.",
  "temperature": 0.7
}
```

### With Thinking (Legacy — Sonnet 4.5, Opus 4, etc.)

```ruby
{
  "model": "claude-sonnet-4-5-20250929",
  "max_tokens": 4096,
  "thinking": {
    "type": "enabled",
    "budget_tokens": 20000
  },
  "messages": [...]
}
```

### With Adaptive Thinking (Opus 4.6+)

```ruby
{
  "model": "claude-opus-4-6",
  "max_tokens": 4096,
  "thinking": {
    "type": "adaptive"
  },
  "output_config": {
    "effort": "high"
  },
  "messages": [...]
}
```

### With Tool Calling

```ruby
{
  "model": "claude-sonnet-4-5-20250929",
  "max_tokens": 4096,
  "tools": [
    {
      "name": "search_web",
      "description": "Search the web for information",
      "input_schema": {
        "type": "object",
        "properties": {
          "query": {"type": "string", "description": "Search query"}
        },
        "required": ["query"]
      }
    }
  ],
  "messages": [...]
}
```

## Response Streaming

Claude uses Server-Sent Events (SSE) for streaming:

```
event: message_start
data: {"type":"message_start","message":{"id":"msg_123",...}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" world"}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: message_stop
data: {"type":"message_stop"}
```

### Thinking Block Handling

Extended thinking responses include separate thinking blocks:

```
event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Let me analyze..."}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: content_block_start
data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Based on my analysis..."}}
```

## Error Handling

### Rate Limiting

```ruby
rescue Faraday::TooManyRequestsError => e
  retry_after = e.response_headers['retry-after'].to_i
  sleep(retry_after)
  retry
end
```

### Token Limit Errors

```ruby
rescue Faraday::BadRequestError => e
  if e.message.include?('prompt is too long')
    truncate_context_and_retry
  else
    raise
  end
end
```

## SSOT Migration Status

| Feature | Current Implementation | SSOT Status |
|---------|-----------------------|-------------|
| Thinking (Legacy) | SSOT flag `supports_thinking` | ✅ In `model_spec.js` |
| Adaptive Thinking | SSOT flag `supports_adaptive_thinking` | ✅ In `model_spec.js` (Opus 4.6+) |
| Context Window | Hardcoded case statement | ✅ In `model_spec.js` |
| Max Output Tokens | Hardcoded case statement | ✅ In `model_spec.js` |
| Vision Support | Hardcoded model check | ✅ In `model_spec.js` |
| Streaming Default | Hardcoded true | Not migrated (handled in `claude_helper.rb`) |
| Tool Call Limit | Hardcoded constant | Not migrated (handled in `claude_helper.rb`) |
| Prompt Caching | Hardcoded model check | Not migrated (handled in `claude_helper.rb`) |
| Thinking Budget | SSOT `thinking_budget` + adaptive effort mapping | ✅ In `model_spec.js` + `claude_helper.rb` |

## Related Files

- **Implementation**: `docker/services/ruby/lib/monadic/adapters/vendors/claude_helper.rb`
- **SSOT Definitions**: `docker/services/ruby/public/js/monadic/model_spec.js`
- **SSOT Accessors**: `docker/services/ruby/lib/monadic/utils/model_spec.rb`
- **Documentation**: `docs_dev/ssot_normalization_and_accessors.md`

## Testing Considerations

### Unit Tests

Test each capability detection method:

```ruby
RSpec.describe Monadic::Utils::ModelSpec do
  describe '.supports_thinking?' do
    it 'returns true for Claude Sonnet 4.5' do
      expect(described_class.supports_thinking?('claude-sonnet-4-5-20250929')).to be true
    end

    it 'returns false for Claude Haiku 4.5' do
      expect(described_class.supports_thinking?('claude-haiku-4-5-20251001')).to be false
    end
  end

  describe '.supports_adaptive_thinking?' do
    it 'returns true for Opus 4.6' do
      expect(described_class.supports_adaptive_thinking?('claude-opus-4-6')).to be true
    end

    it 'returns false for older models' do
      expect(described_class.supports_adaptive_thinking?('claude-sonnet-4-5-20250929')).to be false
    end
  end
end
```

### Integration Tests

Test actual API behavior with real models:

```ruby
RSpec.describe 'Claude API Integration', type: :integration do
  it 'successfully uses adaptive thinking with Opus 4.6' do
    response = helper.chat(
      model: 'claude-opus-4-6',
      messages: [...],
      thinking: { type: 'adaptive' },
      output_config: { effort: 'high' }
    )

    expect(response).to have_key(:thinking_content)
    expect(response[:thinking_content]).not_to be_empty
  end
end
```

## Performance Optimization

### Prompt Caching Strategy

Cache system prompts that don't change across conversations:

```ruby
{
  "system": [
    {
      "type": "text",
      "text": "Long system prompt...",
      "cache_control": {"type": "ephemeral"}
    }
  ]
}
```

**Benefits**:
- Reduces cost for repeated context
- Faster response times
- Enables longer system prompts

### Streaming Optimization

Process streaming chunks efficiently:

```ruby
def process_stream(stream)
  buffer = ""

  stream.each do |chunk|
    buffer << chunk
    yield buffer if buffer.length % 100 == 0  # Emit every 100 chars
  end

  yield buffer  # Emit final content
end
```
