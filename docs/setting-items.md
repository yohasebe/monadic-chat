# Application Setting Items

The setting items for the application are described in the recipe file, where the class that inherits from `MonadicApp` is defined. The settings are defined in the `@settings` variable in the recipe file. There are required and optional settings. If the required settings are not specified, an error message will be displayed on the browser screen when the application is launched.

## Required Settings

`app_name` (string, required)
Specify the name of the application (required).

`icon` (string, required)
Specify the icon for the application (emoji or HTML).

`description` (string, required)
Describe the application.

`initial_prompt` (string, required)
Specify the text of the system prompt.

## Optional Settings

`group` (string)

Specify the group name for grouping the app on the Base App selector on the web settings screen. When adding custom apps, it is recommended to specify some group name to distinguish them from the base apps.

![](./assets/images/groups.png ':size=300')

`model` (string)
Specify the default model. If not specified, the default model provided by the included helper module (e.g., `gpt-4o-mini` for `OpenAIHelper`) is used.

`temperature` (float)
Specify the default temperature.

`presence_penalty` (float)
Specify the default `presence_penalty`. This is available for OpenAI and Mistral AI models. It is ignored if the model does not support it.

`frequency_penalty` (float)
Specify the default `frequency_penalty`. This is available for OpenAI and Mistral AI models. It is ignored if the model does not support it.

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
Specify the app to run in Monadic mode. For Monadic mode, refer to [Monadic Mode](./monadic-mode.md).

`prompt_suffix` (string)
Specify a text string to be added to every message from the user before sending it to the AI agent. This is useful for adding a reminder to the AI agent about highly important information (often specified in the system prompt) to ensure it is considered when preparing the response.

`file` (bool)
Specify whether to enable the text file upload feature on the app's web settings screen. The contents of the uploaded file are added to the end of the system prompt.

`abc` (bool)
Specify whether to enable the display and playback of musical scores entered in [ABC notation](https://abcnotation.com/) in the AI agent's response. ABC notation is a text-based format for describing musical scores.

`disabled` (bool)
Specify whether to disable the app. Disabled apps are not displayed in the Monadic Chat menu.

`toggle` (bool)
Specify whether to toggle the display of parts of the AI agent's response (meta information, tool usage). Currently, this is only available for apps including the `ClaudeHelper` module.

`models` (array)
Specify a list of available models. If not specified, the list of models provided by the included helper module (e.g., `OpenAIHelper`) is used.

`tools` (array)
Specify a list of available functions. The actual definition of the functions specified here should be written in the recipe file or in another file as instance methods of the `MonadicAgent` module.

`response_format` (hash)
Specify the output format when outputting in JSON format. For details, refer to [OpenAI: Structured outputs](https://platform.openai.com/docs/guides/structured-outputs).

