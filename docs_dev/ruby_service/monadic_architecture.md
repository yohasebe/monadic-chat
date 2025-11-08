# Monadic Architecture Documentation (Server-side Concepts)

## Overview

The monadic functionality in Monadic Chat provides a structured way to manage conversation state and context across AI interactions. This refactored architecture maintains 100% backward compatibility while enabling future extensions.

## Quick Start

The monadic functionality is automatically included in all MonadicApp instances. No changes are needed to existing apps - they continue to work exactly as before.

```ruby
# Existing code works without modification
class MyApp < MonadicApp
  def process
    monad = monadic_unit("Hello")          # Wrap in JSON
    result = monadic_map(monad) { |ctx|    # Transform context
      ctx["processed"] = true
      ctx
    }
    result                                   # return JSON string (client renders HTML)
  end
end
```

## Architecture Structure

```
lib/monadic/
├── core.rb           # Core functional programming concepts
├── json_handler.rb   # JSON serialization/deserialization
├── app_extensions.rb # MonadicApp integration layer
└── README.md         # This documentation
```

## Module Hierarchy

```
Monadic::Core
    ↑
Monadic::JsonHandler
    ↑
Monadic::AppExtensions → MonadicApp
```

## Core Concepts

### 1. Monadic::Core

Provides pure functional programming operations:

- **`wrap(value, context)`** - Create monadic structure
- **`unwrap(monad)`** - Extract value from monad
- **`transform(monad, &block)`** - Map over monadic value
- **`bind(monad, &block)`** - FlatMap operation
- **`combine(monad1, monad2)`** - Combine two monads

### 2. Monadic::JsonHandler

JSON-specific operations:

- **`wrap_as_json(message, context)`** - Compatible with `monadic_unit`
- **`unwrap_from_json(json)`** - Compatible with `monadic_unwrap`
- **`transform_json(json, &block)`** - Compatible with `monadic_map`
- **`validate_json_structure(data, expected)`** - Structure validation

### 3. Monadic::AppExtensions

Integration layer providing:

- Backward compatible methods
- Enhanced FP operations
- Context management
- Validation utilities

## Usage Example

```ruby
# Pure functional style
pure_value = monadic_pure("Hello")

# Bind operation
result = monadic_bind(monad) do |value, context|
  # Return new monad
  monadic_unit("Processed: #{value}")
end

# Validation
validation = validate_monadic_structure(monad, {
  "message" => String,
  "context" => Hash
})
```

## Extension Points

### 1. Custom Serialization

```ruby
module Monadic
  module XmlHandler
    include Core
    
    def wrap_as_xml(value, context)
      # Custom XML serialization
    end
  end
end
```

### 2. Provider-Specific Handling

```ruby
module Monadic
  class GeminiStrategy
    def format_for_gemini(monad)
      # Gemini-specific formatting
    end
  end
end
```

### 3. Context Strategies

```ruby
module Monadic
  module ContextPruning
    def prune_context(context, max_size)
      # Implement pruning logic
    end
  end
end
```

## Implementation Status

### Current State
- ✅ Module architecture implemented and tested
- ✅ All 6 monadic apps working with new architecture
- ✅ Performance improvements verified (50x faster for Hash operations)
- ✅ Full backward compatibility maintained
- ✅ Enhanced UI for empty objects in monadic context

### Monadic Apps Using This Architecture
1. **Chat Plus** - Reasoning and context tracking
2. **Jupyter Notebook** - State management
3. **Language Practice Plus** - Learning progress tracking
4. **Novel Writer** - Story state management
5. **Translate** - Translation context
6. **Voice Interpreter** - Voice context awareness

### UI Enhancements
- Empty objects display ": empty" instead of showing empty content
- Field labels are more prominent with increased font weight
- "no value" text is styled in italic gray
- Improved visual hierarchy for better readability

## Best Practices

1. **Maintain Immutability**: Don't modify monadic values directly
2. **Use Type Checking**: Validate structures when accepting external input
3. **Handle Errors Gracefully**: Always provide fallbacks for JSON parsing
4. **Document Context Structure**: Clearly define expected context fields

## Testing

### Unit Tests

```ruby
# Test core operations
describe Monadic::Core do
  it "wraps values correctly" do
    monad = wrap("test", { id: 1 })
    expect(monad.value).to eq("test")
    expect(monad.context).to eq({ id: 1 })
  end
end
```

### Integration Tests

```ruby
# Test with actual apps
describe "Monadic Apps" do
  it "maintains backward compatibility" do
    app = ChatPlusOpenAI.new
    monad = app.monadic_unit("Hello")
    expect(monad).to be_json
  end
end
```

## Contributing

When adding new monadic features:

1. Extend modules, don't modify existing methods
2. Maintain backward compatibility
3. Add tests for new functionality
4. Update documentation
5. Consider provider differences

## References

- [Functional Programming in Ruby](https://www.rubyguides.com/2018/10/functional-programming-ruby/)
- [Monad Design Pattern](https://en.wikipedia.org/wiki/Monad_(functional_programming))
- [JSON Schema Specification](https://json-schema.org/)
