# Thinking/Reasoning Process Display Implementation

This document describes how Monadic Chat displays thinking/reasoning processes from various AI providers in the user interface.

## Overview

Several AI providers now offer models that expose their internal reasoning or thinking process. Monadic Chat captures this content and displays it separately from the main response, allowing users to understand how the model arrived at its answer.

## Supported Providers

### Provider-Specific Implementations

| Provider | Models | Format | Display Name |
|----------|--------|--------|--------------|
| **OpenAI** | o1, o3 series | Field-based (`reasoning_content`) | Reasoning |
| **Anthropic (Claude)** | Sonnet 4.5+ | Content blocks (`type: "thinking"`) | Thinking |
| **DeepSeek** | deepseek-reasoner, deepseek-r1 | Field-based (`reasoning_content`) | Reasoning |
| **Gemini** | gemini-2.0-flash-thinking-exp | Parts with `thought: true` flag | Thinking |
| **Grok** | All models | Field-based (`reasoning_content`) | Reasoning |
| **Mistral** | All models | Field-based (`reasoning_content`) | Reasoning |
| **Cohere** | All models | JSON format (`content["thinking"]`) | Thinking |
| **Perplexity** | sonar-reasoning-pro | Dual format (JSON + tags) | Thinking |

## Implementation Patterns

### Field-Based Pattern (OpenAI, DeepSeek, Grok, Mistral)

These providers include reasoning content in a dedicated field within streaming deltas:

```ruby
# Extract from delta
reasoning = json.dig("choices", 0, "delta", "reasoning_content")

unless reasoning.to_s.strip.empty?
  reasoning_content << reasoning

  # Send to UI in real-time
  res = {
    "type" => "reasoning",
    "content" => reasoning
  }
  block&.call res
end

# Add to final response
if reasoning_content && !reasoning_content.empty?
  result["choices"][0]["message"]["reasoning"] = reasoning_content.join("\n\n")
end
```

### Content Block Pattern (Claude)

Claude uses structured content blocks with explicit types:

```ruby
# Detect thinking block start
if event["type"] == "content_block_start"
  current_block_type = event.dig("content_block", "type")
  if current_block_type == "thinking"
    thinking = event.dig("content_block", "thinking")
    # Store and send to UI
  end
end

# Handle thinking deltas
if event["type"] == "content_block_delta"
  if event.dig("delta", "type") == "thinking_delta"
    thinking = event.dig("delta", "thinking")
    # Store and send to UI
  end
end
```

### Parts-Based Pattern (Gemini)

Gemini includes a `thought` flag in content parts:

```ruby
parts = json.dig("candidates", 0, "content", "parts") || []
parts.each do |part|
  if part["thought"]
    thoughts << part["text"]

    # Send to UI
    res = {
      "type" => "thinking",
      "content" => part["text"]
    }
    block&.call res
  end
end
```

### JSON Format Pattern (Cohere)

Cohere sends thinking as word-level fragments in a JSON structure:

```ruby
if content && content.is_a?(Hash)
  if thinking_text = content["thinking"]
    unless thinking_text.strip.empty?
      thinking << thinking_text

      res = {
        "type" => "thinking",
        "content" => thinking_text
      }
      block&.call res
    end
  end
end

# Join without separators (word-level fragments)
if thinking_content && !thinking_content.empty?
  response[0]["choices"][0]["message"]["thinking"] = thinking_content.join("")
end
```

### Dual Format Pattern (Perplexity)

Perplexity supports both JSON format and XML-style tags:

```ruby
# Track state for tag-based format
inside_think_tag = false

# JSON format detection
if content && content.is_a?(Hash)
  if thinking_text = content["thinking"]
    # Handle like Cohere
  end
elsif content
  # Tag format: <think>...</think>
  fragment = content.to_s

  # Track tag boundaries
  if !inside_think_tag && fragment.include?('<think>')
    inside_think_tag = true
  end

  if inside_think_tag && fragment.include?('</think>')
    inside_think_tag = false
  end

  # Suppress fragments while inside thinking tags
  if inside_think_tag || fragment.include?('<think>') || fragment.include?('</think>')
    fragment = ""
  end

  # Extract complete thinking blocks
  fragment.scan(/<think>(.*?)<\/think>/m) do |match|
    thinking_text = match[0].strip
    unless thinking_text.empty?
      thinking << thinking_text

      res = {
        "type" => "thinking",
        "content" => thinking_text
      }
      block&.call res
    end
  end
end
```

## Frontend Display

### Streaming Display (Temporary Card)

