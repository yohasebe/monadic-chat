# Monadic DSL (Domain Specific Language)

The Monadic DSL provides a simplified way to create AI applications with specific behaviors, UI elements, and capabilities. This document explains the DSL syntax and usage in detail.

## Introduction

Monadic DSL is a Ruby-based configuration system that makes it easier to define AI-powered applications without writing advanced Ruby code. The DSL uses a declarative approach to specify application behavior.

## File Format

Monadic Chat uses the **`.mdsl` format** (Monadic Domain Specific Language) for all app definitions. This declarative format provides a clean, maintainable way to define AI-powered applications.

**Important**: The traditional Ruby class format (`.rb` files) is no longer supported. All apps must use the MDSL format.

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
    model "claude-3-opus-20240229"
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
  model "claude-3-opus-20240229"  # Model name
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

For a complete overview of which apps are compatible with which models, see the [App Availability by Provider](../basic-usage/basic-apps.md#app-availability) section in the Basic Apps documentation.

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
  
  pdf true                # Enable PDF file upload and processing UI elements
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
    model "claude-3-haiku-20240307"
    temperature 0.7
  end
end
```

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
    provider "anthropic"
    model "claude-3-opus-20240229"
    temperature 0.7
  end
  
  features do
    sourcecode true     # Enable code highlighting (formerly code_interpreter)
    image true          # Enable clickable images in responses
  end
  
  tools do
    tool "run_python" do
      description "Run Python code to solve math problems"
      parameters do
        parameter "code", type: "string", description: "Python code to execute"
      end
    end
    
    tool "plot_graph" do
      description "Create a graph for visualization"
      parameters do
        parameter "x_values", type: "array", items: { type: "number" }, description: "X-axis values"
        parameter "y_values", type: "array", items: { type: "number" }, description: "Y-axis values"
        parameter "title", type: "string", description: "Graph title"
      end
    end
  end
end
```

## Advanced Features

> For developers interested in understanding the internal implementation of MDSL and how it works behind the scenes, see [MDSL Internals](mdsl-internals.md).

### MDSL Tool Auto-Completion System

Monadic Chat includes an automatic tool completion system that dynamically generates MDSL tool definitions from Ruby implementation files. This reduces manual work and ensures consistency between tool definitions and implementations.

#### How Auto-Completion Works

1. **Runtime Detection**: When MDSL files are loaded, the system automatically scans corresponding `*_tools.rb` files
2. **Method Analysis**: Public methods in Ruby implementation files are analyzed for tool candidacy
3. **Type Inference**: Parameter types are inferred from default values and naming patterns
4. **Dynamic Completion**: Missing tool definitions are automatically added to the LLM's available tools
5. **File Writing**: Auto-generated definitions are optionally written back to MDSL files

#### Configuration

Control auto-completion behavior with the `MDSL_AUTO_COMPLETE` environment variable:

```bash
# Default behavior (auto-completion disabled)
# MDSL_AUTO_COMPLETE is unset or false by default

# Enable auto-completion with basic logging
export MDSL_AUTO_COMPLETE=true

# Enable auto-completion with detailed debug information
export MDSL_AUTO_COMPLETE=debug

# Disable auto-completion entirely
export MDSL_AUTO_COMPLETE=false
```

#### File Structure Requirements

The auto-completion system works with standard Monadic Chat file naming conventions:

```text
apps/app_name/
├── app_name_constants.rb    # Optional: Shared constants (ICON, DESCRIPTION, etc.)
├── app_name_tools.rb        # Tool method implementations
├── app_name_provider.mdsl   # MDSL interface (e.g., app_name_openai.mdsl)
└── app_name_provider.mdsl   # Additional provider versions
```

#### Method Detection Rules

**Included Methods:**
- Public methods in `*_tools.rb` files
- Methods not matching exclusion patterns
- Methods not in the standard tools list

**Excluded Methods:**
- Private methods (after `private` keyword)
- Methods matching patterns: `initialize`, `validate`, `format`, `parse`, `setup`, `teardown`, `before`, `after`, `test_`, `spec_`
- Standard MonadicApp methods (automatically detected)

#### Type Inference

The system automatically infers parameter types from default values:

```ruby
def example_tool(text: "", count: 0, enabled: false, items: [], config: {})
  # text: "string", count: "integer", enabled: "boolean"
  # items: "array", config: "object"
end
```

#### Generated Tool Definitions

Example of auto-generated MDSL tool definition:

```ruby
tools do
  # Auto-generated tool definitions from Ruby implementation
  define_tool "count_num_of_words", "Count the num of words" do
    parameter :text, "string", "The text content to process"
  end
end
```

#### User-Defined Plugins Support

The auto-completion system supports both built-in apps and user-defined plugins:

**Built-in Apps:** `docker/services/ruby/apps/`
**User Plugins:** `~/monadic/data/plugins/` (or `/monadic/data/plugins/` in container)

#### Development Tools

**CLI Tool for Testing:**
```bash
# Preview auto-completion for an app
ruby bin/mdsl_tool_completer novel_writer

# Validate tool consistency
ruby bin/mdsl_tool_completer --action validate app_name

# Detailed analysis with debug info
ruby bin/mdsl_tool_completer --action analyze --verbose app_name
```

**RSpec Tests:**
The system includes comprehensive tests in `spec/app_loading_spec.rb`:
- Tool implementation validation
- Auto-completion consistency checks  
- System prompt reference validation
- Multi-provider tool consistency

#### Best Practices

1. **Keep Ruby methods simple**: Use clear parameter names and appropriate default values
2. **Add meaningful defaults**: Default values help with type inference
3. **Use descriptive method names**: Method names are used to generate descriptions
4. **Separate public and private**: Use `private` keyword to exclude helper methods
5. **Test auto-completion**: Use the CLI tools to verify generated definitions

#### Troubleshooting

**Common Issues:**
- **No auto-completion**: Check `MDSL_AUTO_COMPLETE` environment variable
- **Wrong type inference**: Verify default values in Ruby method definitions
- **Missing methods**: Ensure methods are public (before `private` keyword)
- **File not found**: Verify file naming conventions match patterns

**Debug Mode:**
```bash
export MDSL_AUTO_COMPLETE=debug
# Restart Monadic Chat to see detailed auto-completion logs
```

### Tool/Function Calling

The DSL supports defining tools (functions) that the AI can call. These automatically get translated to the appropriate format for each provider.

```ruby
tools do
  tool "generate_image" do
    description "Generate an image based on a text description"
    parameters do
      parameter "prompt", type: "string", description: "Text description of the image to generate"
      parameter "style", type: "string", enum: ["realistic", "cartoon", "sketch"], description: "Style of the image"
      parameter "size", type: "string", enum: ["small", "medium", "large"], description: "Size of the image", required: false
    end
  end
end
```

### Implementing Tools with MDSL

Tool implementation in MDSL follows a structured approach using the facade pattern:

1. **Tool Definition**: Tools can be defined explicitly in the MDSL file or auto-completed from Ruby implementations
2. **Tool Implementation**: Implement methods in a companion `*_tools.rb` file using the facade pattern

#### Recommended: Facade Pattern with Auto-Completion

Create your MDSL file with minimal or no tool definitions:

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
    model "gpt-4o-2024-11-20"
    temperature 0.0
  end
  
  features do
    mermaid true
    image true
  end
  
  tools do
    # Tools will be auto-completed from mermaid_grapher_tools.rb
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
    model "gpt-4.1"
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

## Migration Notice

**Important**: The traditional Ruby class format is no longer supported. All apps must use the MDSL format.

If you have custom apps in the old Ruby class format, you must convert them to MDSL:

1. Create a new `.mdsl` file for each provider
2. Move tool implementations to a `*_tools.rb` file using the facade pattern
3. Use `include_modules` for any helper modules
4. Delete the old `.rb` app files

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
  # Tool methods will be auto-completed
end
```

### Provider-Specific Considerations

- **Function Limits**: OpenAI/Gemini support up to 20 function calls, Claude supports up to 16
- **Code Execution**: All providers now consistently use `run_code` (previously Claude used `run_script`)
- **Array Parameters**: OpenAI requires `items` property for arrays
- **Error Prevention**: Built-in error pattern detection prevents infinite retry loops
