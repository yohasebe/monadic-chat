# Recipe File Examples

## Simple Apps

For the way to develop simple apps, refer to [Adding Simple Apps](/ja/develop_apps#adding-simple-apps).

<details open=true>
<summary>Recipe Example (math_tutor.rb)</summary>

![](https://raw.githubusercontent.com/yohasebe/monadic-chat/main/docker/services/ruby/apps/math_tutor/math_tutor_app.rb ':include :type=code')

</details>

## Apps with Function Definitions

For the way to use functions and tools in an app, refer to [Function and Tool Calling](#function-and-tool-calling).

<details open=true>
<summary>Recipe Example (wikipedia.rb)</summary>

![](https://raw.githubusercontent.com/yohasebe/monadic-chat/main/docker/services/ruby/apps/wikipedia/wikipedia_app.rb ':include :type=code')

</details>

<details open=true>
<summary>Helper Example (wikipedia_helper.rb)</summary>

<!-- ![](https://raw.githubusercontent.com/yohasebe/monadic-chat/main/docker/services/ruby/lib/monadic/helpers/wikipedia_helper.rb ':include :type=code') -->

</details>

## Apps with Output Format Specification

Monadic Chat has a special mode (called `monadic` mode) for outputting in JSON format. For details, refer to [Monadic Mode](/ja/monadic-mode).

For some OpenAI models (such as `gpt-4o`), you can specify `response_format` to ensure that the response is in JSON format. For the specification method, refer to [OpenAI: Structured outputs](https://platform.openai.com/docs/guides/structured-outputs).

<details open=true>
<summary>Recipe Example (novel_writer_app.rb)</summary>

![](https://raw.githubusercontent.com/yohasebe/monadic-chat/main/docker/services/ruby/apps/novel_writer/novel_writer_app.rb ':include :type=code')

</details>

## Apps Using a Custom Container

Refer to the section on [Adding Docker Containers](adding-containers.md).
