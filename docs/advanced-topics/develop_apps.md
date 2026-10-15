# Developing Apps

In Monadic Chat, you can add your own apps, each with its own system prompt and tools. This page explains how.

## Developing Apps with MDSL :id=how-to-add-a-simple-app

Apps are defined in MDSL (Monadic Domain Specific Language) files with the `.mdsl` extension. Each MDSL file defines one app for one provider. From the MDSL file, Monadic Chat creates a Ruby class with the app's name (for example `MyAppOpenAI`) that includes the provider's helper module.

Tool methods written in Ruby go in a module named after the app without the provider suffix, plus `Tools`: for the apps `MyAppOpenAI` and `MyAppClaude`, the module is `MyAppTools`. When this module exists, it is included in every provider's app class automatically.

**Common app patterns**:
- **Tools module**: an `*_tools.rb` file with a `<AppName>Tools` module for the app's own tools (recommended)
- **Shared tools**: tool groups imported with `import_shared_tools`; see [Tool Groups](tool-groups.md)
- **Modules**: other modules added with `include_modules`

**Repeated errors**: When tools fail with the same kind of error three times, Monadic Chat stops the retries and shows a suggestion, so the model does not retry without end.

**Tool requirements**:
- Every tool the system prompt mentions needs a `define_tool` block or an imported tool group.
- The parameters of `define_tool` must match the keyword arguments of the Ruby method.
- The Ruby method of a tool must be public. Monadic Chat runs only the tools given to the model in the request; a call to any other name returns an error to the model.

### File Structure Patterns :id=file-structure-patterns

**Pattern A: Constants shared by several providers**
```
apps/coding_assistant/
├── coding_assistant_constants.rb # Shared constants (ICON, DESCRIPTION, etc.)
├── coding_assistant_tools.rb     # CodingAssistantTools module
├── coding_assistant_openai.mdsl  # OpenAI app
├── coding_assistant_claude.mdsl  # Claude app
└── coding_assistant_gemini.mdsl  # Gemini app
```

**Pattern B: MDSL only**
```
apps/simple_app/
└── simple_app_openai.mdsl # The whole app; no Ruby file is needed
```

**Pattern C: Tools module (recommended)**
```
apps/novel_writer/
├── novel_writer_tools.rb         # NovelWriterTools module
├── novel_writer_openai.mdsl      # OpenAI app
└── novel_writer_mistral.mdsl     # Mistral app
```

### Support File Naming Conventions

- **Tool implementation files**: `*_tools.rb` (e.g., `novel_writer_tools.rb`)
- **Constants files**: `*_constants.rb` (e.g., `coding_assistant_constants.rb`)

### Basic MDSL Structure

For the MDSL format, including all blocks and settings, see [Monadic DSL](monadic_dsl.md).

## Steps to Add an App

1. Create an MDSL file for the app, and a `*_tools.rb` file if the app has its own tools.
2. Save the files in the `apps` folder of the shared folder (`~/monadic/data/apps`). Any subfolder of `apps` works.
3. Restart Monadic Chat.

Loading rules:

- `.rb` files are loaded before `.mdsl` files.
- Files whose names start with `_` are not loaded.
- Files in folders named `test`, `helpers` or `services` inside `apps` are not loaded as apps.
- Files reached through a symbolic link are not loaded.
- In development mode (`rake server:debug`), apps and helpers in the shared folder are loaded only when the shell that starts the server sets `MONADIC_LOAD_USER_CODE=true`.

If an app fails to load, the other apps still load. The failed apps and the errors are listed in the server output (`docker logs monadic-chat-ruby-container`, or the terminal in development mode).

## How to Add an Advanced App

- Create one MDSL file per provider (e.g., `my_app_openai.mdsl`, `my_app_claude.mdsl`).
- Write the tool methods in a `MyAppTools` module in `my_app_tools.rb`.
- Define every tool in the MDSL `tools do` block.
- Validate the inputs and handle errors in the tool methods.

Ruby files in the `helpers` folder of the shared folder, and in `apps/<your_app>/helpers`, are loaded before the app files. Put modules that several apps use there.

