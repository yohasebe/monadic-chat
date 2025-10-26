# Monadic DSL (Domain Specific Language)

The Monadic DSL provides a simplified way to create AI applications with specific behaviors, UI elements, and capabilities. This document explains the DSL syntax and usage in detail.

## Introduction

Monadic DSL is a Ruby-based configuration system that makes it easier to define AI-powered applications without writing advanced Ruby code. The DSL uses a declarative approach to specify application behavior.

## File Format

Monadic Chat uses the **`.mdsl` format** (Monadic Domain Specific Language) for all app definitions. This declarative format provides a clean, maintainable way to define AI-powered applications.

**Important**: All apps must use the MDSL format.

## Basic Structure

A basic MDSL application definition looks like this:

```ruby
app "AppNameProvider" do  # Follow the naming convention: AppName + Provider (e.g., ChatOpenAI, ResearchAssistantClaude)
  description "A brief description of what this application does"
  
  icon "fa-solid fa-icon-name"  # FontAwesome icon or custom HTML
  
  system_prompt <<~PROMPT
    Instructions for the AI model that define how it should behave
    in this specific application context.
  PROMPT
  
  llm do
    provider "anthropic"
    model "<model-id>"
    temperature 0.7
  end

  features do
    image_support true
    auto_speech false
  end
end
```

## Configuration Blocks

### 1. App Metadata

```ruby
app "AppNameProvider" do  # e.g., "ChatOpenAI", "CodingAssistantClaude", "ResearchAssistantGemini"
  description "Application description"
  
  # Icon can be specified in multiple formats with smart matching:
  icon "brain"                        # Simple name (becomes fa-solid fa-brain)
  # icon "github"                     # Known brand (automatically becomes fa-brands fa-github)
  # icon "envelope"                   # Simple name (becomes fa-solid fa-envelope)
  # icon "fa-regular fa-envelope"     # Full FontAwesome class with style prefix
  # icon "regular envelope"           # Style + name format (becomes fa-regular fa-envelope)
  # icon "mail"                       # Fuzzy matching (finds closest match like envelope)
  # icon "<i class='fas fa-code'></i>" # Custom HTML is preserved as-is
  
  # For available icons, see: https://fontawesome.com/v5/search?ic=free

  # App naming option:
  display_name "Application Name"      # Name shown in the UI (required)
  
  group "Category Name"  # Optional grouping for the UI
end
```

### 2. LLM Configuration

```ruby
llm do
  provider "anthropic"  # AI provider (anthropic, openai, cohere, etc.)
  model "<model-id>"  # Model name
  temperature 0.7  # Response randomness (0.0-1.0)
  max_tokens 4000  # Maximum response length
end
```

Supported providers:
- `anthropic` (Claude models)
- `openai` (GPT models)
- `cohere` (Command models)
- `mistral` (Mistral models)
- `gemini` (Google Gemini models)
- `deepseek` (DeepSeek models)
- `perplexity` (Perplexity models)
- `xai` (Grok models)
- `ollama` (Local models via Ollama)

