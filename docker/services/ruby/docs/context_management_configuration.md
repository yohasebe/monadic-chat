# Context Management Configuration Guide

## Overview

Context management automatically clears old tool results when conversations grow long, helping maintain performance and stay within token limits. This feature is available for Claude 4+ models.

## Supported Models

- Claude Opus 4.1 (`claude-opus-4-1-20250805`)
- Claude Opus 4 (`claude-opus-4-20250514`)
- Claude Sonnet 4.5 (`claude-sonnet-4-5-20250929`)
- Claude Sonnet 4 (`claude-sonnet-4-20250514`)

## Default Configuration

If no custom configuration is provided, the following defaults are used:

- **Trigger**: 100,000 input tokens
- **Keep**: 5 most recent tool uses
- **Clear at least**: 10,000 tokens

## Custom Configuration per App

Apps can define custom context management settings in their MDSL files:

```ruby
app "MyApp" do
  # ... other configuration ...

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
          value: 3  # Keep only 3 recent tool uses
        },
        clear_at_least: {
          type: "input_tokens",
          value: 15000  # Clear at least 15K tokens
        },
        exclude_tools: ["important_tool"]  # Never clear these tools
      }
    ]
  end
end
```

## Configuration Options

### trigger
When to start clearing content:
- `type: "input_tokens"` - Trigger based on token count
- `value: 50000` - Threshold value

### keep
How many recent tool uses to preserve:
- `type: "tool_uses"` - Count by tool uses
- `value: 3` - Number to keep

### clear_at_least
Minimum amount to clear (useful for prompt caching):
- `type: "input_tokens"` - Measure in tokens
- `value: 15000` - Minimum to clear

### exclude_tools
Array of tool names to never clear:
- `["web_search", "important_tool"]` - Tool names to preserve

## Use Case Examples

### Research Assistant
Aggressive clearing for web search results:
```ruby
context_management do
  edits [
    {
      type: "clear_tool_uses_20250919",
      trigger: { type: "input_tokens", value: 50000 },
      keep: { type: "tool_uses", value: 3 },
      clear_at_least: { type: "input_tokens", value: 15000 }
    }
  ]
end
```

### Code Assistant
Conservative clearing to preserve context:
```ruby
context_management do
  edits [
    {
      type: "clear_tool_uses_20250919",
      trigger: { type: "input_tokens", value: 150000 },
      keep: { type: "tool_uses", value: 10 },
      clear_at_least: { type: "input_tokens", value: 5000 },
      exclude_tools: ["file_editor", "code_runner"]
    }
  ]
end
```

### Chat Application
Balanced configuration:
```ruby
context_management do
  edits [
    {
      type: "clear_tool_uses_20250919",
      trigger: { type: "input_tokens", value: 100000 },
      keep: { type: "tool_uses", value: 5 },
      clear_at_least: { type: "input_tokens", value: 10000 }
    }
  ]
end
```

## Notes

- Context editing invalidates cached prompt prefixes
- Only tool results are cleared by default (tool calls are preserved)
- The feature requires beta header `context-management-2025-06-27` (automatically added)
- Apps without custom configuration use the default settings