# Type Conversion Policy

## Overview

This document defines the type conversion policy between Ruby backend and JavaScript frontend in Monadic Chat. Following this policy prevents type-related bugs such as boolean strings being incorrectly evaluated as truthy values.

## Architecture

```
Ruby (MDSL/App Settings)
    ↓ JSON Serialization
WebSocket (JSON)
    ↓ JSON Parsing
JavaScript (Frontend)
```

## Type Categories

### 1. Boolean Feature Flags

**Purpose**: Enable/disable UI features and app behaviors

**Type Requirement**: MUST be preserved as boolean values (not strings)

**Affected Parameters**:
- UI Controls: `auto_speech`, `easy_submit`, `initiate_from_assistant`
- Rendering: `mathjax`, `mermaid`, `abc`, `sourcecode`, `monadic`
- Capabilities: `image`, `pdf`, `pdf_vector_storage`, `websearch`
- Advanced: `jupyter_access`, `jupyter`, `image_generation`, `video`

**Ruby Implementation** (`lib/monadic/utils/websocket.rb`):
```ruby
# In prepare_apps_data method
elsif ["auto_speech", "easy_submit", "initiate_from_assistant",
       "mathjax", "mermaid", "abc", "sourcecode", "monadic",
       "image", "pdf", "pdf_vector_storage", "websearch",
       "jupyter_access", "jupyter", "image_generation", "video"].include?(p.to_s)
  # Preserve boolean values for feature flags
  # These need to be actual booleans, not strings, for proper JavaScript evaluation
  apps[k][p] = m
```

**JavaScript Implementation**:
```javascript
// Global helper function for defensive boolean evaluation
window.toBool = (value) => {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'string') return value === 'true';
  return !!value;
};

// Usage in loadParams and proceedWithAppChange
if (toBool(params["auto_speech"])) {
  // Enable feature
}
```

**Why This Matters**:
```javascript
// Problem: String "false" is truthy in JavaScript
if ("false") {  // ← Evaluates to true!
  console.log("This runs!"); // ← Unexpected behavior
}

// Solution: Use actual boolean
if (false) {  // ← Evaluates to false
  console.log("This does not run"); // ← Expected behavior
}
```

### 2. Array and Object Parameters

**Purpose**: Complex data structures (model lists, tool definitions)

**Type Requirement**: MUST be JSON-serialized

**Affected Parameters**:
- `models` (Array of strings)
- `tools` (Array or Hash of tool definitions)

**Ruby Implementation**:
```ruby
elsif p == "models" && m.is_a?(Array)
  apps[k][p] = m.to_json
elsif p == "tools" && (m.is_a?(Array) || m.is_a?(Hash))
  apps[k][p] = m.to_json
```

**JavaScript Implementation**:
```javascript
// Parse JSON when needed
const models = JSON.parse(apps[appValue]["models"]);
const tools = JSON.parse(apps[appValue]["tools"]);
```

### 3. String Parameters

**Purpose**: Text content and identifiers

**Type Requirement**: Converted to strings (default behavior)

**Affected Parameters**:
- `app_name`, `display_name`, `icon`, `description`
- `initial_prompt`, `system_prompt`
- `group`, `provider`

**Ruby Implementation**:
```ruby
# Default case - convert to string
else
  apps[k][p] = m ? m.to_s : nil
end
```

### 4. Numeric Parameters

**Purpose**: Numeric settings for model behavior

**Type Requirement**: Currently converted to strings, but JavaScript handles this gracefully

**Affected Parameters**:
- `temperature` (Float)
- `context_size` (Integer)
- `max_tokens` (Integer)
- `reasoning_effort` (String, but conceptually ordered)

**Ruby Implementation**:
```ruby
# Currently uses default string conversion
apps[k][p] = m ? m.to_s : nil
```

**JavaScript Implementation**:
```javascript
// Type coercion happens automatically
const temperature = parseFloat(params["temperature"]);
const contextSize = parseInt(params["context_size"], 10);

// Or use directly in numeric contexts (automatic coercion)
if ($("#temperature").val() > 0.5) { ... }
```

**Numeric Parameters**:
When explicit numeric comparisons are required, add the parameter to the type-preservation list:
```ruby
elsif ["temperature", "context_size", "max_tokens"].include?(p.to_s)
  apps[k][p] = m
```

### 5. Special Case: disabled

**Purpose**: Control app availability based on API key presence

