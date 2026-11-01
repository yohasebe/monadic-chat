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
- `app "AppName"` - The app name, which is also the name of the generated Ruby class (e.g., `app "ChatOpenAI"`)
- `description` - Brief description of the application's purpose
- `icon` - Icon identifier (Font Awesome class or icon name)
- `system_prompt` - The system instructions for the AI model

When `description`, `icon` or `system_prompt` is missing, the app still loads with a default, and its description shows a warning.

### App-Level Optional Settings
- `display_name` - Name shown in the UI (defaults to the app name). Written at the app level, alongside `description` and `icon`, not inside `features`

### LLM Configuration
The `llm` block contains:
- `provider` - The AI provider (`openai`, `anthropic`, `gemini`, `mistral`, `cohere`, `deepseek`, `xai`, `ollama`)
- `model` - The model, or an array of models for a menu. When omitted, the provider's default model is used

## Optional Settings

### LLM Block Options
- `temperature` - Controls randomness in responses (0.0-2.0, default 0.7). The range a model accepts depends on the provider and model, and some reasoning models do not accept it

- `max_tokens` - Maximum tokens in response (availability and limits vary by model)
- `presence_penalty` - Penalize repeated topics. Supported by some OpenAI and Mistral models
- `frequency_penalty` - Penalize repeated words. Supported by some OpenAI and Mistral models

### Features Block
All settings in the features block are optional:

#### Display and Interaction
- `group` - Menu group name for organizing apps in the UI. By default, apps are grouped by their provider (e.g., "OpenAI", "Anthropic")
- `disabled` - Hide app from menu when true
- `easy_submit` - Send messages with Enter key alone
- `auto_speech` - Auto-play AI responses as speech
- `initiate_from_assistant` - Start conversation with AI message

#### Content Features
- `pdf_vector_storage` - Enable PDF database functionality for RAG (Retrieval-Augmented Generation). Shows PDF import button and database panel in the UI
- `websearch` - Enable web search capability
- `image_generation` - Enable AI image generation capabilities. Accepts:
  - `true` - Image generation and editing
  - `"upload_only"` - Image upload only (no generation/editing)
  - `false` - Disabled (default)
- `mermaid` - Enable Mermaid diagram rendering
- `abc` - Enable ABC music notation
- `math` - Enable LaTeX math rendering

#### Speech-to-Speech
These apply to Live Conversation apps, which stream the microphone to a provider's realtime API instead of using the text input panel:
- `speech_to_speech` - Turn the app into a speech-to-speech app (Start/Stop controls replace text input)
- `sts_input_rate` - Microphone sample rate in Hz (default 24000; Gemini Live consumes 16000)
- `sts_vad_threshold` - Voice-activity detection sensitivity, 0.0-1.0 (higher is less sensitive to background noise)
- `sts_vad_prefix_ms` - Audio kept before speech starts, in milliseconds
- `sts_vad_silence_ms` - Silence that ends a turn, in milliseconds
- `sts_vad_type` - Turn-detection mode: `server_vad` (default, silence-based) or `semantic_vad` (waits for semantic completion; OpenAI only)
- `sts_vad_eagerness` - How quickly `semantic_vad` ends a turn: `low`, `medium`, `high`, or `auto` (OpenAI only; ignored otherwise)
- `sts_idle_stop_seconds` - Stop the session after this much inactivity (default 180; 0 disables)

Omitted `sts_vad_*` keys fall back to the provider's defaults, and not every provider honors every key (xAI ignores `sts_vad_prefix_ms`). The OpenAI Live Conversation variant also exposes `sts_vad_type`/`sts_vad_eagerness` to the user as a turn-detection selector — a value chosen there overrides the MDSL default for the next session.

#### Context Management
- `context_size` - Number of recent messages sent to the model. It also sets the **Max Context Size** field in the web UI
- `monadic` - Enable Session State and Session Context; see [Monadic Mode](./monadic-mode.md)
- `toggle` - Render `<div class='toggle'>` blocks in responses as collapsible sections
- `prompt_suffix` - Text appended to every user message

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
- `response_format` - Specify a structured output format (OpenAI; Ollama maps it to its own `format` parameter)
- `reasoning_effort` - Control reasoning intensity for supported models. Available values depend on the model (e.g., "low", "high" for some models)
- `jupyter` - Enable Jupyter notebook access
- `reachable_skills` - Declare tool groups the app is allowed to acquire on demand during a conversation (written at the app level, outside the `tools` block). `reachable_skills :safe` expands to the curated set of read-only safe groups. See [Tool Groups](./tool-groups.md)
- `compaction` - Control server-side conversation compaction for providers whose APIs support it (written at the app level). OpenAI apps use the default threshold even without this directive; `compaction false` opts out, and a `compaction do ... end` block with `compact_threshold` sets a custom trigger threshold

!> **Important:** The `jupyter` feature only enables the UI capability. Actual Jupyter functionality requires implementing corresponding tool definitions (such as `create_jupyter_notebook` and `run_jupyter_cells`, from the `:jupyter_operations` group) in your app. See the Jupyter Notebook app implementation for examples.

## System-Level Settings

These are set in the **Settings** window (**Open → Settings**), not in MDSL files. Its categories are General, System, API Keys, Voice & Audio, Services, Install Options, Actions and About. Among the settings:

- API keys for the providers, ElevenLabs and Tavily
- UI language, Browser Mode, Launch at Login and Menu Bar Mode
- Extra Logging
- The TTS dictionary file and the size limit for Auto Speech
- The MCP server and its port
- [Install Options](./advanced-configuration.md#install-options), including the Privacy Filter languages and the Knowledge Base Quality Pack

The settings are saved in `~/monadic/config/env` and kept between sessions.

The speech-to-text model is selected in the **Speech** panel of the web UI (not in the Settings window or MDSL files); the choice is kept in a browser cookie.

## Complete Example

```ruby
app "ChatOpenAI" do
  description "General-purpose chat application with OpenAI"
  icon "fa-solid fa-comments"

  llm do
    provider "openai"
    model ["<model-1>", "<model-2>"]  # Array of model IDs for user selection
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
  
  system_prompt <<~TEXT
    You are a helpful AI assistant.
  TEXT
end
```

## See Also

- [Monadic DSL](./monadic_dsl.md) - Complete MDSL syntax reference
- [Developing Apps](./develop_apps.md) - Guide to creating apps
- [Recipe Examples](./recipe-examples.md) - Example implementations
