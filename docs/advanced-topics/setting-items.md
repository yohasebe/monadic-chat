# Application Setting Items

Applications in Monadic Chat are defined using MDSL (Monadic Domain Specific Language) files with the `.mdsl` extension. These settings configure the behavior, appearance, and capabilities of each application.

## Basic MDSL Structure

```ruby
app "AppNameProvider" do
  description "Brief description of the app"
  icon "fa-icon-name"
  display_name "Display Name"
  
  llm do
    provider "provider_name"
    model "model_name"
    temperature 0.7
  end
  
  features do
    # Feature settings here
  end
  
  tools do
    # Tool definitions here
  end
  
  system_prompt <<~TEXT
    System prompt text goes here
  TEXT
end
```

## Required Settings

### App Definition
- **`app "AppName"`** - The app identifier. Must match the Ruby class name exactly (e.g., `app "ChatOpenAI"` requires `class ChatOpenAI`)
- **`description`** - Brief description of the application's purpose
- **`icon`** - Icon identifier (Font Awesome class or built-in icon name)
- **`system_prompt`** - The system instructions for the AI model

### LLM Configuration
The `llm` block is required and contains:
- **`provider`** - The AI provider (openai, claude, gemini, etc.)
- **`model`** - The specific model to use

## Optional Settings

### LLM Block Options
- **`temperature`** - Controls randomness in responses. Range and availability depend on provider and model. Some models (e.g., OpenAI o1/o3, Gemini 2.5 thinking models) don't support temperature adjustment
- **`max_tokens`** - Maximum tokens in response (availability and limits vary by model)
- **`presence_penalty`** - Penalize repeated topics. Supported by some OpenAI and Mistral models
- **`frequency_penalty`** - Penalize repeated words. Supported by some OpenAI and Mistral models

### Features Block
All settings in the features block are optional:

#### Display and Interaction
- **`display_name`** - Name shown in the UI (defaults to app name)
- **`group`** - Menu group name for organizing apps in the UI. By default, apps are automatically grouped by their provider (e.g., "OpenAI", "Anthropic"). You can override this to create custom groups, but it's recommended to keep the default provider-based grouping
- **`disabled`** - Hide app from menu when true
- **`easy_submit`** - Send messages with Enter key alone
- **`auto_speech`** - Auto-play AI responses as speech
- **`initiate_from_assistant`** - Start conversation with AI message

#### Content Features
- **`pdf_vector_storage`** - Enable PDF database functionality for RAG (Retrieval-Augmented Generation). Shows PDF import button and database panel in the UI
- **`file`** - Enable text file uploads
- **`websearch`** - Enable web search capability
- **`image_generation`** - Enable AI image generation capabilities. Accepts:
  - `true` - Full image generation (create, edit, variations)
  - `"upload_only"` - Image upload only (no generation/editing)
  - `false` - Disabled (default)
- **`mermaid`** - Enable Mermaid diagram rendering
- **`abc`** - Enable ABC music notation
- **`sourcecode`** - Enable syntax highlighting
- **`mathjax`** - Enable LaTeX math rendering

#### Context Management
- **`context_size`** - Number of previous messages to include
- **`monadic`** - Enable JSON-based state management (OpenAI/Ollama only)
- **`toggle`** - Enable collapsible sections (Claude/Gemini/Mistral/Cohere)
- **`prompt_suffix`** - Text appended to every user message

?> **Important**: Never enable both `monadic` and `toggle` - they are mutually exclusive and provider-specific.

### Tools Block
Define functions the AI can use:

```ruby
tools do
  define_tool "tool_name", "Tool description" do
    parameter :param_name, "type", "description", required: true
  end
end
```

### Advanced Settings
- **`response_format`** - Specify structured output format (OpenAI)
- **`reasoning_effort`** - For thinking models (replaces temperature)
- **`models`** - Override available model list
- **`jupyter`** - Enable Jupyter notebook access (disabled in Server Mode unless `ALLOW_JUPYTER_IN_SERVER_MODE=true`). Note: This only enables the capability; actual Jupyter functionality requires corresponding tool definitions like `run_jupyter`, `create_jupyter_notebook`, etc.

## Provider-Specific Behaviors

### OpenAI
- Supports `monadic` mode for structured outputs
- Most models support `temperature`, `presence_penalty`, `frequency_penalty`
- Reasoning models (o1, o3) don't support these parameters and use fixed settings

### Claude
- Uses `toggle` mode for context display
- Requires `initiate_from_assistant: true`
- Supports thinking models with `reasoning_effort`

### Gemini
- Uses `toggle` mode
- Requires `initiate_from_assistant: true`
- Thinking models (e.g., 2.5 Flash Thinking) use `reasoning_effort` instead of temperature
- Standard models support temperature adjustment

### Mistral
- Uses `toggle` mode
- Requires `initiate_from_assistant: false`
- Supports `presence_penalty` and `frequency_penalty`

## System-Level Settings

These are configured in the Monadic Chat UI, not in MDSL files:

- **`AI_USER_MODEL`** - Model for AI-generated user messages
- **`AI_USER_MAX_TOKENS`** - Max tokens for user message generation (default: 2000)
- **`WEBSEARCH_MODEL`** - Model for web search (gpt-4.1-mini or gpt-4.1)
- **`STT_MODEL`** - Speech-to-text model
- **`ROUGE_THEME`** - Syntax highlighting theme

## Complete Example

```ruby
app "ChatOpenAI" do
  description "General-purpose chat application with OpenAI"
  icon "fa-comments"
  
  llm do
    provider "openai"
    model "gpt-4.1-mini"
    temperature 0.7
    max_tokens 4000
  end
  
  features do
    easy_submit true
    auto_speech false
    context_size 20
    monadic false
    # Note: Image upload is automatically enabled for models with vision capability
    websearch true
  end
  
  tools do
    # Empty block required even if using only standard tools
  end
  
  system_prompt <<~TEXT
    You are a helpful AI assistant.
  TEXT
end
```

## See Also

- [Monadic DSL](./monadic_dsl.md) - Complete MDSL syntax reference
- [Developing Apps](./develop_apps.md) - Guide to creating apps
- [Recipe Examples](./recipe-examples.md) - Example implementations