For a complete overview of which apps are compatible with which models, see the [App Availability by Provider](../basic-usage/basic-apps.md#app-availability) section in the Basic Apps documentation.

#### Model Specification Best Practices

There are three approaches to specifying models in MDSL, each suited for different use cases:

**Standard Apps (Built-in apps in `docker/services/ruby/apps/`)**

Use specific model names for stability and predictability:

```ruby
llm do
  provider "openai"
  model "gpt-4.1"  # Explicit model name ensures consistent behavior
end
```

- ✅ Predictable behavior
- ✅ Easy to debug
- ✅ Suitable for production apps
- ⚠️ Requires periodic updates when new models are released

**Custom Apps (User-created apps in `~/monadic/data/apps/`)**

Use environment variables for flexibility:

```ruby
llm do
  provider "openai"
  model ENV.fetch("OPENAI_DEFAULT_MODEL")  # Respects user preferences
end
```

- ✅ Users can customize via `~/monadic/config/env`
- ✅ Automatically uses system defaults if ENV not set
- ✅ Future-proof (no hardcoded model names)
- ✅ Recommended for custom apps

**Configuration Priority**

Model values are resolved in this order (highest to lowest):

1. **Explicit MDSL value**: `model "gpt-4.1"` (highest priority)
2. **Environment variable**: `ENV["OPENAI_DEFAULT_MODEL"]` from `~/monadic/config/env`
3. **System defaults**: `docker/services/ruby/config/system_defaults.json`
4. **Hardcoded fallback**: Built-in default values

**Multiple Model Options**

Provide users with model choices using an array:

```ruby
llm do
  provider "openai"
  model ["gpt-5", "gpt-4.1", "gpt-4.1-mini"]  # Users can select from dropdown
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
| Perplexity | `PERPLEXITY_DEFAULT_MODEL` |
| xAI/Grok | `GROK_DEFAULT_MODEL` |
| Ollama | `OLLAMA_DEFAULT_MODEL` |

### 3. System Prompt

```ruby
system_prompt <<~PROMPT
  You are an AI assistant specialized in helping with math problems.
  Always show your work step by step.
PROMPT
```

### 4. Feature Flags

```ruby
# Well-supported UI features:
features do
  image true              # Enable images in assistant responses to be clickable (opens in new tab)
  auto_speech false       # Enable automatic text-to-speech for assistant messages
  easy_submit true        # Enable submitting messages with Enter key (without clicking Send)
  sourcecode true         # Enable enhanced source code highlighting (alias: code_highlight)
  mathjax true            # Enable mathematical notation rendering using MathJax
  abc true                # Enable ABC music notation rendering and playback
  mermaid true            # Enable Mermaid diagram rendering for flowcharts and diagrams
  websearch true          # Enable web search capability (alias: web_search)
end

# Features that require specific implementation in the app:
features do
  # The following features are tied to specific system components:
  
  pdf_vector_storage true # Enable PDF file upload and vector storage for RAG (Retrieval-Augmented Generation)
  toggle true             # Enable collapsible sections for meta information and tool usage (primarily for Claude apps)
  jupyter_access true     # Enable access to Jupyter notebook interface (alias: jupyter)
  image_generation true   # Enable AI image generation tools in conversation
  monadic true            # Process responses as structured JSON for enhanced display (see Monadic Mode documentation)
  initiate_from_assistant true # Allow assistant to send first message in conversation
end
```

### 5. Tool Definitions

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

## Example Applications

### Simple Chat Application

```ruby
app "Simple Chat" do
  description "Basic chat application with Claude"
  icon "fa-solid fa-comments"

  system_prompt <<~PROMPT
    You are a helpful assistant that provides accurate and concise information.
    Always be polite and respond directly to the user's questions.
  PROMPT

  llm do
    provider "anthropic"
    model "<model-id>"  # Specify your model ID (e.g., "claude-sonnet-4-5-latest")
    temperature 0.7
  end
end
```

> **Note**: For actual working examples with current model names, see the app implementations in `docker/services/ruby/apps/`.

### Code Interpreter-Enabled Math Tutor

```ruby
app "Math Tutor" do
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
    sourcecode true     # Enable code highlighting
    image true          # Enable clickable images in responses
    mathjax true        # Enable math notation rendering
  end
  
  tools do
    # run_code is a standard tool - no need to define it
    # It's automatically available for code execution
  end
end
```

## Advanced Features

### Tool/Function Calling

Tools in Monadic Chat must be explicitly defined in MDSL files. Each tool definition should match a corresponding method implementation in the companion `*_tools.rb` file.

#### File Structure

Standard Monadic Chat file naming conventions:

```text
apps/app_name/
├── app_name_constants.rb    # Optional: Shared constants (ICON, DESCRIPTION, etc.)
├── app_name_tools.rb        # Tool method implementations
├── app_name_provider.mdsl   # MDSL interface (e.g., app_name_openai.mdsl)
└── app_name_provider.mdsl   # Additional provider versions
```

#### Best Practices

1. **Keep tool definitions explicit**: Define all tools in MDSL files for clarity
2. **Match implementation methods**: Ensure each tool has a corresponding method in `*_tools.rb`
3. **Use descriptive names**: Tool and parameter names should be self-documenting
4. **Add meaningful descriptions**: Help the AI understand when and how to use each tool
5. **Test tool implementations**: Verify tools work correctly before deployment

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

#### Recommended: Facade Pattern

Create your MDSL file with explicit tool definitions:

```ruby
# mermaid_grapher_openai.mdsl
app "MermaidGrapherOpenAI" do
  description "Create diagrams using mermaid.js syntax"
  icon "diagram"
  display_name "Mermaid Grapher"
  
  system_prompt <<~PROMPT
    You help visualize data using mermaid.js.
    Use the mermaid_documentation function to get syntax examples.
  PROMPT
  
  llm do
    provider "openai"
    model ENV.fetch("OPENAI_DEFAULT_MODEL")  # Falls back to system_defaults.json
    temperature 0.0
  end
  
  features do
    mermaid true
    image true
  end
  
  tools do
    define_tool "mermaid_documentation", "Get mermaid.js syntax documentation" do
      parameter :diagram_type, "string", "Type of diagram (graph, sequence, flowchart, etc.)", required: true
    end
  end
end
```

Then create a tools file with facade methods:

```ruby
# mermaid_grapher_tools.rb
class MermaidGrapherOpenAI < MonadicApp
  # Facade method with validation and error handling
  def mermaid_documentation(diagram_type: "graph")
    raise ArgumentError, "diagram_type is required" if diagram_type.nil? || diagram_type.empty?
    
    begin
      result = fetch_web_content(url: "https://mermaid.js.org/syntax/#{diagram_type}.html")
      { success: true, content: result }
    rescue => e
      { success: false, error: e.message }
    end
  end
end
```

#### Using Helper Modules with Facade Pattern

For shared functionality across providers:

```ruby
# wikipedia_openai.mdsl
app "WikipediaOpenAI" do
  description "Search Wikipedia articles"
  icon "fa-brands fa-wikipedia-w"
  display_name "Wikipedia"
  
  system_prompt <<~PROMPT
    Use search_wikipedia to find information.
  PROMPT
  
  llm do
    provider "openai"
    model ENV.fetch("OPENAI_DEFAULT_MODEL")  # Falls back to system_defaults.json
    temperature 0.3
  end
  
  features do
    group "OpenAI"
  end
  
  include_modules ["WikipediaHelper"]
  
  tools do
    # Auto-completed from wikipedia_tools.rb
  end
end
```

Create a tools file with facade methods that wrap the helper:

```ruby
# wikipedia_tools.rb
class WikipediaOpenAI < MonadicApp
  include WikipediaHelper
  
  # Facade method with validation
  def search_wikipedia(search_query: "", language_code: "en")
    raise ArgumentError, "search_query is required" if search_query.empty?
    
    begin
      # Call the helper module method
      super(search_query: search_query, language_code: language_code)
    rescue => e
      { error: e.message }
    end
  end
end
```


### Provider-Specific Adapters

The DSL automatically formats function definitions appropriately for different AI providers, handling the specific requirements and formats for each model provider:

- OpenAI: Converts to OpenAI's function calling format with `type: "function"` wrapper
- Anthropic: Adapts to Claude's tool format with `input_schema` property
- Cohere: Maps to Cohere's Command models `parameter_definitions` format
- Mistral: Formats for Mistral's function calling API
- Gemini: Structures for Google Gemini models with `function_declarations` wrapper
- DeepSeek: Converts to DeepSeek's function calling format
- Perplexity: Adapts to Perplexity's function format
- Grok (xAI): Maps to Grok's function format with strict validation

This automatic conversion means you can write your tool definitions once in the DSL, and they will work across different providers without manual conversion.

**Note about FontAwesome Icons**: When specifying icons using the `icon` method, you can use any icon name from FontAwesome 5 Free. Browse the available icons at https://fontawesome.com/v5/search?ic=free. The system will automatically convert simple names like "brain" to the proper HTML with appropriate styles.

## Debugging and Testing

When troubleshooting DSL apps, check for:

1. Valid Ruby syntax (no missing `end` statements, proper indentation)
2. Required configuration blocks (app name, description, system prompt, llm)
3. Properly formatted tool definitions
4. Compatibility between selected features and provider capabilities

Error logs are stored in `~/monadic/data/error.log` when apps fail to load.

## Best Practices

1. Use descriptive names and clear instructions
2. Keep system prompts focused on specific use cases
3. Enable only the features your application needs
4. Provide detailed parameter descriptions for tools
5. Test thoroughly with different inputs
6. Organize related apps into logical groups

## Important Note

**Important**: All apps must use the MDSL format.

To create custom apps:

1. Create a new `.mdsl` file for each provider
2. Implement tools in a `*_tools.rb` file using the facade pattern
3. Use `include_modules` for any helper modules

## Common Issues and Solutions

### Empty Tools Block Error

**Problem**: Empty `tools do` blocks cause "Maximum function call depth exceeded" errors.

**Solution**: Either define tools explicitly or create a companion `*_tools.rb` file:

```ruby
# Option 1: Explicit tool definition
tools do
  define_tool "my_tool", "Tool description" do
    parameter :param, "string", "Parameter description"
  end
end

# Option 2: Create app_name_tools.rb 
class AppNameProvider < MonadicApp
  # Implementation methods - all tools must be defined in MDSL
end
```

### Provider-Specific Considerations

- **Function Limits**: All providers support up to 20 function calls per conversation turn
- **Code Execution**: All providers use `run_code` for code execution
- **Array Parameters**: OpenAI requires `items` property for arrays
- **Error Prevention**: Built-in error pattern detection prevents infinite retry loops
