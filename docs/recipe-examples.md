# Recipe File Examples

## Simple Apps

<details>
<summary>Recipe File (math_tutor.rb)</summary>

![chat_app.rb ](https://raw.githubusercontent.com/yohasebe/monadic-chat/main/docker/services/ruby/apps/math_tutor/math_tutor_app.rb ':include :type=code')

</details>

## Apps with Function Definitions

<details>
<summary>Recipe File (wikipedia.rb)</summary>

![chat_app.rb ](https://raw.githubusercontent.com/yohasebe/monadic-chat/main/docker/services/ruby/apps/wikipedia/wikipedia_app.rb ':include :type=code')

</details>

<details>
<summary>Function Definition File (wikipedia_agent.rb)</summary>

![chat_app.rb ](https://raw.githubusercontent.com/yohasebe/monadic-chat/main/docker/services/ruby/lib/monadic/agents/wikipedia_agent.rb ':include :type=code')

</details>

To use functions within an app, follow these steps:

- Explain how to use the functions in the system prompt.
- Add a `tools` key to the `@settings` hash and specify the definitions of the functions to be used in a list. The method of defining functions varies by language model vendor. For apps including the OpenAIHelper module, refer to [OpenAI: Function calling](https://platform.openai.com/docs/guides/function-calling).
- Define the functions specified in the `tools` key in Ruby. Functions can be written within the class in the recipe file or in another file as instance methods of the `MonadicAgent` module.

## Apps with Output Format Specification

Monadic Chat has a special mode (called `monadic` mode) for outputting in JSON format. For details, refer to [Monadic Mode](/ja/monadic-mode).

<details>
<summary>Recipe File (novel_writer_app.rb)</summary>

![chat_app.rb ](https://raw.githubusercontent.com/yohasebe/monadic-chat/main/docker/services/ruby/apps/novel_writer/novel_writer_app.rb ':include :type=code')

</details>

To specify the output format in an app that includes `OpenAIHelper`, follow these steps:

- Clearly state in the system prompt that the output should be in JSON format.
- Add a `monadic` key to the `@settings` hash and set its value to `true`.
- Add a `response_format` key to the `@settings` hash and specify the JSON format to be used for output. For the specification method, refer to [OpenAI: Structured outputs](https://platform.openai.com/docs/guides/structured-outputs).

## Apps Using a Custom Container

Refer to the section on [Adding Docker Containers](adding-containers.md).