During streaming, thinking/reasoning content appears in a temporary card:

```javascript
// Create temp-reasoning-card
tempReasoningCard = $(`
  <div id="temp-reasoning-card" class="card mt-3 streaming-card border-info">
    <div class="card-header p-2 ps-3 bg-info bg-opacity-10">
      <div class="fs-6 card-title mb-0 text-muted">
        <span><i class="fas fa-brain"></i></span> <span class="fw-bold">${titleText}</span>
      </div>
    </div>
    <div class="card-body">
      <div class="card-text small text-muted"></div>
    </div>
  </div>
`);

// Append thinking content
if (json.type === "thinking" || json.type === "reasoning") {
  tempReasoningCard.find('.card-text').append(json.content);
}
```

### Final Display (Collapsible Toggle)

After streaming completes, thinking content moves to a collapsible toggle:

```javascript
let thinkingHtml = `
  <div class="thinking-toggle mt-2">
    <a class="text-decoration-none" data-bs-toggle="collapse" href="#thinking-${index}">
      <i class="fas fa-chevron-right"></i> <span class="fw-bold">${titleText}</span>
    </a>
    <div class="collapse" id="thinking-${index}">
      <div class="card card-body mt-2 small text-muted">
        ${marked.parse(thinking)}
      </div>
    </div>
  </div>
`;
```

## Fragment Handling Strategies

### Block-Level Fragments (Most Providers)

Providers that send complete sentences or paragraphs use `join("\n\n")` to preserve readability:

```ruby
reasoning_content.join("\n\n")  # OpenAI, DeepSeek, Grok, Mistral, Gemini, Perplexity
```

### Word-Level Fragments (Cohere)

Cohere sends individual words/tokens, requiring direct concatenation:

```ruby
thinking_content.join("")  # Cohere
```

### Fragment Suppression (Perplexity Tag Format)

When using tag format, fragments inside `<think>` tags must be suppressed to prevent duplicate display:

```ruby
# Suppress all fragments while inside thinking tags
if inside_think_tag || fragment.include?('<think>') || fragment.include?('</think>')
  fragment = ""
end
```

This prevents thinking content from appearing in the normal temp card during streaming.

## Configuration

### Model Specification

Models that support thinking/reasoning should be flagged in `model_spec.js`:

```javascript
{
  name: "o1",
  provider: "openai",
  supportsReasoning: true  // Indicates reasoning capability
}
```

### Extended Thinking (Claude)

Claude's extended thinking mode requires explicit parameter:

```ruby
if model_name.include?("sonnet")
  params["thinking"] = {
    "type" => "enabled",
    "budget_tokens" => 10000
  }
end
```

### Thinking Config (Gemini)

Gemini requires thinking mode configuration:

```ruby
config = {
  "thinkingConfig" => {
    "thinkingMode" => "THINKING_MODE_ENABLED"
  }
}
```

## Testing

Test files verify the extraction, aggregation, and display logic for each provider:

- `spec/unit/openai_reasoning_spec.rb` (14 examples)
- `spec/unit/claude_thinking_spec.rb` (15 examples)
- `spec/unit/deepseek_reasoning_spec.rb` (14 examples)
- `spec/unit/gemini_thinking_spec.rb` (14 examples)
- `spec/unit/grok_reasoning_spec.rb` (12 examples)
- `spec/unit/mistral_reasoning_spec.rb` (12 examples)
- `spec/unit/cohere_thinking_spec.rb` (12 examples)
- `spec/unit/perplexity_thinking_spec.rb` (15 examples)

Run tests with:

```bash
rake spec_unit
```

## Debugging

### Enable Extra Logging

Set in `~/monadic/config/env`:

```bash
EXTRA_LOGGING=true
```

### Server Debug Mode

Use local Ruby for debugging (not Docker container):

```bash
rake server:debug
```

### Common Issues

1. **Missing temp-reasoning-card**: Check that `type: "thinking"` or `type: "reasoning"` messages are being sent from vendor helper

2. **Duplicate content**: Verify fragment suppression is working correctly (especially for tag-based formats)

3. **Wrong join strategy**: Confirm word-level vs block-level fragment handling

4. **Split tags not extracted**: Ensure buffer accumulation logic is implemented for incomplete tag pairs

## Related Documentation

- `docs/developer/reasoning_context_guidance.md` - GPT-5 reasoning context configuration
- `docs/updates/reasoning_effort_changes.md` - Reasoning effort parameter updates
- `docs_dev/websocket_progress_broadcasting.md` - WebSocket message broadcasting
