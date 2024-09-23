# Developing Apps

In Monadic Chat, you can develop AI chatbot applications using original system prompts. This page explains the steps to develop a new application.

## How to Add

1. Create a recipe file for the app. The recipe file is written in Ruby.
2. Save the recipe file in the `apps` directory of the shared folder (`~/monadic/data/apps`).
3. Restart Monadic Chat.

The recipe file can be saved in any directory under the `apps` directory as long as it is correctly written. However, it is conventionally recommended to create an `app_name` directory directly under the `apps` directory and save the recipe file named `app_name_app.rb` in it.

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
