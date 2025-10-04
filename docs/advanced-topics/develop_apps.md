# Developing Apps

In Monadic Chat, you can develop AI chatbot applications using original system prompts. This section explains the steps to develop a new application.

?> **Important**: The app name in MDSL must match the Ruby class name exactly. For example, `app "ChatOpenAI"` requires a corresponding `class ChatOpenAI < MonadicApp`. This ensures proper menu grouping and functionality.

## How to Add a Simple App

### MDSL Format (Primary Method)

1. Create an MDSL (Monadic Domain Specific Language) file for the app.
2. Save the MDSL file in the `apps` directory of the shared folder (`~/monadic/data/apps`).
3. Restart Monadic Chat.

**Common App Patterns**:
- **Facade Pattern**: Apps with `*_tools.rb` files using facade methods for all custom functionality (Recommended)
- **Module Integration**: Apps using `include_modules` + facade methods for shared capabilities
- **Standard Tools**: Apps using only built-in MonadicApp methods

**Error Prevention**: The system includes error pattern detection that prevents infinite retry loops by:
- Detecting repeated errors (font, module, permission issues)
- Stopping after 3 similar errors
- Providing context-aware suggestions


**Tool Requirements**:
- All tools mentioned in system prompts must have corresponding `define_tool` blocks
- Use consistent parameter names: `fetch_text_from_file` uses `:file`, `fetch_text_from_pdf` uses `:pdf`
- Empty `tools do` blocks can cause "Maximum function call depth exceeded" errors

For detailed information on MDSL format, see [Monadic DSL Documentation](monadic_dsl.md).

### How to Add an Advanced App

For robust app development, use MDSL with the facade pattern:
- Create `app_name_provider.mdsl` for each provider (e.g., `chat_openai.mdsl`)
- Create `app_name_tools.rb` with facade methods extending MonadicApp
- **Explicitly define all tools** in the MDSL `tools do` block
- Include input validation and error handling in facade methods
- Use `include_modules` for shared functionality with facade wrappers

Files in the `helpers` folder are loaded before the app files, so you can use helper files to extend the functionality of the application. This way, you can consolidate common functions into a module and reuse them in multiple apps.

