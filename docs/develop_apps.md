# Developing Apps

In Monadic Chat, you can develop AI chatbot applications using original system prompts. This page explains the steps to develop a new application.

## How to Add a Simple App

1. Create a recipe file for the app. The recipe file is written in Ruby.
2. Save the recipe file in the `apps` directory of the shared folder (`~/monadic/data/apps`).
3. Restart Monadic Chat.

The recipe file can be saved in any directory under the `apps` directory as long as it is correctly written.

### How to Add an Advanced App

The recipe file for the app defines a class that inherits from `MonadicApp` and describes the application settings in the instance variable `@settings`. By defining a module in the helper folder, you can implement common functions that can be used in multiple apps.

When adding a new container other than the standard container, store Docker-related files in the `services` folder. When you want to execute a specific command available in each container or use a Python function, use the `send_command` method or `send_code` method defined in `MonadicApp`, which is the base class for all additional apps.

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

Adding files to the `apps`, `helpers`, and `services` folders directly under the shared folder can make it difficult to manage code and difficult to redistribute. You can consolidate additional apps into a single folder and develop them as plugins.

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

If the Ruby script is not valid and an error occurs, Monadic Chat will not start, and an error message will be displayed. Details of the specific error are recorded in a log file saved in the shared folder (`~/monadic/data/error.log`).

## Settings

There are required and optional settings. If the required settings are not specified, an error message will be displayed on the browser screen when the application starts.

`app_name` (string, required)

Specify the name of the application (required).

`icon` (string, required)

Specify the icon for the application (emoji or HTML).

`description` (string, required)

Describe the application.

`initial_prompt` (string, required)

Specify the text of the system prompt.

`model` (string)

Specify the default model. If not specified, `gpt-4o-mini` is used (for apps including the `OpenAIHelper` module).

`temperature` (float)

Specify the default temperature.

`presence_penalty` (float)

Specify the default `presence_penalty`. It is ignored if the model does not support it.

`frequency_penalty` (float)

Specify the default `frequency_penalty`. It is ignored if the model does not support it.

`top_p` (float)

Specify the default `top_p`. It is ignored if the model does not support it.

`max_tokens` (int)

Specify the default `max_tokens`.

`context_size` (int)

Specify the default `context_size`.

`easy_submit` (bool)

Specify whether to send messages entered in the text box with just the ENTER key.

`auto_speech` (bool)

Specify whether to read aloud the AI assistant's responses.

`image` (bool)

Specify whether to display an image attachment button in the message box sent to the AI assistant.

`pdf` (bool)

Specify whether to enable the PDF database feature.

`initiate_from_assistant` (bool)

Specify whether to start with the first message from the AI assistant before the user.

`sourcecode` (bool)

Specify whether to enable syntax highlighting for program code.

`mathjax` (bool)

Specify whether to enable rendering of mathematical expressions using [MathJax](https://www.mathjax.org/).

`jupyter` (bool)

Specify `true` when integrating with Jupyter Notebook (optimizes MathJax display).

`monadic` (bool)

Specify the app in Monadic mode. For Monadic mode, refer to [Monadic Mode](/ja/monadic-mode).

`file` (bool)

Specify whether to enable the text file upload feature on the app's web settings screen. The contents of the uploaded file are added to the end of the system prompt.

`abc` (bool)

Specify whether to enable the display and playback of musical scores entered in [ABC notation](https://abcnotation.com/) in the AI agent's response. ABC notation is a format for describing musical scores.

`disabled` (bool)

Specify whether to disable the app. Disabled apps are not displayed in the Monadic Chat menu.

`toggle` (bool)

Specify whether to toggle the display of part of the AI agent's response (meta information, tool usage). Currently, it is only available for apps including the `ClaudeHelper` module.

`models` (array)

Specify a list of available models. If not specified, the list of models provided by the included module (e.g., `OpenAIHelper`) is used.

`tools` (array)

Specify a list of available functions. The actual definition of the functions specified here should be written in the recipe file or in another file as instance methods of the `MonadicAgent` module.

`response_format` (hash)

Specify the output format when outputting in JSON format. For details, refer to [OpenAI: Structured outputs](https://platform.openai.com/docs/guides/structured-outputs).

## Calling Functions in the App

It is possible to define functions that the AI agent can use in the app. Define functions in Ruby, specify function names and arguments in `@settings`' `tools`, and describe how to use the functions in `initial_prompt`.

When you want to execute a specific command available in each container or use a Python function, use the `send_command` method or `send_code` method defined in `MonadicApp`, which is the base class for all additional apps.

### `send_command`

The `send_command` method is used to execute a command in the container. Specify the command as a string in the argument. The return value is a string of the command execution result.

```ruby
send_command(command: "ls", container: "python", success: "Command executed successfully.")
```

For example, the above code executes the `ls` command in the Python container and returns the result. The `command` argument specifies the command to execute. The `container` argument specifies the container to execute the command in. If `python` is specified, it refers to the `monadic-chat-python-container`. The `success` argument specifies the message to insert before the command execution result if the command execution is successful.

### `send_code`

The `send_code` method is used to execute code in the container. It saves the given code to a temporary file and executes that file with the specified program. When a new file is generated as a result, the returned string differs depending on whether the file is generated.

```ruby
send_code(code: "print('Hello, world!')", command: "python", extension: "py")
```

For example, the above code executes the `print('Hello, world!')` code in the Python container and returns the result. The `code` argument specifies the code to execute. The `container` argument specifies the program to execute the code. The `extension` argument specifies the extension of the temporary file.

**When a file is not generated**

```text
The code has been executed successfully; Output: OUTPUT
```

**When a file is generated**

```text
The code has been executed successfully; Files generated: NEW FILE; Output: OUTPUT
```

By calling the `send_command` or `send_code` method from a method used in the app, you can realize advanced functions that utilize the Docker container's capabilities by returning messages to the AI agent according to the results.
