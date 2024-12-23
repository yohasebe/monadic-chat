# Language Models

## OpenAI Models

Monadic Chat uses OpenAI's language models to provide features such as chat, speech recognition, speech synthesis, image generation, and video recognition. Therefore, it is recommended to set the OpenAI API key. However, if the model you want to use in the chat is not an OpenAI model, it is not necessary to set the OpenAI API key.

Once the OpenAI API key is set, it is saved in the `~/monadic/data/.env` file in the following format:

```
OPENAI_API_KEY=api_key
```

For apps using OpenAI's language models, refer to the [Basic Apps](./basic-apps.md) section.

?> For apps using OpenAI's GPT-4o series and GPT-4o-mini series models, the "Predicted Outputs" feature is available. By using the string `__DATA__` as a separator in the prompt to distinguish between instructions to the AI agent and data to be corrected or processed by the AI agent, you can speed up the response from the AI and reduce the number of tokens (See OpenAI [Predicted Outputs](https://platform.openai.com/docs/guides/latency-optimization#use-predicted-outputs)).

## Anthropic Models

![Anthropic apps icon](./assets/icons/a.png ':size=40')

By setting the Anthropic API key, you can use apps that utilize Claude. Once set, the API key is saved in the `~/monadic/data/.env` file in the following format:

```
ANTHROPIC_API_KEY=api_key
```

?> For apps using Anthropic Claude's Sonnet series models, it is possible to upload a PDF directly and have the AI agent recognize its contents. (See [PDF recognition](./message-input?id=uploading-pdfs))

Once the Anthropic API key is set, you can use the following apps. For information on the features of each app, refer to the [Basic Apps](./basic-apps.md) section.

<details>
<summary>chat_claude_app.rb</summary>

[chat_claude_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/talk_to_claude/chat_claude_app.rb ':include :type=code')

</details>

<details>
<summary>code_interpreter_claude_app.rb</summary>

[code_interpreter_claude_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/talk_to_claude/code_interpreter_claude_app.rb ':include :type=code')

</details>

<details>
<summary>coding_assistant_claude_app.rb</summary>

[code_interpreter_claude_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/talk_to_claude/coding_assistant_claude_app.rb ':include :type=code')

</details>

<details>

<summary>jupyter_notebook_claude_app.rb</summary>

![jupyter_notebook_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/talk_to_claude/jupyter_notebook_claude_app.rb ':include :type=code')

</details>

## Google Models

![Google apps icon](./assets/icons/google.png ':size=40')

By setting the Google Gemini API key, you can use apps that utilize Gemini. Once set, the API key is saved in the `~/monadic/data/.env` file in the following format:

```
GEMINI_API_KEY=api_key
```

Once the Google Gemini API key is set, you can use the following apps. For information on the features of each app, refer to the [Basic Apps](./basic-apps.md) section.

<details>
<summary>chat_gemini_app.rb</summary>

[chat_gemini_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/talk_to_gemini/chat_gemini_app.rb ':include :type=code')

</details>

<details>
<summary>coding_assistant_gemini_app.rb</summary>

![chat_gemini_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/talk_to_gemini/coding_assistant_gemini_app.rb ':include :type=code')

</details>

## Cohere Models

![Cohere apps icon](./assets/icons/c.png ':size=40')

By setting the Cohere API key, you can use apps that utilize Command R. Once set, the API key is saved in the `~/monadic/data/.env` file in the following format:

```
COHERE_API_KEY=api_key
```

Once the Cohere API key is set, you can use the following apps. For information on the features of each app, refer to the [Basic Apps](./basic-apps.md) section.

<details>
<summary>chat_command_r_app.rb</summary>

[chat_command_r_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/talk_to_cohere/chat_command_r_app.rb ':include :type=code')

</details>

<details>
<summary>code_interpreter_command_r_app.rb</summary>

[code_interpreter_command_r_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/talk_to_cohere/code_interpreter_command_r_app.rb ':include :type=code')

</details>

## Mistral Models

![Mistral apps icon](./assets/icons/m.png ':size=40')

By setting the Mistral AI API key, you can use apps that utilize Mistral. Once set, the API key is saved in the `~/monadic/data/.env` file in the following format:

```
MISTRAL_API_KEY=api_key
```

Once the Mistral API key is set, you can use the following apps. For information on the features of each app, refer to the [Basic Apps](./basic-apps.md) section.

<details>
<summary>chat_mistral_app.rb</summary>

[chat_mistral_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/talk_to_mistral/chat_mistral_app.rb ':include :type=code')

</details>

<details>
<summary>coding_assistant_mistral_app.rb</summary>

[coding_assistant_mistral_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/talk_to_mistral/coding_assistant_mistral_app.rb ':include :type=code')

</details>

## Ollama Models

![Ollama apps icon](./assets/icons/ollama.png ':size=40')

By introducing additional images and containers, you can use apps that utilize Ollama. [Ollama](https://ollama.com/) is a platform that allows you to use language models in a local environment on Docker. The following models are available:

- Llama
- Phi
- Mistral
- Gemma

For information on how to introduce Ollama in Monadic Chat, refer to [Using Ollama](./ollama).