If you want to add a new container other than the standard container, store Docker-related files in the `services` folder. When you want to execute a specific command available in each container or use a Python function, use the `send_command` method or `send_code` method defined in `MonadicApp`, which is the base class for all additional apps (for more information, see [Calling Functions in the App](#calling-functions-in-the-app)).

When defining an app by combining these elements, the folder structure will look like this:

```text
~/
└── monadic
    └── data
        ├── apps
        │   └── my_app
        │       ├── my_app_openai.mdsl
        │       ├── my_app_claude.mdsl
        │       ├── my_app_tools.rb
        │       └── my_app_constants.rb (optional)
        ├── helpers
        │   └── my_helper.rb
        └── services
            └── my_service
                ├── compose.yml
                └── Dockerfile
```

## Creating a Plugin

As you add more and more files to the `apps`, `helpers`, and `services` folders directly under the shared folder, it may become difficult to manage the code or difficult to redistribute. You can consolidate additional apps into a single folder and develop them as plugins.

To create a plugin, create a folder under `~/monadic/data/plugins` and create `apps` and other folders directly under the plugin folder to store the necessary files.

```text
~/
└── monadic
    └── data
        └── plugins
            └── my_plugin
                ├── apps
                │   └── my_app
                │       ├── my_app_openai.mdsl
                │       ├── my_app_claude.mdsl
                │       └── my_app_tools.rb
                ├── helpers
                │   └── my_helper.rb
                └── services
                    └── my_service
                        ├── compose.yml
                        └── Dockerfile
```

The above file structure is an example of a plugin that includes an app, a helper, and a service; a rather complex plugin structure. You can create a simpler plugin structure by omitting the `helpers` and `services` folders.

## Best Practices for MDSL Development

### Always Use Facade Pattern

For maintainable and robust MDSL applications:

**Benefits of Facade Pattern:**
- **Clear API**: Explicit method signatures
- **Input Validation**: Prevent invalid function calls
- **Error Handling**: Consistent error response format
- **Debugging**: Easy to trace and log method calls
- **Future-proof**: Interface stability when underlying implementation changes

**Implementation Template:**

Create a corresponding MDSL file:
```ruby
# my_app_openai.mdsl
app "MyAppOpenAI" do
  description "My custom app"
  icon "🚀"
  display_name "My App"
  
  llm do
    provider "openai"
    model ENV.fetch("OPENAI_DEFAULT_MODEL", "gpt-4.1")
  end
  
  system_prompt "You are a helpful assistant."
  
  tools do
    define_tool "method_name", "Description of what this tool does" do
      parameter :required_param, "string", "Description of the parameter", required: true
      parameter :optional_param, "string", "Optional parameter description", required: false
    end
  end
end
```

**Note on App Naming Convention**: The app name in the MDSL file should follow the pattern `AppNameProvider` where:
- `AppName` is your application name in PascalCase
- `Provider` is the LLM provider name capitalized (e.g., `OpenAI`, `Claude`, `Gemini`)
- Examples: `ChatOpenAI`, `CodingAssistantClaude`, `ResearchAssistantGemini`

And a tools file with facade pattern:
```ruby
# my_app_tools.rb
class MyAppOpenAI < MonadicApp  # Class name must match the app name in MDSL
  # Facade method with full validation and error handling
  def method_name(required_param:, optional_param: nil)
    # 1. Input validation
    validate_inputs!(required_param, optional_param)
    
    # 2. Call underlying implementation
    result = underlying_implementation(required_param, optional_param)
    
    # 3. Return structured response
    format_response(result)
  rescue StandardError => e
    handle_error(e)
  end
  
  private
  
  def validate_inputs!(required_param, optional_param)
    raise ArgumentError, "Required parameter missing" if required_param.nil?
    # Add specific validations
  end
  
  def format_response(result)
    { success: true, data: result }
  end
  
  def handle_error(error)
    { success: false, error: error.message }
  end
end
```

### Ensure Session Safety

**Important**: Monadic Chat uses a shared-instance architecture where each app class has a single instance shared across all users. This requires careful handling to prevent data contamination between sessions.

#### ✅ DO: Use Pure Functions

All tool methods should be pure functions that rely only on their parameters:

```ruby
class MyApp < MonadicApp
  def my_tool(input:, options:)
    # ✅ CORRECT: Uses only parameters
    result = process_input(input, options)

    format_tool_response(
      success: true,
      output: result
    )
  end

  private

  def process_input(input, options)
    # Pure function - same input produces same output
    # No instance variables, no side effects
    input.upcase if options[:uppercase]
  end
end
```

**Why Safe**:
- No shared state between users
- Thread-safe by design
- Predictable behavior

#### ❌ DON'T: Use Instance Variables for Session State

Never store session-specific data in instance variables:

```ruby
class MyApp < MonadicApp
  def validate_code(code:)
    # ❌ WRONG: User B can overwrite User A's data
    @last_validated_code = code
    @validation_timestamp = Time.now

    validate(code)
  end

  def preview_code
    # ❌ WRONG: May read another user's data
    code = @last_validated_code
    generate_preview(code)
  end
end
```

**Why Unsafe**:
- User A validates code → Stores in `@last_validated_code`
- User B validates different code → **Overwrites** `@last_validated_code`
- User A requests preview → Gets User B's code!

#### Acceptable Uses of Instance Variables

**Read-only configuration** (same for all users):

```ruby
class MyApp < MonadicApp
  def initialize
    super
    @config = load_app_config  # ✅ OK: Read-only configuration
  end

  def my_tool(input:)
    # Using @config for read-only settings is fine
    process(input, max_length: @config[:max_length])
  end
end
```

#### Best Practices Summary

1. **Design stateless tools**: Each tool invocation should be independent
2. **Pass data through parameters**: All inputs as function arguments
3. **Return all outputs**: No side effects or state mutation
4. **Use filesystem for persistence**: Write to files instead of instance variables
5. **Read-only instance vars only**: Configuration that's the same for all users

For detailed information on session safety and app isolation, see the [App Isolation and Session Safety](../../docs_dev/app_isolation_and_session_safety.md) internal documentation.

## Troubleshooting Common Issues

### Missing Method Errors
If you encounter "undefined method" errors:

1. **Create facade methods**: Use `*_tools.rb` files with facade pattern for all custom methods
2. **Add module integration**: Use `include_modules` with facade wrappers for shared functionality
3. **Verify class naming**: Class name in tools file must match the app ID

**Facade Pattern Fix**:
```ruby
# app_name_tools.rb
class AppNameProvider < MonadicApp
  def custom_method(param:, options: {})
    # Input validation
    raise ArgumentError, "Parameter required" if param.nil?
    
    # Call underlying implementation
    result = underlying_service.method(param, options)
    
    # Return structured response
    { success: true, data: result }
  rescue StandardError => e
    { success: false, error: e.message }
  end
end
```

## Helper Modules :id=helper-modules

The following helper modules are available for use in your apps:

- `OpenAIHelper` - OpenAI API integration
- `ClaudeHelper` - Anthropic Claude API integration
- `CohereHelper` - Cohere API integration
- `MistralHelper` - Mistral AI API integration
- `GeminiHelper` - Google Gemini API integration
- `DeepSeekHelper` - DeepSeek API integration
- `PerplexityHelper` - Perplexity API integration
- `GrokHelper` - xAI Grok API integration
- `OllamaHelper` - Ollama local model integration

For a complete overview of which apps are compatible with which models, see the [App Availability by Provider](../basic-usage/basic-apps.md#app-availability) section in the Basic Apps documentation.

?> The "function calling" or "tool use" functions can be used in `OpenAIHelper`, `ClaudeHelper`, `CohereHelper`, `MistralHelper`, `GeminiHelper`, `GrokHelper`, and `DeepSeekHelper` (see [Calling Functions in the App](#calling-functions-in-the-app)). Function calling support varies by provider - check the specific provider's documentation for limitations.

!> If the Ruby script is not valid and an error occurs, Monadic Chat will not start, and an error message will be displayed in the console. App loading errors are shown when starting the server with details about which apps failed to load and why.

### Settings

There are required and optional settings. If the required settings are not specified, an error message will be displayed on the browser screen when the application starts. Here are the required settings:

`display_name` (string, required)
Specify the display name of the application that appears in the UI (required).

`icon` (string, required)
Specify the icon for the application (emoji or HTML).

`description` (string, required)
Describe the application.

`initial_prompt` (string, required)
Specify the text of the system prompt.

`group` (string)

Specify the group name for grouping the app on the Base App selector on the web settings screen. Though optional, it is recommended to specify some group name to distinguish custom apps from the base apps.

There are many optional settings. See [Setting Items](./setting-items.md) for details.

## Calling Functions in the App :id=calling-functions-in-the-app

You can define functions and tools that the AI agent can use in the app. With the MDSL format, tools must be defined in the `tools do` block. There are three ways to implement the underlying functionality: 1) Define Ruby methods in the tools file; 2) Execute commands or shell scripts; and 3) Execute program code in languages other than Ruby.

### Define Ruby Methods

To define Ruby methods that the AI agent can use:

1. Define tools explicitly in the MDSL file's `tools do` block
2. Implement corresponding methods in the `*_tools.rb` file
3. Ensure the method signatures match the tool definitions

The tool definition format varies slightly among providers:
- All providers: Support up to 20 function calls
- Code execution: All providers use `run_code` for code execution
- Array parameters: OpenAI requires `items` property

### Execute Commands or Shell Scripts

You can execute commands or shell scripts in the app. The `send_command` method is used to execute commands or shell scripts. The `send_command` method is defined in the `MonadicApp` module, which is the base class for all additional apps. Commands or shell scripts are executed with the shared folder (`/monadic/data`) as the current working directory in each container. Shell scripts saved in the `scripts` directory in the shared folder on the host computer are executable in the container, and you can execute them by specifying the script name.

The `send_command` method takes the following arguments: the name of the command or shell script to execute (`command`), the container name (`container`), and an optional message to display when the command is executed successfully (`success`). The `container` argument uses short string notation; for example, `python` represents `monadic-chat-python-container`.

```ruby
send_command(command: "ls",container: "python", success_with_output: "Linux `ls` command executed with the following output:\n")
```

As an example, the above command executes the `ls` command in the `python` container and displays the message "Linux ls command executed successfully" when the command is executed successfully. If the `success` argument is omitted, the message "Command has been executed" is displayed, and if the `success_with_output` argument is omitted, the message "Command has been executed with the following output: " is displayed.

?> It is possible to set up a recipe file so that the AI agent can use the `send_command` method directly. However, it is recommended to create a wrapper method in the recipe file and call the `send_command` method from there, implementing necessary error handling procedures. The `MonadicApp` class provides a wrapper method called `run_command` that works similarly to `send_command` but returns a specific message if any arguments are missing. It is recommended to use `run_command` instead of `send_command` directly in your recipe files.


### Execute Program Code

If you want to execute program code in a language other than Ruby, you can use the `send_code` method. The `send_code` method is defined in the `MonadicApp` module, which is the base class for all additional apps. Note that the `send_code` method only supports code execution in the Python container (`monadic-chat-python-container`).

The `send_code` method runs the given program code in the container by first saving the code to a temporary file with the specified extension and then executing the file. It takes the following arguments: the program code to execute (`code`), the command to run the code (such as `python`) (`command`), the extension of the file to save the code (`extension`), and an optional message to display when the code is executed successfully (`success`).

```ruby
send_code(code: "print('Hello, world!')", command: "python", extension: "py", success: "Python code executed successfully")
```

As an example, the above code runs the `print('Hello, world!')` code in the Python container and returns the result.  If the `success` argument is omitted, the message "The code has been executed successfully." is displayed.

The `send_code` method detects if new files have been created as a result of the code execution. If new files are present, it returns the file names as part of the response along with the success message.

**Without new files created:**

```text
The code has been executed successfully; Output: OUTPUT_TEXT
```

**With new files created:**

```text
The code has been executed successfully; File(s) generated: NEW_FILE; Output: OUTPUT_TEXT
```

With the correct information about the generated files, the AI agent can continue processing them further.

?> If you set up the recipe file so that the AI agent can call `send_code` directly, an error will occur in the container if any of the required arguments are not specified. Therefore, it is recommended to create a wrapper method and handle errors appropriately.

## Using LLM in Functions and Tools

In functions and tools called by the AI agent, you may want to make requests to the AI agent. In such cases, you can use the `send_query` method available in the `MonadicApp` class.

The `send_query` method is used to make requests to the AI agent from within functions and tools in the app. It sends a request to the AI agent through the API of the language model currently used in the app (or a language model by the same vendor) and returns the result. You can send a request to the AI agent by passing a hash with API parameters set to the method as an argument.

The hash of API parameters must specify an array of messages as the value of the `messages` key. The `model` key specifies the language model to use. Various parameters available in the API of that language model can also be used.

In queries using `send_query`, `stream` is set to `false` (it is already set to `false` by default, so there is no need to specify it explicitly).

The following is an example of how to use `send_query` in a function or tool created using Ruby in the tools file.

```ruby
# my_app_tools.rb
class MyAppOpenAI < MonadicApp
  def my_function
    # Set parameters
    parameters = {
      message: {
        model: "gpt-4.1",
        messages: [
          {
            role: "user",
            content: "What is the name of the capital city of Argentina?"
          }
        ]
      }
    }
    # Send a request to OpenAI
    send_query(parameters)
  end
end
```