To add a Docker container, put its files in the `services` folder; see [Adding Docker Containers](adding-containers.md). To run a command in a container or run Python code, use the `send_command` or `send_code` method of `MonadicApp`, the base class of every app (see [Calling Functions in the App](#calling-functions-in-the-app)).

With these elements, the folders look like this:

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

## Best Practices for MDSL Development

### Always Use Facade Pattern :id=always-use-facade-pattern

Write each tool as a method that checks its inputs, calls the code that does the work, and returns a result the model can read. A tool returns a String; start the message with `❌` when the tool fails, so the model can tell the user.

**Implementation Template:**

The MDSL file:
```ruby
# my_app_openai.mdsl
app "MyAppOpenAI" do
  description "My custom app"
  icon "fa-solid fa-rocket"
  display_name "My App"

  llm do
    provider "openai"
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

**App naming**: The app name is `AppNameProvider`:
- `AppName` is the name of your app in PascalCase
- `Provider` is one of `OpenAI`, `Claude`, `Gemini`, `Mistral`, `Cohere`, `Grok`, `DeepSeek`, `Ollama`
- Examples: `ChatOpenAI`, `CodingAssistantClaude`, `ResearchAssistantGemini`

The tools file:
```ruby
# my_app_tools.rb
module MyAppTools
  def method_name(required_param:, optional_param: nil)
    raise ArgumentError, "required_param is empty" if required_param.to_s.strip.empty?

    result = do_the_work(required_param, optional_param)
    "Done: #{result}"
  rescue ArgumentError => e
    "❌ #{e.message}"
  rescue StandardError => e
    "❌ method_name failed: #{e.message}"
  end

  private

  def do_the_work(required_param, optional_param)
    # ...
  end
end
```

### Model Specification for Custom Apps

Omit `model` from the `llm` block to use the default model of the provider:

```ruby
llm do
  provider "openai"
end
```

The default comes from the `<PROVIDER>_DEFAULT_MODEL` variable in `~/monadic/config/env`, and otherwise from the provider defaults in Monadic Chat. For the full order and for menus with several models, see [Model Specification Best Practices](monadic_dsl.md#model-specification-best-practices).

### Ensure Session Safety

Each app class has one instance, shared by every session. Data stored in instance variables is therefore shared between sessions.

#### ✅ DO: Use Pure Functions

Tool methods should depend only on their parameters:

```ruby
module MyAppTools
  def my_tool(input:, uppercase: false)
    # Uses only parameters
    uppercase ? input.upcase : input
  end
end
```

#### ❌ DON'T: Use Instance Variables for Session State

Do not store session data in instance variables:

```ruby
module MyAppTools
  def validate_code(code:)
    # WRONG: another session can overwrite this
    @last_validated_code = code
    validate(code)
  end

  def preview_code
    # WRONG: may read another session's code
    generate_preview(@last_validated_code)
  end
end
```

If session A validates code and session B then validates other code, a preview requested in session A shows session B's code.

#### Acceptable Uses of Instance Variables

Read-only configuration that is the same for every session:

```ruby
module MyAppTools
  def my_tool(input:)
    process(input, max_length: app_config[:max_length])
  end

  private

  def app_config
    @app_config ||= { max_length: 1000 }.freeze  # OK: read-only, same for everyone
  end
end
```

#### Best Practices Summary

1. **Stateless tools**: Each call works from its inputs and returns its outputs.
2. **Pass data through parameters**: Give every input as an argument.
3. **Return all outputs**: Return the results instead of keeping them in hidden state.
4. **Use `session` for conversation state**: For data that belongs to one conversation (for example the last generated file name), accept a `session:` keyword argument; see [Define Ruby Methods](#define-ruby-methods).
5. **Use files for persistence**: Write data that must last to the shared folder.
6. **Read-only instance variables only**: Use instance variables only for configuration that is the same for every session.

## Troubleshooting Common Issues

### Missing Method Errors

If a tool call fails with "undefined method":

1. Check that the module name is the app name without the provider suffix, plus `Tools` (`MyAppOpenAI` → `MyAppTools`).
2. Check that the method name matches the `define_tool` name.
3. Check that the keyword arguments match the `define_tool` parameters.

## Helper Modules :id=helper-modules

Each app class includes the helper module of its provider:

- `OpenAIHelper` - OpenAI
- `ClaudeHelper` - Anthropic Claude
- `CohereHelper` - Cohere
- `MistralHelper` - Mistral AI
- `GeminiHelper` - Google Gemini
- `DeepSeekHelper` - DeepSeek
- `GrokHelper` - xAI Grok
- `OllamaHelper` - Ollama

Tool calling works with all of them (see [Calling Functions in the App](#calling-functions-in-the-app)). For which apps are available with which providers, see [App Availability by Provider](../basic-usage/basic-apps.md#app-availability).

## Settings

An app needs these settings. When one is missing, the app still loads, a default is used, and the app's description shows a warning:

`description` (string)
Describes the app.

`icon` (string)
The icon: a Font Awesome class such as `"fa-solid fa-rocket"`, or an icon name.

`system_prompt` (string)
The system prompt.

These are optional:

`display_name` (string)
The name shown in the UI. The default is the app name.

`group` (string, inside `features do`)
The group in the app menu. The default is the provider's group (for example "OpenAI").

```ruby
features do
  group "My Apps"
end
```

For the other settings, see [Setting Items](./setting-items.md).

## Calling Functions in the App :id=calling-functions-in-the-app

Tools are defined in the `tools do` block of the MDSL file. The work behind a tool can be done in three ways: 1) Ruby methods in the tools module; 2) commands or shell scripts in a container; 3) program code run in the Python container.

### Define Ruby Methods :id=define-ruby-methods

1. Define the tool in the MDSL `tools do` block.
2. Write a method with the same name in the tools module.
3. Make the keyword arguments of the method match the parameters of the tool.

**The `session` argument:**
- When the method accepts a `session:` keyword argument, Monadic Chat passes the current conversation's session to it. You do not need to declare `session` in `define_tool`.
- Use it for state that belongs to one conversation, for example `session[:last_image_filename] = "image.png"`.

How tool definitions are sent, and how many tool calls a turn may make, differ by provider; see [Provider-Specific Considerations](monadic_dsl.md#provider-specific-considerations).

### Execute Commands or Shell Scripts

`send_command` runs a command in a container, with the shared folder (`/monadic/data`) as the working directory.

```ruby
send_command(command: "ls", container: "python", success_with_output: "Files in the shared folder:\n")
```

Arguments:
- `command`: the command to run
- `container`: the container in short form; `python` means `monadic-chat-python-container`, and `my-service` means `monadic-chat-my-service-container`
- `success`: the message returned when the command succeeds without output (default: "Command has been executed.")
- `success_with_output`: the text put before the output when there is output (default: "Command has been executed with the following output: ")

In the Python container, the `scripts` folder of the shared folder is on `PATH`, after the system folders, so scripts saved there can be run by name.

On the Ruby side (`container: "ruby"`), only the Ruby scripts that come with Monadic Chat run.

?> `send_command` and `send_code` are private methods of `MonadicApp`: call them from a tool method that checks its arguments first. The model then gets a clear message when an argument is wrong.

### Execute Program Code

`send_code` runs program code in the Python container (`monadic-chat-python-container`). It saves the code to a file with the given extension and runs it.

```ruby
send_code(code: "print('Hello, world!')", command: "python", extension: "py", success: "Python code executed successfully")
```

Arguments: the code (`code`), the command that runs it (`command`, such as `python`), the file extension (`extension`), and the message for success (`success`, default "The code has been executed successfully").

The result tells the model which files the code created or changed in the shared folder:

**No new files:**

```text
The code has been executed successfully

NOTE: No image files were created. Do NOT display any images.

Output: OUTPUT_TEXT
```

**New image files:**

```text
The code has been executed successfully

IMAGE FILES CREATED (verified to exist):
- /data/plot.png

These images are automatically displayed in the chat. Do NOT include <img> tags in your response.

Output: OUTPUT_TEXT
```

**Other new files:**

```text
The code has been executed successfully; File(s) generated or modified: /data/report.html

Output: OUTPUT_TEXT
```

?> As with `send_command`, call `send_code` from a tool method that checks its arguments first.

## Using LLM in Functions and Tools

A tool can send its own request to a model with `send_query`. It comes from the provider's helper module, so it uses the API of the app's provider. It takes a hash of API parameters with a `messages` array, and the model as the `model:` keyword argument. Without `model:`, the provider's default model is used. The request is not streamed.

```ruby
# my_app_tools.rb
module MyAppTools
  def capital_of_argentina
    send_query(
      { "messages" => [{ "role" => "user", "content" => "What is the capital of Argentina?" }] },
      model: "<model-id>"  # optional
    )
  end
end
```

## MCP Integration

Monadic Chat has an MCP (Model Context Protocol) server called Monadic Conduit. It publishes a fixed set of tools in the `monadic_*` namespace (queries, Knowledge Base, media analysis and generation, and others) and does not publish the tools of each app. There is nothing MCP-specific to do when you create an app.

See [MCP Integration](/advanced-topics/mcp-integration.md) for the server setup, the tools, and client configuration.
