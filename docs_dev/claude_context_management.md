# Claude Context Management

> **Status**: Implemented (Beta feature)
> **API Version**: `context-management-2025-06-27`
> **Supported Models**: Claude Opus 4, Claude Sonnet 4.5

## Overview

Context management allows automatic management of conversation context as it grows, helping optimize costs and stay within context window limits. The API provides two strategies:

1. **Tool result clearing** (`clear_tool_uses_20250919`): Automatically clears tool use/result pairs
2. **Thinking block clearing** (`clear_thinking_20251015`): Manages thinking blocks from Extended Thinking

## Implementation Status

✅ **Fully Implemented**:
- Model capability detection (`supports_context_management`)
- Beta header automatic addition
- MDSL configuration support
- Default behavior with automatic thinking block management

## How It Works

### Server-Side Processing

Context editing is applied **server-side** before the prompt reaches Claude. Your client application maintains the full, unmodified conversation history—no need to sync client state with the edited version.

### Automatic Behavior

**For all context-management-enabled models:**
- Tool result clearing activates at 100K input tokens
- Keeps 5 most recent tool uses
- Clears at least 10K tokens per activation

**When thinking is enabled:**
- Thinking block clearing automatically added
- Keeps thinking blocks from last assistant turn (default)
- Preserves prompt cache when keeping thinking blocks

## MDSL Configuration

### Basic Configuration (Tool Result Clearing Only)

```ruby
app "MyApp" do
  llm do
    provider "anthropic"
    model "claude-sonnet-4-5-20250929"
  end

  context_management do
    edits [
      {
        type: "clear_tool_uses_20250919",
        trigger: {
          type: "input_tokens",
          value: 50000  # Trigger at 50K tokens
        },
        keep: {
          type: "tool_uses",
          value: 3  # Keep 3 most recent tool uses
        },
        clear_at_least: {
          type: "input_tokens",
          value: 15000  # Clear at least 15K tokens
        },
        exclude_tools: []  # Clear all tools (or specify tools to exclude)
      }
    ]
  end
end
```

### Advanced Configuration (Tool + Thinking Clearing)

```ruby
app "MyApp" do
  llm do
    provider "anthropic"
    model "claude-sonnet-4-5-20250929"
    thinking budget: 10000
  end

  context_management do
    edits [
      # IMPORTANT: clear_thinking MUST come FIRST
      {
        type: "clear_thinking_20251015",
        keep: {
          type: "thinking_turns",
          value: 2  # Keep thinking from last 2 assistant turns
        }
      },
      {
        type: "clear_tool_uses_20250919",
        trigger: {
          type: "input_tokens",
          value: 50000
        },
        keep: {
          type: "tool_uses",
          value: 3
        },
        clear_at_least: {
          type: "input_tokens",
          value: 15000
        },
        exclude_tools: ["web_search"]  # Never clear web search results
      }
    ]
  end
end
```

### Keep All Thinking Blocks (Maximize Cache Hits)

```ruby
context_management do
  edits [
    {
      type: "clear_thinking_20251015",
      keep: "all"  # Keep all thinking blocks - maximizes cache hits
    },
    {
      type: "clear_tool_uses_20250919",
      # ... tool clearing config ...
    }
  ]
end
```

## Configuration Options

### Tool Result Clearing (`clear_tool_uses_20250919`)

| Option | Default | Description |
|--------|---------|-------------|
| `trigger` | 100,000 tokens | When to start clearing (input_tokens or tool_uses) |
| `keep` | 5 tool uses | How many recent tool use/result pairs to preserve |
| `clear_at_least` | 10,000 tokens | Minimum tokens to clear (ensures cache invalidation is worthwhile) |
| `exclude_tools` | `[]` | List of tool names to never clear |
| `clear_tool_inputs` | `false` | Whether to clear tool call parameters (default: only results) |

### Thinking Block Clearing (`clear_thinking_20251015`)

| Option | Default | Description |
|--------|---------|-------------|
| `keep` | `{type: "thinking_turns", value: 1}` | Thinking blocks to preserve |

**Keep Options:**
- `{type: "thinking_turns", value: N}`: Keep thinking from last N assistant turns
- `"all"`: Keep all thinking blocks (maximizes prompt cache hits)

## Important Notes

### Strategy Ordering

When using both strategies, `clear_thinking_20251015` **MUST** come first in the `edits` array:

