# MDSL Type Reference

## Overview

This document provides a complete type reference for Monadic DSL (MDSL) parameters. It complements the [Type Conversion Policy](/type_conversion_policy.md) by specifying expected types for each MDSL setting.

## Parameter Type Reference

### Boolean Feature Flags

All boolean feature flags MUST use actual boolean values (`true`/`false`), not strings.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `auto_speech` | Boolean | `false` | Enables automatic text-to-speech for assistant messages |
| `easy_submit` | Boolean | `false` | Enables submitting messages on Enter key |
| `initiate_from_assistant` | Boolean | `false` | Allows assistant to send first message |
| `mathjax` | Boolean | `false` | Enables mathematical notation rendering |
| `mermaid` | Boolean | `false` | Enables Mermaid diagram rendering |
| `abc` | Boolean | `false` | Enables ABC music notation rendering |
| `monadic` | Boolean | `false` | Enables monadic mode with JSON context |
| `pdf_vector_storage` | Boolean | `false` | Enables vector storage for PDF |
| `websearch` | Boolean | `false` | Enables web search functionality |
| `jupyter` | Boolean | `false` | Enables Jupyter notebook access |
| `image_generation` | Boolean | `false` | Enables AI image generation |
| `video` | Boolean | `false` | Enables video upload and processing |

**Example**:
```ruby
app "MyApp" do
  features do
    auto_speech true        # ✅ Correct: boolean
    easy_submit true        # ✅ Correct: boolean
  end
end
```

**Common Mistakes**:
```ruby
features do
  auto_speech "true"        # ❌ Wrong: string
  easy_submit "false"       # ❌ Wrong: string (will be truthy!)
end
```

### String Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `app_name` | String | No* | Application identifier (auto-derived from class name) |
| `display_name` | String | Yes | Display name shown in UI |
| `description` | String or Hash | Yes | App description (single string or multi-language hash) |
| `icon` | String | Yes | FontAwesome icon or emoji |
| `initial_prompt` | String | Yes | System prompt for the model |
| `system_prompt` | String | No | Alias for `initial_prompt` |
| `group` | String | No | Provider group (e.g., "OpenAI", "Anthropic") |
| `provider` | String | Yes | Provider name (e.g., "openai", "anthropic") |

*`app_name` is typically auto-derived from the app declaration name.

**Example**:
```ruby
app "ChatOpenAI" do
  display_name "Chat"
  icon "comment"
  description "A conversational AI assistant"

  # Or multi-language description
  description do
    en "A conversational AI assistant"
    ja "会話型AIアシスタント"
    zh "对话型AI助手"
  end

  system_prompt <<~PROMPT
    You are a helpful assistant.
  PROMPT

  llm do
    provider "openai"
  end
end
```

### Array Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `model` | Array of Strings | Available model choices for the app |

**Example**:
```ruby
llm do
  provider "openai"
  model ["gpt-5", "gpt-4.1", "gpt-4.1-mini"]  # ✅ Correct: array of strings
end
```

**Common Mistakes**:
```ruby
llm do
  model "gpt-5"  # ❌ Wrong: single string instead of array
end
```

### Numeric Parameters

| Parameter | Type | Range | Description |
|-----------|------|-------|-------------|
| `temperature` | Float | 0.0-2.0 | Randomness in model responses |
| `context_size` | Integer | 1+ | Number of messages to send as context |
| `max_tokens` | Integer | 1+ | Maximum tokens to generate |

**Example**:
```ruby
llm do
  temperature 0.7
  max_tokens 2000
  context_size 10
end
```

**Note**: These are currently converted to strings during transmission but JavaScript handles this gracefully through type coercion. Explicit type preservation may be added in future if numeric comparisons become problematic.

### Enum Parameters

| Parameter | Type | Valid Values | Description |
|-----------|------|--------------|-------------|
| `reasoning_effort` | String | "minimal", "low", "medium", "high" | OpenAI reasoning effort level |

**Provider-Specific**:
- **OpenAI**: "minimal", "low", "medium", "high"
- **Anthropic**: Budget values (integers) via thinking budget
- **Google**: Config object via thinking config

**Example**:
```ruby
llm do
  provider "openai"
  model ["gpt-5"]
  reasoning_effort "medium"  # ✅ Correct: string enum value
end
```

### Complex Parameters

#### tools

**Type**: Hash (converted to JSON)

**Description**: Tool definitions for function calling

**Example**:
```ruby
tools do
  define_tool "search_web", "Search the web for information" do
    parameter :query, "string", "Search query", required: true
    parameter :limit, "integer", "Maximum results", required: false
  end

  define_tool "calculate", "Perform calculations" do
    parameter :expression, "string", "Mathematical expression", required: true
  end
end
```

**Internal Representation**:
```ruby
# Converted to hash structure
{
  "search_web" => {
    name: "search_web",
    description: "Search the web for information",
    parameters: {
      query: { type: "string", description: "Search query" },
      limit: { type: "integer", description: "Maximum results" }
    },
    required: ["query"]
  },
  # ...
}
```

#### context_management

**Type**: Hash

**Description**: Monadic context management configuration

**Example**:
```ruby
context_management do
  edits [
    {
      role: "user",
      content: "Update context based on conversation"
    }
  ]
end
```

### Special Parameters

#### disabled

**Type**: Boolean expression result as String

**Description**: Controls app availability based on conditions

**Example**:
```ruby
features do
  disabled !CONFIG["OPENAI_API_KEY"]  # Evaluates to "true" or "false" string
end
```

**Why String**:
- Evaluated in Ruby as boolean expression
- Sent to frontend as string for display purposes
- Frontend checks for truthiness

