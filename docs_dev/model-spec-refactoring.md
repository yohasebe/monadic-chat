# Model Spec Refactoring Guide

## Overview

Monadic Chat has transitioned from hardcoded model arrays in provider helpers to a property-based model configuration system using `model_spec.js`. This provides better maintainability and consistency across the codebase.

## Architecture

### Model Properties

Each model in `model_spec.js` can have the following properties:

```javascript
{
  "model-name": {
    // Core capabilities
    "tool_capability": boolean,        // Supports function calling
    "vision_capability": boolean,       // Supports image input
    "supports_web_search": boolean,    // Has web search capability
    
    // API behavior
    "supports_streaming": boolean,     // Supports streaming responses
    "api_endpoint_type": string,       // "standard" or "responses"
    "processing_speed": string,        // "normal", "slow", "fast"
    
    // Parameter support
    "supports_temperature": boolean,   // Accepts temperature parameter
    "supports_penalties": boolean,     // Accepts frequency/presence penalties
    "supports_verbosity": boolean,     // Supports verbosity parameter
    
    // Reasoning models
    "reasoning_effort": string/array,  // For reasoning models
    "is_reasoning_model": boolean,     // Explicitly marks reasoning models
    
    // Other properties...
  }
}
```

### ModelSpec Module

The Ruby `ModelSpec` module provides helper methods to query model properties:

```ruby
# Check capabilities
ModelSpec.supports_tools?(model_name)
ModelSpec.supports_vision?(model_name)
ModelSpec.supports_web_search?(model_name)
ModelSpec.supports_streaming?(model_name)

# Get properties
ModelSpec.api_endpoint_type(model_name)
ModelSpec.processing_speed(model_name)
ModelSpec.model_has_property?(model_name, property_name)
```

## Provider Helper Refactoring

### Before (Hardcoded Arrays)

```ruby
REASONING_MODELS = ["o1-mini", "o1", "o3-mini"]
NON_STREAM_MODELS = ["o1-mini", "o1", "o3-mini"]
RESPONSES_API_MODELS = ["o1-mini", "o1", "gpt-4.1"]

# Usage
if REASONING_MODELS.include?(model)
  # Handle reasoning model
end
```

### After (Property-based)

```ruby
# Usage
if ModelSpec.model_has_property?(model, "reasoning_effort")
  # Handle reasoning model
end

if ModelSpec.api_endpoint_type(model) == "responses"
  # Use responses API
end
```

## Adding New Models

When adding a new model:

1. Add the model configuration to `model_spec.js`
2. Include all relevant properties
3. No changes needed in provider helpers - they automatically use ModelSpec

Example:
```javascript
"new-model-2025": {
  "context_window": [1, 128000],
  "max_output_tokens": [1, 4096],
  "tool_capability": true,
  "vision_capability": false,
  "supports_streaming": true,
  "api_endpoint_type": "standard",
  "processing_speed": "normal",
  "supports_temperature": true,
  "supports_penalties": true
}
```

## Provider-Specific Considerations

### Perplexity
- All Perplexity models have `tool_capability: false`
- The helper removes tools from all requests
- MDSL files should not define tools for Perplexity apps

### OpenAI
- Reasoning models (o1, o3, gpt-5) have:
  - `supports_temperature: false`
  - `supports_penalties: false`
  - `api_endpoint_type: "responses"`

### Claude
- Uses native web search when available
- Supports parallel function calling

## Testing Considerations

### PDF Navigator Tests
- AI models may not use tools without explicit instruction
- Test messages should include "Use find_closest_text" or similar
- System prompts alone may not guarantee tool usage

### Fork Safety on macOS
- Set `ENV['OBJC_DISABLE_INITIALIZE_FORK_SAFETY'] = 'YES'` for Thin server
- Required for tests that start the server in forked processes

## Migration Checklist

When refactoring a provider helper:

1. ✅ Identify all hardcoded model arrays
2. ✅ Map arrays to appropriate ModelSpec properties
3. ✅ Replace array checks with ModelSpec method calls
4. ✅ Update model_spec.js with any missing properties
5. ✅ Test with affected models
6. ✅ Update MDSL files if needed (e.g., remove tools for non-supporting providers)

## Best Practices

1. **Always use ModelSpec** for model capability checks
2. **Keep model_spec.js as single source of truth**
3. **Document special cases** in comments
4. **Test edge cases** like reasoning models and tool-less providers
5. **Update both JS and Ruby specs** when adding properties