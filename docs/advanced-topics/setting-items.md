# Application Setting Items

Applications in Monadic Chat are defined using MDSL (Monadic Domain Specific Language) files with the `.mdsl` extension. These settings configure the behavior, appearance, and capabilities of each application.

<!-- > 📸 **Screenshot needed**: MDSL file open in text editor showing app configuration -->

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
- `app "AppName"` - The app identifier. Must match the Ruby class name exactly (e.g., `app "ChatOpenAI"` requires `class ChatOpenAI`)
- `description` - Brief description of the application's purpose
- `icon` - Icon identifier (Font Awesome class or built-in icon name)
- `system_prompt` - The system instructions for the AI model

### LLM Configuration
The `llm` block is required and contains:
- `provider` - The AI provider (openai, claude, gemini, etc.)
- `model` - The specific model to use

## Optional Settings

### LLM Block Options
- `temperature` - Controls randomness in responses. Range and availability depend on provider and model. Some models (e.g., OpenAI o1/o3, Gemini 2.5 thinking models) don't support temperature adjustment

- `max_tokens` - Maximum tokens in response (availability and limits vary by model)
- `presence_penalty` - Penalize repeated topics. Supported by some OpenAI and Mistral models
- `frequency_penalty` - Penalize repeated words. Supported by some OpenAI and Mistral models

### Features Block
All settings in the features block are optional:

#### Display and Interaction
- `display_name` - Name shown in the UI (defaults to app name)
- `group` - Menu group name for organizing apps in the UI. By default, apps are automatically grouped by their provider (e.g., "OpenAI", "Anthropic"). You can override this to create custom groups, but it's recommended to keep the default provider-based grouping
- `disabled` - Hide app from menu when true
- `easy_submit` - Send messages with Enter key alone
- `auto_speech` - Auto-play AI responses as speech
- `initiate_from_assistant` - Start conversation with AI message

#### Content Features
- `pdf_vector_storage` - Enable PDF database functionality for RAG (Retrieval-Augmented Generation). Shows PDF import button and database panel in the UI
- `file` - Enable text file uploads
- `websearch` - Enable web search capability
- `image_generation` - Enable AI image generation capabilities. Accepts:
  - `true` - Full image generation (create, edit, variations)
  - `"upload_only"` - Image upload only (no generation/editing)
  - `false` - Disabled (default)
- `mermaid` - Enable Mermaid diagram rendering
- `abc` - Enable ABC music notation
- `mathjax` - Enable LaTeX math rendering

#### Context Management
- `context_size` - Number of previous messages to include
- `monadic` - Enable JSON-based state management (available across providers with varying capabilities)
- `toggle` - Enable collapsible sections (Claude/Gemini/Mistral/Cohere)
- `prompt_suffix` - Text appended to every user message

!> **Important:** Never enable both `monadic` and `toggle` - they are mutually exclusive display modes.

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
- `response_format` - Specify structured output format (OpenAI)
- `reasoning_effort` - For reasoning models: "low" (default), "medium", "high"
- `models` - Override available model list
- `jupyter` - Enable Jupyter notebook access (disabled in Server Mode unless `ALLOW_JUPYTER_IN_SERVER_MODE=true`)

!> **Important:** The `jupyter` feature only enables the UI capability. Actual Jupyter functionality requires implementing corresponding tool definitions (such as `run_jupyter`, `create_jupyter_notebook`, etc.) in your app. See the Jupyter Notebook app implementation for examples.

## System-Level Settings

These are configured in the Monadic Chat settings panel, not in MDSL files:

- API keys for various providers (OpenAI, Claude, Gemini, etc.)
- Tavily API key for web search
- Syntax highlighting theme
- Speech-to-text model selection

Settings are loaded at application startup and persist between sessions.

## Complete Example

```ruby
app "ChatOpenAI" do
  description "General-purpose chat application with OpenAI"
  icon "fa-comments"

  llm do
    provider "openai"
    model ["<model-1>", "<model-2>"]  # Array of model IDs for user selection
    reasoning_effort "minimal"
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
