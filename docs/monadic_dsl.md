# Monadic DSL (Domain Specific Language)

The Monadic DSL provides a simplified way to create AI applications with specific behaviors, UI elements, and capabilities. This document explains the DSL syntax and usage in detail.

## Introduction

Monadic DSL is a Ruby-based configuration system that makes it easier to define AI-powered applications without writing advanced Ruby code. The DSL uses a declarative approach to specify application behavior.

## File Formats

Monadic Chat supports two formats for app definitions:

1. **`.mdsl` files** - Simplified DSL format with cleaner syntax
2. **`.rb` files** - Traditional Ruby class definitions

The `.mdsl` format is recommended for most applications as it's more concise and easier to maintain.

## Basic Structure

A basic MDSL application definition looks like this:

```ruby
app "Application Name" do
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
app "Application Name" do
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

### 3. System Prompt

```ruby
system_prompt <<~PROMPT
  You are an AI assistant specialized in helping with math problems.
  Always show your work step by step.
PROMPT
```

### 4. Feature Flags

```ruby
features do
  image_support true     # Enable image attachments
  auto_speech false      # Enable automatic text-to-speech
  code_interpreter true  # Enable code execution
  web_search true        # Enable web search capability
  file_upload true       # Enable file uploading
  chat_history true      # Enable history preservation
end
```

### 5. Tool Definitions

```ruby
tools do
  tool "search_web" do
    description "Search the web for current information"
    parameters do
      parameter "query", type: "string", description: "Search query"
    end
  end
end
```

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
    code_interpreter true
    image_support true
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

When using the MDSL format, tool implementation follows a two-part approach:

1. **Tool Definition**: Define the tool structure in the MDSL file using the `define_tool` method
2. **Tool Implementation**: Implement the actual methods in a companion Ruby file

#### Method 1: Using a Companion Ruby File

First, create your MDSL file with tool definitions:

```ruby
# mermaid_grapher.mdsl
app "Mermaid Grapher" do
  description "Create diagrams using mermaid.js syntax"
  icon "fa-solid fa-project-diagram"
  
  system_prompt <<~PROMPT
    You help visualize data using mermaid.js.
    Use the mermaid_documentation function to get syntax examples.
  PROMPT
  
  llm do
    provider "openai"
    model "gpt-4o"
    temperature 0.0
  end
  
  features do
    mermaid true
  end
  
  # The tool is defined here, but implemented elsewhere
  tools do
    define_tool "mermaid_documentation", "Fetch documentation for a mermaid diagram type" do
      parameter :diagram_type, "string", "Type of diagram to fetch documentation for", required: true
    end
  end
end
```

Then, create a companion Ruby file with the same base name to implement the method:

```ruby
# mermaid_grapher.rb
class MermaidGrapher < MonadicApp
  # Implement the actual method that will be called
  def mermaid_documentation(diagram_type: "graph")
    fetch_web_content(url: "https://mermaid.js.org/syntax/#{diagram_type}.html")
  end
end
```

#### Method 2: Using Helper Modules

For more complex implementations or shared functionality:

```ruby
# wikipedia.mdsl
app "Wikipedia" do
  description "Search Wikipedia articles"
  icon "fa-brands fa-wikipedia-w"
  
  system_prompt <<~PROMPT
    Use search_wikipedia to find information.
  PROMPT
  
  llm do
    provider "openai"
    model "gpt-4o"
    temperature 0.3
  end
  
  # Define the tool interface
  tools do
    define_tool "search_wikipedia", "Search Wikipedia articles" do
      parameter :search_query, "string", "Query for the search", required: true
      parameter :language_code, "string", "Language code", required: true
    end
  end
end
```

Create a minimal app class that includes a helper module:

```ruby
# wikipedia_app.rb
class Wikipedia < MonadicApp
  include WikipediaHelper  # This module contains the actual implementation
end
```

Then implement the actual functionality in the helper module:

```ruby
# wikipedia_helper.rb
module WikipediaHelper
  def search_wikipedia(search_query: "", language_code: "en")
    # Implementation code...
    result = perform_search(search_query, language_code)
    return result
  end
  
  private
  
  def perform_search(query, language)
    # Private helper methods...
  end
end
```


### Provider-Specific Adapters

The DSL automatically formats function definitions appropriately for different AI providers:

- OpenAI: Uses the function_call format
- Anthropic: Uses Claude's tool format
- Cohere: Adapts to Cohere's Command models format
- Mistral: Uses Mistral's function calling format
- Gemini: Formats tools for Google Gemini models
- DeepSeek: Supports DeepSeek models
- Perplexity: Supports Perplexity models
- Grok (xAI): Supports Grok models

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

## Converting Old-Style Apps to MDSL

If you have existing apps in the traditional Ruby class format, you can convert them to the new MDSL format:

**Old format:**
```ruby
class MathTutorApp < MonadicApp
  include ClaudeHelper
  
  @settings = {
    app_name: "Math Tutor",
    icon: "fa-solid fa-calculator",
    description: "AI assistant that helps solve math problems step-by-step",
    initial_prompt: "You are a helpful math tutor...",
    # other settings...
  }
  
  # Custom methods...
end
```

**New MDSL format:**
```ruby
app "Math Tutor" do
  description "AI assistant that helps solve math problems step-by-step"
  icon "fa-solid fa-calculator"
  
  system_prompt "You are a helpful math tutor..."
  
  llm do
    provider "anthropic"
    model "claude-3-opus-20240229"
    temperature 0.7
  end
  
  # Other configuration...
end
```