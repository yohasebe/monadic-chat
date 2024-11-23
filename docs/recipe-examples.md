# Recipe File Examples

?> The program examples shown on this page directly reference the code in the [monadic-chat](https//github.com/yohasebe/monadic-chat) repository (`main` branch) on GitHub. If you find any issues, please submit a pull request.

## Simple Apps

For how to develop simple apps, refer to [Adding Simple Apps](/develop_apps.md#how-to-add-a-simple-app).

<details open>
<summary>Recipe Example (math_tutor_app.rb)</summary>

![](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/math_tutor/math_tutor_app.rb ':include :type=code')

</details>

## Apps with Function Definitions

For how to use functions and tools in an app, refer to [Calling Functions in the App](/develop_apps.md#calling-functions-in-the-app).

<details open>
<summary>Recipe Example (wikipedia_app.rb)</summary>

![](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/wikipedia/wikipedia_app.rb ':include :type=code')

</details>

<details open>
<summary>Helper Example (wikipedia_helper.rb)</summary>

![](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/lib/monadic/helpers/wikipedia_helper.rb ':include :type=code')

</details>

## Apps with Output Format Specification

Monadic Chat has a special mode (called `monadic` mode) for outputting in JSON format. For details, refer to [Monadic Mode](/monadic-mode.md).

For some OpenAI models (such as `gpt-4o`), you can specify `response_format` to ensure that the response is in JSON format. For the specification method, refer to [OpenAI: Structured outputs](https://platform.openai.com/docs/guides/structured-outputs).

<details open>
<summary>Recipe Example (novel_writer_app.rb)</summary>

![](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/novel_writer/novel_writer_app.rb ':include :type=code')

</details>

## AI Agents Using LLMs within Apps

This section provides examples of apps where the AI agent accesses the OpenAI language model within the functions and tools it uses. Refer to [Using LLM in Functions and Tools](/develop_apps.md#using-llm-in-functions-and-tools).

<details open>
<summary>Recipe Example (second_opinion_app.rb)</summary>

![](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/second_opinion/second_opinion_app.rb ':include :type=code')

</details>

<details open>
<summary>Helper Example (second_opinion_agent.rb)</summary>

![](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/lib/monadic/helpers/agents/second_opinion_agent.rb ':include :type=code')

</details>

## Apps Using a Custom Container

Refer to the section on [Adding Docker Containers](/adding-containers.md) for information on how to create and use custom containers with your apps. This allows you to extend Monadic Chat's functionality by adding new services and tools.