**Type Requirement**: MUST be string for compatibility

**Why String**:
- Evaluated as boolean expression in Ruby: `!CONFIG["OPENAI_API_KEY"]`
- Sent to frontend as string for display purposes
- Frontend checks for truthiness

**Ruby Implementation**:
```ruby
elsif p == "disabled"
  # Keep disabled as a string for compatibility with frontend
  apps[k][p] = m.to_s
```

## Implementation Checklist

When adding new MDSL parameters:

- [ ] Determine parameter type (boolean, array, object, string, numeric)
- [ ] If boolean feature flag: Add to type-preservation list in `websocket.rb`
- [ ] If array/object: Add explicit `.to_json` handling
- [ ] If numeric: Consider whether explicit type preservation is needed
- [ ] Update this document with new parameter
- [ ] Add integration test for app switching behavior

## Testing Strategy

### Unit Tests

Test type conversion in isolation:
```ruby
# spec/unit/utils/websocket_type_conversion_spec.rb
describe "prepare_apps_data type conversion" do
  it "preserves boolean feature flags" do
    result = prepare_apps_data_for_test(auto_speech: false)
    expect(result["auto_speech"]).to be false
    expect(result["auto_speech"]).not_to eq "false"
  end
end
```

### Integration Tests

Test app switching behavior:
```ruby
# spec/integration/app_switching_spec.rb
it "resets feature flags when switching apps" do
  # Switch from Voice Chat (auto_speech: true) to Chat (auto_speech: false)
  # Verify UI checkboxes reflect correct state
  # Verify params hash has correct boolean values
end
```

## Common Pitfalls

### ❌ DON'T: Trust string booleans in JavaScript

```javascript
// WRONG
if (params["auto_speech"]) {
  // "false" would be truthy!
}
```

### ✅ DO: Use toBool helper

```javascript
// CORRECT
if (toBool(params["auto_speech"])) {
  // Handles both boolean and string correctly
}
```

### ❌ DON'T: Convert booleans to strings in setParams

```javascript
// WRONG
params["mathjax"] = "true";
```

### ✅ DO: Use actual boolean values

```javascript
// CORRECT
params["mathjax"] = true;
```

### ❌ DON'T: Add new boolean parameters without updating type list

```ruby
# WRONG - new parameter will be stringified
features do
  my_new_boolean_flag true
end
```

### ✅ DO: Add to type-preservation list

```ruby
# CORRECT - add to websocket.rb
elsif ["auto_speech", ..., "my_new_boolean_flag"].include?(p.to_s)
  apps[k][p] = m
```

## Backward Compatibility

The `toBool` helper function ensures backward compatibility:

```javascript
// Handles legacy string values
toBool("true")  → true
toBool("false") → false

// Handles modern boolean values
toBool(true)    → true
toBool(false)   → false

// Handles edge cases
toBool(null)    → false
toBool(undefined) → false
toBool(0)       → false
toBool(1)       → true
```

Some existing code explicitly checks for string "true":
```javascript
if (params["pdf"] === "true" || params["pdf_vector_storage"] === true)
```

This pattern provides backward compatibility and should be maintained where it exists.

## Migration Guide

If you encounter type-related bugs:

1. **Identify the affected parameter**
   - Check if it's a boolean that should toggle behavior
   - Verify current type in browser console: `typeof params["param_name"]`

2. **Add to type-preservation list**
   - Edit `lib/monadic/utils/websocket.rb`
   - Add parameter name to the elsif condition

3. **Add defensive checks**
   - Use `toBool()` in JavaScript where the parameter is evaluated
   - Both in `loadParams()` and `proceedWithAppChange()`

4. **Test thoroughly**
   - Test app switching with various combinations
   - Verify checkbox states in UI
   - Check params hash in browser console

5. **Update documentation**
   - Add parameter to this document
   - Update MDSL documentation if needed

## Related Documentation

- `docs_dev/common-issues.md` - Troubleshooting guide
- `docs/advanced-topics/monadic_dsl.md` - MDSL syntax reference
- `docs_dev/app_isolation_and_session_safety.md` - Session safety guidelines
- `docs_dev/mdsl/mdsl_type_reference.md` - MDSL type definitions

## Revision History

- 2024-01: Initial documentation after boolean feature flags fix
- Feature flags affected: All 16 boolean parameters
- Files modified: `websocket.rb`, `utilities.js`, `monadic.js`, `websocket.js`
