# Monadic DSL (Domain Specific Language)

The Monadic DSL defines an app's behavior, interface and tools. This page describes its syntax.

## Introduction

Monadic DSL is a Ruby-based, declarative format for defining apps without writing the Ruby classes yourself.

## File Format

Apps are defined in `.mdsl` files (Monadic Domain Specific Language). From each file, Monadic Chat creates a Ruby class with the app's name.

## Basic Structure

A basic MDSL application definition looks like this:

```ruby
app "AppNameProvider" do  # The name of the generated class (e.g., ChatOpenAI)
  description "A brief description of what this application does"

  icon "fa-solid fa-icon-name"  # Font Awesome class or icon name

  llm do
    provider "anthropic"
    model "<model-id>"
    temperature 0.7
  end

  system_prompt <<~PROMPT
    Instructions for the AI model that define how it should behave
    in this specific application context.
  PROMPT

  features do
    auto_speech false
  end
end
```

Write the `llm` block before `tools` and `import_shared_tools`: tool definitions are formatted for the provider set at the time they are declared, and the provider is `openai` until the `llm` block sets it.

## Configuration Blocks

### 1. App Metadata

```ruby
app "AppNameProvider" do  # e.g., "ChatOpenAI", "CodingAssistantClaude", "ResearchAssistantGemini"
  description "Application description"
  # Or one description per UI language:
  # description do
  #   en "Application description"
  #   ja "アプリの説明"
  # end

  # Icon formats:
  icon "brain"                        # Simple name (becomes fa-solid fa-brain)
  # icon "github"                     # Known brand (becomes fa-brands fa-github)
  # icon "fa-regular fa-envelope"     # Full Font Awesome class with style prefix
  # icon "regular envelope"           # Style + name (becomes fa-regular fa-envelope)

  # For available icons, see: https://fontawesome.com/v6/search?ic=free

  display_name "Application Name"      # Name shown in the UI (default: the app name)
end
```

The menu group is set in the `features` block (`group "Category Name"`); by default it is the provider's group.

### 2. LLM Configuration

```ruby
llm do
  provider "anthropic"  # AI provider (anthropic, openai, cohere, etc.)
  model "<model-id>"  # Model name
  temperature 0.7  # Response randomness (0.0-2.0, default 0.7)
  max_tokens 4000  # Maximum response length
  reasoning_effort "high"  # Reasoning depth for reasoning-capable models
                           # (e.g., "low", "medium", "high"; when omitted,
                           # defaults to "none" = reasoning disabled)
end
```

