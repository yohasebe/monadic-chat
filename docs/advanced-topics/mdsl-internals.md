# MDSL Internals

?> This document provides a detailed explanation of how Monadic DSL (MDSL) is implemented internally. It is intended for developers who want to understand the inner workings of MDSL or contribute to its development.

## 1. Overview

Monadic DSL (MDSL) is a Ruby-based domain-specific language developed to simplify the creation of AI-driven applications. By leveraging Ruby's language features, MDSL enables developers to define applications in a declarative way without worrying about the complexities of different LLM providers.

### 1.1 Key Features

#### 1.1.1 Declarative Syntax
Applications are defined using an `app "Name" do ... end` format, allowing various settings to be organized hierarchically in a readable format.

```ruby
app "ChatClaude" do
  description "A chat application using the Anthropic API"
  icon "a"
  system_prompt "You are a friendly AI assistant..."
  
  llm do
    provider "anthropic"
    model "claude-3-5-sonnet-20241022"
  end
  
  features do
    easy_submit false
    image true
  end
end
```

#### 1.1.2 Provider Abstraction
MDSL abstracts the differences between various LLM providers like OpenAI, Anthropic (Claude), Google (Gemini), Cohere, Mistral, DeepSeek, Perplexity, and xAI (Grok). This allows developers to switch providers easily or create similar applications for multiple providers with minimal effort.

```ruby
# Anthropic/Claude version
app "ChatClaude" do
  llm do
    provider "anthropic"
    model "claude-3-5-sonnet-20241022"
  end
end

# OpenAI version
app "ChatOpenAI" do
  llm do
    provider "openai"
    model "gpt-4.1"
  end
end
```

#### 1.1.3 Unified Tool Definition
Different LLM providers require different formats for function calling (tools). MDSL hides these differences by providing a consistent tool definition syntax.

```ruby
tools do
  define_tool "search_web", "Perform a web search" do
    parameter "query", "string", "Search query", required: true
    parameter "num_results", "integer", "Number of results", required: false
  end
end
```

#### 1.1.4 Ruby Class Conversion
DSL definitions are evaluated at runtime and converted to actual Ruby classes that inherit from `MonadicApp`. This combines the simplicity of DSL syntax with the power of Ruby classes.

#### 1.1.5 Monadic Error Handling
MDSL adopts monadic patterns (`Result` class and `bind`/`map` operations) from functional programming for error handling and state transformation, making error handling explicit and chainable.

```ruby
# Result monad for success/failure
class Result
  attr_reader :value, :error
  
  def initialize(value, error = nil)
    @value = value
    @error = error
  end
  
  # Halt processing if there's an error, otherwise transform value to a new Result
  def bind(&block)
    return self if @error
    begin
      block.call(@value)
    rescue => e
      Result.new(nil, e)
    end
  end
  
  # Simplified version of bind - transforms value and wraps in Result
  def map(&block)
    bind { |value| Result.new(block.call(value)) }
  end
  
  def success?
    !@error
  end
end
```

#### 1.1.6 Provider-Specific Formatters
Each provider has a dedicated formatter class that transforms abstract tool definitions into provider-specific JSON formats, allowing developers to define tools without worrying about implementation details.

## 2. Ruby Language Features Used in MDSL Implementation

MDSL leverages several Ruby language features to achieve its clean and declarative syntax. Understanding these features helps explain how MDSL works internally.

### 2.1 Metaprogramming

MDSL uses `eval` to execute DSL files, allowing Ruby interpreter to directly interpret the code. This enables execution of `.mdsl` files as Ruby code, with parsing and execution happening at runtime for flexible syntax.

```ruby
def load_dsl
  # Evaluate DSL in TOPLEVEL_BINDING context
  app_state = eval(@content, TOPLEVEL_BINDING, @file)
rescue => e
  warn "Warning: Failed to evaluate DSL in #{@file}: #{e.message}"
  raise
end
```

While `eval` can pose security risks when evaluating external input, MDSL is an internal DSL used for files written by the developer, and execution happens within Docker containers, minimizing security concerns.

### 2.2 Block Syntax

Ruby's block syntax allows for context-specific and scoped settings:

```ruby
app "Name" do
  # App context
  
  llm do
    # LLM context
    provider "anthropic"
    model "claude-3-5-sonnet-20241022"
  end
end

# Implementation
def llm(&block)
  LLMConfiguration.new(@state).instance_eval(&block)
end
```

This block syntax enables hierarchical settings that are easy to read and maintain.

### 2.3 Dynamic Class Generation

MDSL dynamically generates Ruby classes from string definitions using `eval`:

```ruby
def self.convert_to_class(state)
  class_def = <<~RUBY
    class #{state.name} < MonadicApp
      include #{helper_module} if defined?(#{helper_module})

      @settings = {
        model: #{state.settings[:model].inspect},
        # Other settings
      }
    end
  RUBY

  eval(class_def, TOPLEVEL_BINDING, state.name)
end
```