## Type Validation

### Runtime Validation

The MDSL loader includes basic validation:

```ruby
# lib/monadic/dsl.rb
def validate!
  raise ValidationError, "Name is required" unless @name
  raise ValidationError, "Settings are required" if @settings.empty?
  raise ValidationError, "Provider is required" unless @settings[:provider]
  true
end
```

### Adding New Parameters

When adding new MDSL parameters:

1. **Determine the type category**:
   - Boolean feature flag? → Add to type-preservation list in `websocket.rb`
   - Array/Object? → Add explicit `.to_json` handling
   - Numeric? → Consider type preservation needs
   - String? → Default handling is fine

2. **Update DSL parser** (if needed):
   - Add method to appropriate context class
   - Add to `FEATURE_MAP` if it's a feature flag

3. **Update documentation**:
   - Add to this type reference
   - Update `monadic_dsl.md` with usage examples
   - Update `type_conversion_policy.md` with handling details

4. **Add tests**:
   - Unit test for DSL parsing
   - Integration test for app switching
   - Type consistency test

### Example: Adding a New Boolean Feature

```ruby
# 1. Define in MDSL
app "MyApp" do
  features do
    my_new_feature true  # New boolean flag
  end
end

# 2. Add to type-preservation list (websocket.rb)
elsif ["auto_speech", ..., "my_new_feature"].include?(p.to_s)
  apps[k][p] = m

# 3. Use in JavaScript with toBool
if (toBool(apps[appValue]["my_new_feature"])) {
  // Enable feature
}

# 4. Add test
it "preserves my_new_feature boolean value" do
  # Test app switching preserves correct boolean
end
```

## Type Coercion Rules

### Ruby → JSON

| Ruby Type | JSON Type | Notes |
|-----------|-----------|-------|
| `true`/`false` | Boolean | Preserved for feature flags |
| `Array` | Array | JSON-serialized via `.to_json` |
| `Hash` | Object | JSON-serialized via `.to_json` |
| `String` | String | Direct conversion |
| `Integer` | Number* | Currently stringified, but parseable |
| `Float` | Number* | Currently stringified, but parseable |
| `nil` | null | Converted to JSON null |

*Numeric types are currently converted to strings during transmission.

### JSON → JavaScript

| JSON Type | JavaScript Type | Usage |
|-----------|-----------------|-------|
| Boolean | Boolean | Direct evaluation: `if (value)`|
| String | String | Needs `toBool()` for "true"/"false" |
| Array | Array | Needs `JSON.parse()` if stringified |
| Object | Object | Needs `JSON.parse()` if stringified |
| Number | Number | Auto-coercion from string works |
| null | null | Falsy value |

## Common Type Pitfalls

### 1. String Boolean Evaluation

```javascript
// ❌ Problem
"false" → truthy (evaluates to true)
"true"  → truthy (evaluates to true)

// ✅ Solution
toBool("false") → false
toBool("true")  → true
```

### 2. Array as String

```javascript
// ❌ Problem
typeof apps[appValue]["models"] === "string"  // "[\"gpt-5\",\"gpt-4.1\"]"

// ✅ Solution
const models = JSON.parse(apps[appValue]["models"]);
```

### 3. Numeric String Comparison

```javascript
// ⚠️ Be Careful
"10" > "2"  // false (string comparison)
10 > 2      // true (numeric comparison)

// ✅ Safe
parseInt("10", 10) > parseInt("2", 10)  // true
```

### 4. Null vs Undefined vs False

```javascript
// All falsy, but different
if (null) { }        // doesn't execute
if (undefined) { }   // doesn't execute
if (false) { }       // doesn't execute

// But different in strict equality
null === undefined        // false
null === false           // false
undefined === false      // false

// Use toBool for consistent handling
toBool(null)      → false
toBool(undefined) → false
toBool(false)     → false
```

## Best Practices

### 1. Always Use Correct Types in MDSL

```ruby
# ✅ Good
features do
  auto_speech true

  easy_submit true
end

# ❌ Bad
features do
  auto_speech "true"
  image "false"
  easy_submit 1  # Will work but inconsistent
end
```

### 2. Use toBool for Feature Flags

```javascript
// ✅ Always use toBool for feature flags
if (toBool(params["auto_speech"])) {
  enableTTS();
}

// ❌ Don't trust direct evaluation
if (params["auto_speech"]) {  // Could be string "false"!
  enableTTS();
}
```

### 3. Parse JSON Arrays/Objects

```javascript
// ✅ Parse when needed
const models = JSON.parse(apps[appValue]["models"]);
const tools = JSON.parse(apps[appValue]["tools"]);

// ❌ Don't use stringified version directly
if (apps[appValue]["models"].includes("gpt-5")) {  // Wrong!
}
```

### 4. Explicit Type Conversion for Numbers

```javascript
// ✅ Explicit conversion
const temp = parseFloat(params["temperature"]);
const size = parseInt(params["context_size"], 10);

// ⚠️ Implicit conversion (usually works, but be aware)
if ($("#temperature").val() > 0.5) {  // Auto-coercion
}
```

## Related Documentation

- [Type Conversion Policy](/type_conversion_policy.md) - Overall policy document
- [Monadic DSL Documentation](../../docs/advanced-topics/monadic_dsl.md) - User-facing DSL guide
- [Common Issues](/common-issues.md) - Troubleshooting guide

## Revision History

- 2025-01: Initial type reference documentation
- Added comprehensive boolean feature flag types
- Documented type coercion rules
- Added common pitfalls and best practices