```ruby
edits [
  { type: "clear_thinking_20251015", ... },  # FIRST
  { type: "clear_tool_uses_20250919", ... }  # SECOND
]
```

### Prompt Caching Interaction

**Tool result clearing:**
- Invalidates cached prompt prefixes when content is cleared
- Use `clear_at_least` to ensure cache invalidation is worthwhile
- Incurs cache write costs on each clear, but subsequent requests reuse the new cached prefix

**Thinking block clearing:**
- Keeping thinking blocks preserves cache (enables cache hits)
- Clearing thinking blocks invalidates cache at the clearing point
- Trade-off: cache performance vs. context window availability

### Default Behavior Summary

| Condition | Tool Clearing | Thinking Clearing |
|-----------|---------------|-------------------|
| No MDSL config, no thinking | Enabled (100K trigger) | Not added |
| No MDSL config, thinking enabled | Enabled (100K trigger) | Auto-added (keep 1 turn) |
| MDSL config provided | Uses MDSL config | Uses MDSL config |

## Real-World Example: Research Assistant

Research Assistant Claude uses aggressive clearing for web search results:

```ruby
context_management do
  edits [
    {
      type: "clear_tool_uses_20250919",
      trigger: {
        type: "input_tokens",
        value: 50000  # Earlier than default (research contexts grow fast)
      },
      keep: {
        type: "tool_uses",
        value: 3  # Fewer than default (prioritize recent searches)
      },
      clear_at_least: {
        type: "input_tokens",
        value: 15000  # More than default (ensure worthwhile clearing)
      },
      exclude_tools: []  # Clear all tools including web_search
    }
  ]
end
```

**Rationale:**
- Research queries generate large web search results
- Only recent searches are typically relevant
- Clearing earlier prevents hitting context limits mid-research

## Response Information

The API returns information about applied context edits:

```json
{
  "context_management": {
    "applied_edits": [
      {
        "type": "clear_thinking_20251015",
        "cleared_thinking_turns": 3,
        "cleared_input_tokens": 15000
      },
      {
        "type": "clear_tool_uses_20250919",
        "cleared_tool_uses": 8,
        "cleared_input_tokens": 50000
      }
    ]
  }
}
```

## Best Practices

### When to Use Tool Result Clearing

✅ **Use for:**
- Long-running coding sessions with many file operations
- Research tasks with multiple web searches
- Applications with frequent tool usage
- Workflows that accumulate large tool results

❌ **Avoid for:**
- Short conversations unlikely to exceed 100K tokens
- Applications where all tool results are critical context
- Workflows where losing tool results breaks functionality

### When to Use Thinking Block Clearing

✅ **Use for:**
- Extended thinking enabled applications
- Long conversations with reasoning tasks
- Scenarios prioritizing context window over cache

✅ **Use `keep: "all"` for:**
- Maximizing prompt cache hits
- Reducing input token costs
- Applications with sufficient context window

### Exclude Tools Strategically

Consider excluding tools whose results provide critical ongoing context:

```ruby
exclude_tools: [
  "web_search",  # Web search results often needed for follow-ups
  "memory"       # Memory tool results contain persistent state
]
```

## Supported Models

| Model | ID | Context Management | Thinking Clearing |
|-------|-----|-------------------|-------------------|
| Claude Opus 4 | `claude-opus-4-20250514` | ✅ | ✅ |
| Claude Sonnet 4.5 | `claude-sonnet-4-5-20250929` | ✅ | ✅ |
| Claude 3.5 Sonnet | `claude-3-5-sonnet-20241022` | ❌ | ❌ |
| Claude 3 Haiku | `claude-3-haiku-20240307` | ❌ | ❌ |

## Related Documentation

- [Anthropic Context Management Documentation](https://docs.claude.com/en/docs/build-with-claude/context-editing)
- [Extended Thinking Documentation](https://docs.claude.com/en/docs/build-with-claude/extended-thinking)
- [Prompt Caching Documentation](https://docs.claude.com/en/docs/build-with-claude/prompt-caching)

## Implementation Files

- **Model Spec**: `public/js/monadic/model_spec.js` (defines `supports_context_management`)
- **Helper**: `lib/monadic/adapters/vendors/claude_helper.rb` (implements context management)
- **Accessor**: `lib/monadic/utils/model_spec.rb` (`supports_context_management?` method)
