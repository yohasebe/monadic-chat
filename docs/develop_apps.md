# Developing Apps

In Monadic Chat, you can develop AI chatbot applications using original system prompts. This section explains the steps to develop a new application.

## How to Add a Simple App

1. Create a recipe file for the app. The recipe file is written in Ruby.
2. Save the recipe file in the `apps` directory of the shared folder (`~/monadic/data/apps`).
3. Restart Monadic Chat.

The recipe file can be saved in any directory under the `apps` directory as long as it is correctly written.

For information on how to write a recipe file, see [Writing the Recipe File](#writing-the-recipe-file).

### How to Add an Advanced App

The recipe file for an app defines a class that inherits from `MonadicApp` and describes the application settings in the instance variable `@settings`. Files in the `helpers` folder are loaded before the recipe file, so you can use helper files to extend the functionality of the application. For example, you can define a module in the helper folder and include it in the class that inherits from `MonadicApp` defined in the recipe file. This way, you can consolidate common functions into a module and reuse them in multiple apps.

If you want to add a new container other than the standard container, store Docker-related files in the `services` folder. When you want to execute a specific command available in each container or use a Python function, use the `send_command` method or `send_code` method defined in `MonadicApp`, which is the base class for all additional apps (for more information, see [Calling Functions in the App](#calling-functions-in-the-app)).

When defining an app by combining these elements, the folder structure will look like this:

```text
~/
└── monadic
    └── data
        ├── apps
        │   └── my_app
        │       └── my_app.rb
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
                │       └── my_app.rb
                ├── helpers
                │   └── my_helper.rb
                └── services
                    └── my_service
                        ├── compose.yml
                        └── Dockerfile
```

The above file structure is an example of a plugin that includes an app, a helper, and a service; a rather complex plugin structure. You can create a simpler plugin structure by omitting the `helpers` and `services` folders.

## Writing the Recipe File

In the recipe file, define a class that inherits from `MonadicApp` and describe the application settings in the instance variable `@settings`.

```ruby
class RobotApp < MonadicApp
  include OpenAIHelper
  @settings = {
    app_name: "Robot App",
    icon: "🤖",
    description: "This is a sample robot app.",
    initial_prompt: "You are a friendly robot that can help with anything the user needs. You talk like a robot, always ending your sentences with '...beep boop'.",
  }
end
```

The following modules are available for use in the recipe file:

- `OpenAIHelper` to use the OpenAI API
- `ClaudeHelper` to use the Anthropic Claude API
- `CommandRHelper` to use the Cohere Command R API
- `MistralHelper` to use the Mistral AI API
- `GeminiHelper` to use the Google Gemini API

?> The "function calling" or "tool use" functions can be used in `OpenAIHelper`, `ClaudeHelper`, `CommandRHelper`, and `MistralHelper` (see [Calling Functions in the App](#calling-functions-in-the-app)). Currently, these functions are not available in `GeminiHelper`.

!> If the Ruby script is not valid and an error occurs, Monadic Chat will not start, and an error message will be displayed. Details of the specific error are recorded in a log file saved in the shared folder (`~/monadic/data/error.log`).

## Settings

There are required and optional settings. If the required settings are not specified, an error message will be displayed on the browser screen when the application starts. Here are the required settings:

`app_name` (string, required)

Specify the name of the application (required).

`icon` (string, required)

Specify the icon for the application (emoji or HTML).

`description` (string, required)

Describe the application.

`initial_prompt` (string, required)

Specify the text of the system prompt.

There are many optional settings. See [Setting Items](ja/setting-items.md) for details.

### Using Functions and Tools in the App

You can define functions and tools that the AI agent can use in the app. There are three ways to define functions and tools: 1) Define Ruby methods in the recipe file; 2) Execute commands or shell scripts; and 3) Execute program code in language other than Ruby.

### Define Ruby Methods

There are three steps to define a Ruby method that the AI agent can use:

1. Define a Ruby method (function) in the recipe file
2. Specify the function name and arguments in JSON schema in `tools` of `@settings`
3. Describe how to use the method (function) in `initial_prompt`

The ways to specify the function name and arguments in `tools` are somewhat different among the language models. Refer to the following documentation for details:

- OpenAI GPT-4: [Function calling guide](https://platform.openai.com/docs/guides/function-calling/function-calling-with-structured-outputs)
- Anthropic Claude: [Tool use (function calling)](https://docs.anthropic.com/en/docs/build-with-claude/tool-use)
- Cohere Command R:  [Tool use](https://docs.cohere.com/docs/tools)
- Mistral AI:  [Function calling](https://docs.mistral.ai/capabilities/function_calling/)

### Execute Commands or Shell Scripts

You can execute commands or shell scripts in the app. The `send_command` method is used to execute commands or shell scripts. The `send_command` method is defined in the `MonadicApp` module, which is the base class for all additional apps. Commands or shell scripts are executed with the shared folder (`/monadic/data`) as the current working directory in each container. Shell scripts saved in the `scripts` directory in the shared folder on the host computer are executable in the container, and you can execute them by specifying the script name.

The `send_command` method ise used with the following arguments: the name of the command or shell script to execute (`command`), the container name (`container`), and the message to display when the command is executed successfully (`success`).

```ruby
send_command(command: "ls", container: "python", success: "Linux ls command executed successfully")
```

As an example, the above command executes the `ls` command in the `python` container and displays the message "Linux ls command executed successfully" when the command is executed successfully. The `container` aregument is specified in a short string format, with `python` representing the `monadic-chat-python-container`. The `success` argument is optional, but by specifying an appropriate message, the AI agent can correctly interpret the command execution result. If the `success` argument is omitted, the message "Command executed successfully" is displayed.

?> It is possible to set up a recipe file so that the AI agent can use the `send_command` method directly. However, it is recommended to create a wrapper method in the recipe file and call the `send_command` method from there with the necessary procedures to handle errors and exceptions gracefully.

### Execute Program Code

If you want to execute program code in a language other than Ruby, you can use the `send_code` method. The `send_code` method is defined in the `MonadicApp` module, which is the base class for all additional apps.

?> The `send_code` method only supports code execution in the Python container (`monadic-chat-python-container`).

The `send_code` methods runs the given program code in the container by first saving the code to a file with the specified extension and then executing the file. It is used with the following arguments: the program code to execute (`code`), the command to run the code (such as `python`) (`command`), the extension of the file to save the code (`extension`), and the message to display when the code is executed successfully (`success`). The `success` argument is optional, but by specifying an appropriate message, the AI agent can correctly interpret the code execution result. If the `success` argument is omitted, the message "The code has been executed successfully." is displayed.

```ruby
send_code(code: "print('Hello, world!')", command: "python", extension: "py", success: "Python code executed successfully")
```

As an example, the above code runs the `print('Hello, world!')` code in the Python container and returns the result.

The `send_code` method detects if new files have been created as a result of the code execution and if there are any new files, it returns the file names as part of the response along with the success message.

**Without new files created:**

```text
The code has been executed successfully; Output: OUTPUT_TEXT
```

**With new files created:**

```text
The code has been executed successfully; File(s) generated: NEW_FILE; Output: OUTPUT_TEXT
```

With the correct information about the generated files, the AI agent can continue processing them further.


?> If you set up the recipe file so that the AI agent can call `send_code` directly, an error will occur in the container if any of the required arguments are not specified. Therefore, when calling `send_command`, be sure to handle errors properly. The `MonadicApp` class provides a wrapper method called `run_command` that works the same way as `send_command`, but returns a message if any arguments are missing.

## Using LLM in Functions and Tools

In functions and tools called by the AI agent, you may want to make requests to the AI agent. In such cases, you can use `ask_openai` method available in the `MonadicApp` class.

The `ask_openai` method is used to make requests to the AI agent from within functions and tools in the app. It takes a hash as an argument that specifies the request parameters available for the OpenAI Chat Completions API. 

The parameter hash must have a `messages` key and an array of messages as its value. The `model` key specifies the language model to use (defaults to `gpt-4o-mini`). Other parameters available for the OpenAI Chat Completions API can also be used. See the [Chat Completions](https://platform.openai.com/docs/guides/chat-completions) API documentation for more information.

!> The `stream` parameter of the OpenAI Chat Completions API must be `false`. It is already set to `false` by default, so there is no need to change it. If you set `stream` to `true`, you will need to implement (unnecessary) procedures in the function or tool to handle the information exchange between the LLMs.

The following is an example of using the `ask_openai` method:

```ruby
def my_function
  # Set the parameters for the OpenAI API
  parameters = {
    message: {
      model: "gpt-4o",
      messages: [
        {
          role: "user",
          content: "What is the name of the capital city of Argentina?"
        }
      ]
    }
  }
  # Send a request to the OpenAI API
  ask_openai(parameters)
end
```