The `convert_to_class` method dynamically generates Ruby classes from DSL definitions, converting them to actual application classes at runtime.

### 2.4 Modules and Mixins

Generated classes include appropriate helper modules (e.g., `OpenAIHelper`, `ClaudeHelper`) based on the `provider` property value specified in the DSL.

```ruby
module ToolFormatters
  class AnthropicFormatter
    def format(tool)
      {
        name: tool.name,
        description: tool.description,
        input_schema: { /* ... */ }
      }
    end
  end
  # Other formatter classes
end

FORMATTERS = {
  openai: ToolFormatters::OpenAIFormatter,
  anthropic: ToolFormatters::AnthropicFormatter,
  # Other providers
}
```

This modular design separates provider-specific logic for flexibility.

### 2.5 Ruby's Flexible Syntax

MDSL uses `method_missing` for dynamic method handling, allowing undefined methods to be processed and enhancing the expressiveness of the DSL:

```ruby
# 1. LLMConfiguration - handling parameter name aliases
# e.g., converting max_output_tokens to max_tokens
def method_missing(method_name, *args)
  if PARAMETER_MAP.key?(method_name)
    send(PARAMETER_MAP[method_name], *args)
  else
    super
  end
end

# 2. SimplifiedFeatureConfiguration - handling arbitrary feature flags
# e.g., easy_submit, auto_speech, image, etc.
def method_missing(method_name, *args)
  value = args.first.nil? ? true : args.first
  feature_name = FEATURE_MAP[method_name] || method_name
  @state.features[feature_name] = value
end
```

This allows DSL users to declaratively specify various features:

```ruby
features do
  easy_submit false   # Known feature
  auto_speech false   # Known feature
  new_feature true    # Even unknown features are accepted
end
```

### 2.6 Closures and Scope

MDSL uses `instance_eval` to evaluate blocks in the context of specific instances, allowing DSL users to use local variables and methods in their DSL context:

```ruby
def define_tool(name, description, &block)
  tool = ToolDefinition.new(name, description)
  tool.instance_eval(&block) if block_given?
  tool.validate_for_provider(@provider)
  @tools << tool
  tool
end
```

This enables natural syntax for tool definitions:

```ruby
tools do
  define_tool "search", "Search the web" do
    parameter "query", "string", "Search query", required: true
  end
end
```

## 3. Provider Configuration System

One key component of MDSL is how it identifies and configures the appropriate helper module for each provider:

```ruby
class ProviderConfig
  # Provider information mapping
  PROVIDER_INFO = {
    "xai" => {
      helper_module: 'GrokHelper',  # Helper module name
      api_key: 'XAI_API_KEY',
      display_group: 'xAI Grok',
      aliases: ['grok', 'xaigrok']
    },
    # Other providers...
  }
  
  def initialize(provider_name)
    @provider_name = provider_name.to_s.downcase.gsub(/[\s\-]+/, "")
    @config = find_provider_config
  end
  
  # Get helper module name
  def helper_module
    @config[:helper_module]
  end
  
  private
  
  # Find provider configuration by name or aliases
  def find_provider_config
    # Direct match
    PROVIDER_INFO.each do |key, config|
      return config.merge(standard_key: key) if key == @provider_name
    end
    
    # Check aliases
    PROVIDER_INFO.each do |key, config|
      return config.merge(standard_key: key) if config[:aliases].include?(@provider_name)
    end
    
    # Default to OpenAI if no match
    PROVIDER_INFO["openai"]
  end
end
```

This system allows users to specify providers with various names (e.g., `anthropic` or `claude`), and the system will find the appropriate helper module.

## 4. Loading and Execution Flow

The MDSL loading and execution flow works as follows:

1. The `Loader` class determines if a file uses MDSL (by `.mdsl` extension or detecting `app "Name" do` pattern)
2. For MDSL files, content is processed with `eval`; for traditional Ruby files, `require` is used
3. The `app` method creates an `AppState` instance and processes the DSL block
4. The `SimplifiedAppDefinition` class handles various configuration methods like `description`, `icon`, etc.
5. Configuration is organized into settings, features, prompts, etc.
6. The completed state is converted to a Ruby class via `convert_to_class`
7. The generated class inherits from `MonadicApp` and includes the appropriate helper module

## 5. Conclusion

MDSL's implementation showcases how Ruby's language features can be leveraged to create a powerful and expressive domain-specific language. By abstracting provider differences and providing a clean, declarative syntax, it enables developers to focus on creating AI applications without getting bogged down in implementation details.

For information on how to use MDSL in your applications, see [Monadic DSL Documentation](monadic_dsl.md).
