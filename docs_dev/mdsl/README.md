# MDSL Documentation

This section contains internal documentation for Monadic DSL (MDSL), the domain-specific language used to define Monadic Chat applications.

## Contents

- [MDSL Type Reference](mdsl_type_reference.md) - Complete type system reference for MDSL

## Overview

Monadic DSL (MDSL) is a declarative language for defining intelligent chat applications. It provides:

- **App Definition**: Properties, settings, and metadata
- **Tool Methods**: Function definitions with JSON Schema for parameters
- **Response Handling**: Structured response formatting
- **Template System**: ERB templates for prompts and responses
- **Type System**: Rich type annotations for parameters and returns

## Quick Example

```ruby
app "Example App" do
  version "1.0.0"
  author "Developer"
  description "An example application"
  icon "🎯"

  initial_prompt "You are a helpful assistant."

  tool "example_tool" do
    description "Example tool description"
    parameter "input", type: "string", description: "User input", required: true

    execute do |input:|
      result = process(input)
      format_tool_response(success: true, output: result)
    end
  end
end
```

## Related Documentation

- `docs/advanced-topics/monadic_dsl.md` - Public MDSL reference for app developers
- `lib/monadic/dsl.rb` - MDSL implementation source code
- `apps/` - Example MDSL applications

See also:
- [Ruby Service](../ruby_service/) - Backend implementation details
- [App Isolation & Session Safety](../app_isolation_and_session_safety.md) - Best practices for app development