The number of recent messages sent to the model is set with `context_size` in the `features` block; see [Feature Flags](#feature-flags).

Supported providers:
- `anthropic` (Claude models)
- `openai` (GPT models)
- `cohere` (Command models)
- `mistral` (Mistral models)
- `gemini` (Google Gemini models)
- `deepseek` (DeepSeek models)
- `xai` (Grok models)
- `ollama` (Local models via Ollama)

For a complete overview of which apps are compatible with which models, see the [App Availability by Provider](../basic-usage/basic-apps.md#app-availability) section in the Basic Apps documentation.

#### Model Specification Best Practices :id=model-specification-best-practices

**A fixed model**

```ruby
llm do
  provider "openai"
  model "<model-id>"
end
```

**The default model**

If you do not need a fixed model, omit `model` from the `llm` block:

```ruby
llm do
  provider "openai"
end
```

The model is then chosen by the order below, and the app definition does not need a model name.

**Configuration Priority**

Model values are resolved in this order (highest to lowest):

1. **Explicit MDSL value**: `model "<model-id>"` (highest priority)
2. **Environment variable**: for example `OPENAI_DEFAULT_MODEL` in `~/monadic/config/env`
3. **Provider defaults**: `providerDefaults` in `model_spec.js`

**Multiple Model Options**

Provide users with model choices using an array:

```ruby
llm do
  provider "openai"
  model ["<model-1>", "<model-2>", "<model-3>"]  # Users can select from dropdown
end
```

**Provider-Specific Environment Variables**

Each provider has a corresponding environment variable:

| Provider | Environment Variable |
|----------|---------------------|
| OpenAI | `OPENAI_DEFAULT_MODEL` |
| Anthropic/Claude | `ANTHROPIC_DEFAULT_MODEL` |
| Gemini/Google | `GEMINI_DEFAULT_MODEL` |
| Mistral | `MISTRAL_DEFAULT_MODEL` |
| Cohere | `COHERE_DEFAULT_MODEL` |
| DeepSeek | `DEEPSEEK_DEFAULT_MODEL` |
| xAI/Grok | `GROK_DEFAULT_MODEL` |
| Ollama | `OLLAMA_DEFAULT_MODEL` |

### 3. System Prompt

```ruby
system_prompt <<~PROMPT
  You are an AI assistant specialized in helping with math problems.
  Always show your work step by step.
PROMPT
```

### 4. Feature Flags :id=feature-flags

```ruby
# Interface features:
features do
  group "My Apps"         # Group in the app menu (default: the provider's group)
  disabled false          # Hide the app from the menu when true
  context_size 20         # Number of recent messages sent to the model
  auto_speech false       # Enable automatic text-to-speech for assistant messages
  easy_submit true        # Enable submitting messages with Enter key (without clicking Send)
  math true               # Enable mathematical notation rendering using KaTeX
  abc true                # Enable ABC music notation rendering and playback
  mermaid true            # Enable Mermaid diagram rendering for flowcharts and diagrams
  websearch true          # Enable web search
  library_save false      # No saving to the Knowledge Base (default true)
  library_search false    # No Knowledge Base retrieval (default true; needs library_save)
end

# Features that require specific implementation in the app:
features do
  # The following features are tied to specific system components:

  pdf_vector_storage true # Enable PDF file upload and vector storage for RAG (Retrieval-Augmented Generation)
  toggle true             # Render <div class='toggle'> blocks in assistant messages as collapsible show/hide sections
  jupyter true            # Enable access to Jupyter notebook interface
  image_generation true   # Enable AI image generation tools in conversation
  monadic true            # REQUIRED for Session State apps - enables context management via tools
  initiate_from_assistant true # Allow assistant to send first message in conversation
  autonomy "high"         # Set autonomy level: "high", "medium" (default), or "low"
  expressive_speech false # Opt this app out of Expressive Speech injection.
                          # Useful for apps with strict output formats (e.g. JSON-producing apps)
                          # where appended voice-marker instructions would collide with the system prompt.
                          # Default: not set (the feature activates automatically when Auto Speech is on
                          # and a marker-capable TTS provider is selected).

  # Speech-to-speech (Live Conversation family). Declaring speech_to_speech
  # replaces the text input panel with Start/Stop controls and streams the
  # microphone to the provider's realtime API. See the Live Conversation
  # section in Chat & Assistant Apps for the user-facing behavior.
  speech_to_speech true   # Turn this app into a speech-to-speech app
  sts_input_rate 16000    # Microphone sample rate in Hz. Default: 24000
                          # (Gemini Live consumes 16000)
  sts_vad_threshold 0.65  # Voice-activity detection sensitivity (0.0-1.0).
                          # Higher = less sensitive to background noise
  sts_vad_prefix_ms 300   # Audio kept before speech starts, in milliseconds
  sts_vad_silence_ms 1000 # Silence that ends a turn, in milliseconds
  sts_vad_type "semantic_vad"   # Turn-detection mode. Default: "server_vad"
                                # (silence-based). "semantic_vad" waits for
                                # semantic completion (OpenAI only)
  sts_vad_eagerness "low"       # How quickly semantic_vad ends a turn:
                                # low / medium / high / auto (OpenAI only)
  sts_idle_stop_seconds 180 # Stop the session after this much inactivity.
                            # Default: 180. Set 0 to disable
end
```

Omitted `sts_vad_*` keys fall back to the provider's own defaults, and not
every provider honors every key (xAI ignores `sts_vad_prefix_ms`). The
OpenAI Live Conversation variant also lets the user choose
`sts_vad_type`/`sts_vad_eagerness` from a turn-detection selector, and a
chosen value overrides the MDSL default from the next session.

#### Autonomy Levels

The `autonomy` feature controls how much confirmation the assistant seeks before executing actions:

| Level | Behavior |
|-------|----------|
| `"high"` | Execute actions immediately without confirmation. Skip the Plan-Approve-Execute protocol. Only pause for ambiguous intent, passwords, or destructive actions. |
| `"medium"` | Default behavior. The assistant follows standard confirmation patterns including the Plan-Approve-Execute protocol for multi-step tasks. |
| `"low"` | Ask for explicit user confirmation before every action. Always use `propose_plan` for tasks with 2 or more steps. |

When omitted, autonomy defaults to `"medium"` (no prompt injection). Web Insight uses `"high"` to enable smooth interactive browser sessions without repeated confirmation prompts.

### 5. Tool Definitions

Tools can be defined in two ways: by importing shared tool groups or by defining custom tools.

#### Importing Shared Tool Groups

Shared tool groups are collections of related tools that can be reused across multiple apps:

```ruby
# Import always-available tool groups
import_shared_tools :file_operations, visibility: "always"
import_shared_tools :python_execution, visibility: "always"

# Import conditionally-available tool groups
import_shared_tools :web_automation, visibility: "conditional"
```

**Available Tool Groups**: Tool groups are defined in the shared tool registry (`lib/monadic/shared_tools/registry.rb`). See [Tool Groups](tool-groups.md) for the complete list of groups, the tools they contain, and their availability conditions.

**Visibility Modes**:
- `always`: The tools are sent to the model from the start
- `conditional` (default): The tools stay hidden until the model asks for the group with `request_tool`

Some groups also depend on the environment, for example a running container or an API key; the [Tool Groups](tool-groups.md) page lists these conditions. Groups that need a capability the provider lacks (such as image or audio input) are skipped for that provider.

#### Dynamic Skills (reachable_skills)

Instead of importing every tool group up front, an app can declare groups it is allowed to acquire on demand during a conversation with `reachable_skills`. The groups stay hidden until the model requests them by name via `request_tool`:

```ruby
# Groups the app can unlock when the conversation calls for them
reachable_skills :web_search_tools, :image_analysis

# Or grant the curated pool of read-only safe groups in one line
reachable_skills :safe
```

`reachable_skills :group_a, :group_b` is equivalent to importing each group with `visibility: "conditional"`, but states the intent more clearly. See the "Dynamic Skills" section in [Tool Groups](tool-groups.md) for details.

#### Defining Custom Tools

For app-specific functionality, define custom tools:

```ruby
tools do
  define_tool "book_search", "Search for books by title, author, or ISBN" do
    parameter :query, "string", "Search terms (book title, author name, or ISBN)", required: true
    parameter :search_type, "string", "Type of search to perform", enum: ["title", "author", "isbn", "any"]
    parameter :category, "string", "Book category to filter results", enum: ["fiction", "non-fiction", "science", "history", "biography"]
    parameter :max_results, "integer", "Maximum number of results to return (default: 10)"
  end
end
```

**Note**: The `parameter` method doesn't support the `default` keyword. Include default values in the description instead.

#### Combining Shared and Custom Tools

You can use both shared tool groups and custom tools in the same app:

```ruby
# Import shared tools
import_shared_tools :file_operations, visibility: "always"

# Define custom tools
tools do
  define_tool "analyze_data", "Analyze data from file" do
    parameter :filename, "string", "Name of file to analyze", required: true
  end
end
```

### 6. Context Compaction

For apps running on OpenAI models, the `compaction` block controls server-side conversation compaction (Responses API). It is on by default, with a threshold of 150,000 tokens, so apps declare the block only to change the threshold or to turn it off:

```ruby
compaction do
  compact_threshold 180_000   # Custom token threshold
end

compaction false              # Opt out — rely on the context_size sliding window only
```

## Example Applications

### Simple Chat Application

```ruby
app "ChatClaude" do  # AppName + Provider
  description "Basic chat application with Claude"
  icon "fa-solid fa-comments"
  display_name "Chat"

  system_prompt <<~PROMPT
    You are a helpful assistant that provides accurate and concise information.
    Always be polite and respond directly to the user's questions.
  PROMPT

  llm do
    provider "anthropic"
    model "<model-id>"
    temperature 0.7
  end

  features do
    monadic false  # Disable Session State (context management)
    initiate_from_assistant true
  end
end
```

> **Note**: For working examples, see the apps in `docker/services/ruby/apps/`.

### Code Interpreter-Enabled Math Tutor

```ruby
app "MathTutorOpenAI" do  # AppName + Provider
  description "AI assistant that helps solve math problems step-by-step"
  icon "fa-solid fa-calculator"
  display_name "Math Tutor"
  
  system_prompt <<~PROMPT
    You are a helpful math tutor. When presented with math problems:
    1. Analyze the problem carefully
    2. Explain your approach
    3. Show all steps of your work
    4. Verify the answer
    
    You can use Python code to perform calculations and create visualizations.
    Focus on teaching the concepts, not just providing answers.
  PROMPT
  
  llm do
    provider "openai"
    model ["<model-1>", "<model-2>"]  # Array of model IDs for user selection
    temperature 0.7
  end

  features do
    math true        # Enable math notation rendering
  end
  
  tools do
    # run_code comes from the :python_execution group
    import_shared_tools :python_execution, visibility: "always"
  end
end
```

## Advanced Features

### Tool/Function Calling

Tools are defined in MDSL files. Each custom tool needs a method with the same name in the companion `*_tools.rb` file.

#### File Structure

Tool implementations live in a companion `*_tools.rb` file alongside the app's `.mdsl` files. For the standard directory layouts and file naming conventions, see [File Structure Patterns](develop_apps.md#file-structure-patterns) in the Developing Apps guide.

**For Shared Tool Groups**:

With `import_shared_tools`, the methods come from the shared modules in `lib/monadic/shared_tools/`. The generated app class includes the module of each imported group and the app's `<AppName>Tools` module, so the tools file only holds the app's own methods:

```ruby
# apps/my_app/my_app_tools.rb
module MyAppTools
  def my_custom_tool(param:)
    # Implementation
  end
end
```

Every app also gets the `:file_operations` group, so it can read and write files in the shared folder.

#### Best Practices

1. **Prefer shared tools**: Use `import_shared_tools` for common functionality instead of duplicating code
2. **Keep tool definitions explicit**: Define all tools in MDSL files for clarity
3. **Match implementation methods**: Ensure each custom tool has a corresponding method in `*_tools.rb`
4. **Use descriptive names**: Tool and parameter names should be self-documenting
5. **Add meaningful descriptions**: Help the AI understand when and how to use each tool
6. **Test tool implementations**: Verify tools work correctly before deployment
7. **Check availability**: For conditional tools, ensure dependencies are met before use

The DSL supports defining tools (functions) that the AI can call. These automatically get translated to the appropriate format for each provider.

```ruby
tools do
  define_tool "generate_image", "Generate an image based on a text description" do
    parameter :prompt, "string", "Text description of the image to generate", required: true
    parameter :style, "string", "Style of the image", required: false, enum: ["realistic", "cartoon", "sketch"]
    parameter :size, "string", "Size of the image", required: false, enum: ["small", "medium", "large"]
  end
end
```

### Implementing Tools with MDSL

Tool implementation in MDSL follows a structured approach using the facade pattern:

1. **Tool Definition**: Tools must be defined explicitly in the MDSL file
2. **Tool Implementation**: Implement methods in a companion `*_tools.rb` file using the facade pattern

A minimal example — the tool is declared in the MDSL file, and a facade method in the companion tools file validates input and handles errors:

```ruby
# my_app_openai.mdsl (excerpt)
tools do
  define_tool "mermaid_documentation", "Get mermaid.js syntax documentation" do
    parameter :diagram_type, "string", "Type of diagram (graph, sequence, flowchart, etc.)", required: true
  end
end
```

```ruby
# my_app_openai.mdsl (excerpt): fetch_web_content comes from this group
import_shared_tools :web_search_tools, visibility: "always"
```

```ruby
# my_app_tools.rb
module MyAppTools
  # Facade method with validation and error handling
  def mermaid_documentation(diagram_type: "graph")
    raise ArgumentError, "diagram_type is required" if diagram_type.to_s.empty?

    fetch_web_content(url: "https://mermaid.js.org/syntax/#{diagram_type}.html")
  rescue => e
    "❌ #{e.message}"
  end
end
```

For the full pattern explanation and the canonical implementation template — including wrapping helper modules imported via `include_modules` — see [Always Use Facade Pattern](develop_apps.md#always-use-facade-pattern) in the Developing Apps guide. For complete worked examples (such as a Wikipedia app whose facade method wraps a helper module), see [Recipe Examples](recipe-examples.md).

### Session State Apps

Session State allows apps to persist context across conversation turns using explicit tool calls. This is useful for apps that need to track progress, accumulate information, or maintain structured state.

#### Requirements for Session State Apps

Apps using Session State **must** set `monadic true` in the features block:

```ruby
app "MySessionStateOpenAI" do
  llm do
    provider "openai"
  end

  features do
    monadic true  # REQUIRED - enables Session State functionality
  end

  tools do
    # Define load/save tools for state management
    define_tool "load_context", "Load current context from session state" do
      parameter :session, "object", "Session object (automatically provided)", required: false
    end

    define_tool "save_context", "Save response and context to session state" do
      parameter :message, "string", "Your response message", required: true
      parameter :topics, "array", "Topics discussed (accumulated)", required: false
      parameter :notes, "array", "Important notes (accumulated)", required: false
    end
  end
end
```

#### Built-in Session State Apps

Apps that use Session State include Chat Plus, Research Assistant, Math Tutor, Novel Writer, Translate, Language Practice Plus, Voice Interpreter and Jupyter Notebook.

### Context Schema (Session Context)

While Session State Apps use explicit tool calls for context management, you can also enable **automatic context extraction** using the `context_schema` block. This feature extracts key information from conversations and displays it in the sidebar panel.

> **Note**: For complete documentation on Session Context, see the [Session Context](session-context.md) guide.

#### Basic Usage

```ruby
app "MyAppOpenAI" do
  features do
    monadic true  # Required for context_schema
  end

  context_schema do
    field :topics, icon: "fa-tags", label: "Topics",
          description: "Main subjects discussed in conversation"
    field :people, icon: "fa-users", label: "People",
          description: "Names of people mentioned"
    field :notes, icon: "fa-sticky-note", label: "Notes",
          description: "Important facts and preferences to remember"
  end
end
```

#### Field Definition

Each field in `context_schema` accepts the following options:

| Option | Type | Required | Description |
|--------|------|----------|-------------|
| `name` | Symbol | Yes | Field identifier (first argument, e.g., `:topics`) |
| `icon` | String | No | FontAwesome icon class (e.g., `"fa-tags"`) |
| `label` | String | No | Display name in sidebar (default: the name with `_` replaced by spaces and the first letter capitalized) |
| `description` | String | No | Guides the extraction agent on what to extract |

#### Default Schema

If no `context_schema` block is provided but `monadic true` is set, the app uses the default schema:

- **Topics**: Main subjects discussed
- **People**: Names of people mentioned
- **Notes**: Important facts to remember

#### Custom Schema Example

```ruby
# For a Code Review app
context_schema do
  field :files_reviewed, icon: "fa-file-code", label: "Files",
        description: "Source code files that were reviewed"
  field :issues, icon: "fa-bug", label: "Issues",
        description: "Bugs and code problems identified"
  field :suggestions, icon: "fa-lightbulb", label: "Suggestions",
        description: "Improvement recommendations"
end
```

Session State (explicit tool calls) and Session Context (automatic extraction) both require `monadic true` and can be used together in the same app. For a side-by-side comparison of the two mechanisms and the related terminology, see the [Terminology Guide](monadic-mode.md#terminology-guide) in the Monadic Mode documentation.

### Provider-Specific Adapters

The DSL automatically formats function definitions appropriately for different AI providers, handling the specific requirements and formats for each model provider:

- OpenAI: Converts to OpenAI's function calling format with `type: "function"` wrapper
- Anthropic: Adapts to Claude's tool format with `input_schema` property
- Cohere: Uses the OpenAI-style `type: "function"` format with a JSON Schema `parameters` object
- Mistral: Formats for Mistral's function calling API
- Gemini: Structures for Google Gemini models with `function_declarations` wrapper
- DeepSeek: Converts to DeepSeek's function calling format
- Grok (xAI): Maps to Grok's function calling format

This automatic conversion means you can write your tool definitions once in the DSL, and they will work across different providers without manual conversion.

**Note about Font Awesome Icons**: The `icon` method accepts any icon of Font Awesome 6 Free (https://fontawesome.com/v6/search?ic=free). A simple name like "brain" is converted to the Font Awesome class.

## Debugging and Testing

When troubleshooting DSL apps, check for:

1. Valid Ruby syntax (no missing `end` statements, proper indentation)
2. The `llm` block before the tools, and the description, icon and system prompt
3. Properly formatted tool definitions
4. Compatibility between selected features and provider capabilities

When apps fail to load, the other apps still load, and each failed app is listed with the reason in the server output (`docker logs monadic-chat-ruby-container`, or the terminal in development mode). Set `EXTRA_LOGGING=true` in the configuration for more detailed debug output.

## Best Practices

1. **Prefer shared tools** - Use `import_shared_tools` for common functionality instead of duplicating code
2. **Name the tools module after the app** - `MyAppOpenAI` uses the `MyAppTools` module
3. **Use descriptive names** - Clear app and tool names make the application easier to use
4. **Keep system prompts focused** - Write instructions specific to each use case
5. **Enable only what you need** - Do not turn on features the application does not use
6. **Test with the target provider** - Confirm compatibility with the LLM you selected
7. **Organize apps logically** - Use `display_name` for consistent presentation in the UI
8. **Check availability** - For conditional tools, make sure dependencies are met before use

## Common Issues and Solutions

### A Tool Is Defined but Fails

**Problem**: The model calls a tool and gets "undefined method".

**Solution**: Check that the method is in the `<AppName>Tools` module, or that the tool's group is imported with `import_shared_tools`:

```ruby
# Explicit tool definition in the MDSL file
tools do
  define_tool "my_tool", "Tool description" do
    parameter :param, "string", "Parameter description"
  end
end
```

```ruby
# my_app_tools.rb
module MyAppTools
  def my_tool(param: nil)
    # ...
  end
end
```

### Provider-Specific Considerations :id=provider-specific-considerations

- **Function Limits**: Up to 20 function calls per conversation turn (30 with Mistral)
- **Code Execution**: All providers use `run_code` from the `:python_execution` group
- **Array Parameters**: OpenAI requires `items` property for arrays
- **Error Prevention**: Built-in error pattern detection prevents infinite retry loops
