# Reasoning Effort Configuration Updates

## Overview

Recent updates to OpenAI's GPT-5 models require adjustments to the `reasoning_effort` parameter when using certain features.

## Affected Applications

### Research Assistant
- **Previous**: `reasoning_effort: "minimal"`
- **Current**: `reasoning_effort: "low"`
- **Reason**: Web search functionality requires "low" or higher reasoning effort

### Content Reader
- **Previous**: `reasoning_effort: "minimal"`
- **Current**: `reasoning_effort: "low"`
- **Reason**: Web search functionality requires "low" or higher reasoning effort

## Understanding Reasoning Effort Levels

The `reasoning_effort` parameter controls how much computational reasoning the model applies:

- **minimal**: Fastest responses, basic reasoning
- **low**: Balanced speed and reasoning capability
- **medium**: More thorough reasoning
- **high**: Maximum reasoning capability

## Feature Compatibility

| Feature | Minimal | Low | Medium | High |
|---------|---------|-----|--------|------|
| Basic chat | ✅ | ✅ | ✅ | ✅ |
| Tool calls | ✅ | ✅ | ✅ | ✅ |
| Web search | ❌ | ✅ | ✅ | ✅ |
| Complex reasoning | ❌ | ✅ | ✅ | ✅ |

## Impact on Performance

The change from "minimal" to "low" provides:
- Enhanced web search capabilities
- Better contextual understanding
- Slightly longer response times (still optimized for performance)
- More accurate information retrieval

## No Action Required

These changes are automatically applied. Users don't need to make any configuration changes - the applications will work as expected with improved capabilities.