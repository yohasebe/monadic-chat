# MDSL Overview

?> This document provides an overview of how Monadic DSL (MDSL) works for app developers.

## What is MDSL?

Monadic DSL (MDSL) is a simple, Ruby-based language for creating AI applications in Monadic Chat. It handles the complexity of different AI providers so you can focus on building your app.

## Key Concepts

### 1. Provider Independence
Write your app once and it works with all supported providers:
- OpenAI (GPT models)
- Anthropic (Claude models)  
- Google (Gemini models)
- And many more

### 2. Naming Convention
**Important**: Your app name must match the Ruby class name:
- `app "ChatOpenAI"` requires `class ChatOpenAI < MonadicApp`
- This ensures proper menu grouping and functionality

### 3. File Organization
Keep your apps organized:
```
~/monadic/data/apps/
├── my_app/
│   ├── my_app_openai.mdsl    # App definition
│   ├── my_app_openai.rb      # Ruby implementation (optional)
│   └── my_app_tools.rb       # Shared tools (optional)
```

## Features You Can Use

### Available Features
- `monadic` - Enable JSON-based context management
- `context_size` - Set conversation history size
- `easy_submit` - Enable Enter key submission
- `auto_speech` - Enable automatic speech
- `image` - Allow image uploads
- `pdf` - Allow PDF uploads

### Provider-Specific Features
Some features work differently across providers:
- Web search capabilities
- Image generation
- Voice options

## Tool System

Define tools (functions) your AI can use:
```ruby
tools do
  define_tool "get_weather", "Get current weather" do
    parameter :location, "string", "City name", required: true
  end
end
```

The MDSL system automatically formats these for each provider.

## Best Practices

1. **Start Simple** - Begin with basic chat apps before adding complex tools
2. **Test Across Providers** - Ensure your app works with multiple AI providers
3. **Use Clear Descriptions** - Help users understand what your app does
4. **Follow Examples** - Look at existing apps for patterns and ideas

## Common Issues and Solutions

| Issue | Solution |
|-------|----------|
| App doesn't appear in menu | Check that app name matches class name |
| Tools not working | Verify tool definitions match system prompt |
| Features not available | Some features are provider-specific |

## Next Steps

- Read the [Monadic DSL Guide](./monadic_dsl.md) for detailed syntax
- See [Developing Apps](./develop_apps.md) for a complete tutorial
- Check [Basic Apps](../basic-usage/basic-apps.md) for examples

?> **Need Help?** Use the Monadic Help app for assistance with MDSL and app development.