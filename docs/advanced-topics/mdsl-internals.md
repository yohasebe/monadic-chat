# MDSL Internals

?> This document explains how Monadic DSL (MDSL) works internally. It's intended for developers who want to understand the implementation or contribute to its development.

## 1. Overview

Monadic DSL (MDSL) is a Ruby-based domain-specific language that simplifies AI application development by abstracting provider differences and offering a declarative syntax.

### 1.1 Core Architecture

#### 1.1.1 Provider Abstraction
MDSL supports multiple LLM providers through a unified interface:
- **OpenAI** - [https://openai.com](https://openai.com)
- **Anthropic** (Claude) - [https://anthropic.com](https://anthropic.com)
- **Google** (Gemini) - [https://ai.google.dev](https://ai.google.dev)
- **Mistral** - [https://mistral.ai](https://mistral.ai)
- **Cohere** - [https://cohere.com](https://cohere.com)
- **DeepSeek** - [https://deepseek.com](https://deepseek.com)
- **Perplexity** - [https://perplexity.ai](https://perplexity.ai)
- **xAI** (Grok) - [https://x.ai](https://x.ai)
- **Ollama** - [https://ollama.ai](https://ollama.ai)

#### 1.1.2 Critical Naming Convention
?> **Important**: The MDSL app name must exactly match the Ruby class name. For example, `app "ChatOpenAI"` requires a corresponding `class ChatOpenAI < MonadicApp`. This ensures proper menu grouping and functionality.

#### 1.1.3 File Organization
```
apps/
├── chat/
│   ├── chat_openai.mdsl
│   ├── chat_openai.rb
│   └── chat_tools.rb
└── second_opinion/
    ├── second_opinion_openai.mdsl
    ├── second_opinion_tools.rb
    └── ...
```


### 1.2 Key Design Principles

1. **Declarative Syntax** - Define apps without implementation details
2. **Provider Independence** - Switch providers with minimal changes
3. **Tool Format Unification** - Single syntax for all provider-specific formats
4. **Runtime Class Generation** - Convert DSL to Ruby classes dynamically
5. **Monadic Error Handling** - Explicit, chainable error management

## 2. DSL Structure and Processing

### 2.1 Basic App Definition
```ruby
app "AppNameProvider" do
  description "Brief description"
  icon "fa-icon"
  
  llm do
    provider "provider_name"
    model "model_name"
  end
  
  features do
    # Feature flags
  end
  
  tools do
    # Tool definitions
  end
  
  system_prompt "..."
end
```

### 2.2 Loading Process
1. **File Detection** - `.mdsl` extension or `app "Name" do` pattern
2. **Content Evaluation** - DSL evaluated with `eval` in safe context
3. **State Building** - Configuration collected in `AppState`
4. **Class Generation** - Dynamic Ruby class creation
5. **Module Inclusion** - Provider-specific helpers included

### 2.3 Provider Configuration
```ruby
PROVIDER_INFO = {
  "openai" => {
    helper_module: "OpenAIHelper",
    default_model: "gpt-4.1-mini",
    features: { monadic: true }
  },
  "anthropic" => {
    helper_module: "ClaudeHelper", 
    default_model: "claude-3-5-sonnet-20241022",
    features: { toggle: true, initiate_from_assistant: true }
  },
  # ... other providers
}
```

## 3. Feature Management

### 3.1 Provider-Specific Features
- `monadic` - JSON state management (supported by all providers)
- `toggle` - Collapsible UI sections (Claude, Gemini, Mistral, Cohere)
- `initiate_from_assistant` - Start with AI message (Claude, Gemini)

?> **Important**: Never enable both `monadic` and `toggle` - they are mutually exclusive.

### 3.2 Model-Specific Behaviors
- **Reasoning Models** - o1, o3 don't support temperature adjustment
- **Thinking Models** - Gemini 2.5 uses `reasoning_effort` instead of temperature
- **Web Search Fallback** - Reasoning models use `WEBSEARCH_MODEL` for web queries

## 4. Tool System

### 4.1 Unified Tool Definition
```ruby
tools do
  define_tool "tool_name", "Description" do
    parameter :param, "type", "description", required: true
  end
end
```

### 4.2 Provider Formatters
Each provider has a dedicated formatter that transforms abstract definitions:

```ruby
FORMATTERS = {
  openai: ToolFormatters::OpenAIFormatter,
  anthropic: ToolFormatters::AnthropicFormatter,
  gemini: ToolFormatters::GeminiFormatter,
  # ... other providers
}
```

## 5. Runtime Behavior

### 5.1 Class Generation
MDSL dynamically generates Ruby classes:
```ruby
class AppNameProvider < MonadicApp
  include ProviderHelper
  
  @settings = { /* from DSL */ }
  @app_name = "AppNameProvider"
  
  # Tool methods included from facade modules
end
```

### 5.2 Error Handling
Uses monadic patterns for chainable error handling:
```ruby
Result.new(value)
  .bind { |v| validate(v) }
  .map { |v| transform(v) }
  .bind { |v| save(v) }
```

## 6. Common Issues

1. **Menu grouping problems** - Check app name matches class name
2. **Missing models** - Ensure helper's `list_models` uses `$MODELS` cache
3. **Tool not found** - Verify facade module is included
4. **Feature conflicts** - Check `monadic`/`toggle` exclusivity

?> **For debugging**: Enable "Extra Logging" in the Console Panel settings to get detailed logs when troubleshooting issues.

## 7. Best Practices

1. **Follow naming conventions** - App identifier must match class name
2. **Use facade pattern** - Implement tools in separate `*_tools.rb` files
3. **Respect feature constraints** - Don't mix incompatible features
4. **Test with multiple providers** - Ensure portability
5. **Handle errors gracefully** - Use monadic patterns

## See Also

- [Monadic DSL](./monadic_dsl.md) - User-facing DSL documentation
- [Developing Apps](./develop_apps.md) - App development guide
- [Setting Items](./setting-items.md) - Configuration reference