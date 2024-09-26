# Language Models

## OpenAI

Monadic Chat uses OpenAI's language models to provide features such as chat, speech recognition, speech synthesis, image generation, and video recognition. Therefore, you must set an OpenAI API key, even if the model you primarily want to use for chat isn't an OpenAI model.  These other features rely on OpenAI services. Once set, the API key is saved in the `~/monadic/data/.env` file in the following format:

```
OPENAI_API_KEY=api_key
```

For apps using OpenAI's language models, refer to the [Basic Apps](/basic-apps.md) section.

## Anthropic

![Anthropic apps icon](/assets/icons/a.png ':size=40')

By setting the Anthropic API key, you can use apps that utilize Claude. Once set, the API key is saved in the `~/monadic/data/.env` file in the following format:

```
ANTHROPIC_API_KEY=api_key
```

Chat with Claude is an application that accesses the Anthropic Claude API to answer questions on a wide range of topics. Code with Claude assists in creating program code. Claude (Code Interpreter) integrates with JupyterLab to actually execute program code.

<details>
<summary>chat_with_claude_app.rb</summary>

[chat_with_claude_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/nightly/docker/services/ruby/apps/talk_to_claude/chat_with_claude_app.rb ':include :type=code')

</details>

<details>
<summary>code_with_claude_app.rb</summary>

[code_with_claude_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/nightly/docker/services/ruby/apps/talk_to_claude/code_with_claude_app.rb ':include :type=code')

</details>

<details>
<summary>jupyter_with_claude_app.rb</summary>

[jupyter_with_claude_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/nightly/docker/services/ruby/apps/talk_to_claude/jupyter_with_claude_app.rb ':include :type=code')

</details>

## Cohere

![Cohere apps icon](/assets/icons/c.png ':size=40')

By setting the Cohere API key, you can use apps that utilize Command R. Once set, the API key is saved in the `~/monadic/data/.env` file in the following format:

```
COHERE_API_KEY=api_key
```

Chat with Command R is an application that accesses the Cohere API to answer questions on a wide range of topics. Code with Command R assists in creating program code.  Jupyter with Command R allows you to use Command R within JupyterLab.


<details>
<summary>chat_with_command_r_app.rb</summary>

[chat_with_command_r_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/nightly/docker/services/ruby/apps/talk_to_cohere/chat_with_command_r_app.rb ':include :type=code')

</details>

<details>
<summary>code_with_command_r_app.rb</summary>

[code_with_command_r_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/nightly/docker/services/ruby/apps/talk_to_cohere/code_with_command_r_app.rb ':include :type=code')

</details>

## Google

![Google apps icon](/assets/icons/google.png ':size=40')

By setting the Google Gemini API key, you can use apps that utilize Gemini. Once set, the API key is saved in the `~/monadic/data/.env` file in the following format:

```
GEMINI_API_KEY=api_key
```

Chat with Gemini is an application that accesses the Google Gemini API to answer questions on a wide range of topics.

<details>
<summary>chat_with_gemini_app.rb</summary>

[chat_with_gemini_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/nightly/docker/services/ruby/apps/talk_to_gemini/chat_with_gemini_app.rb ':include :type=code')

</details>

## Mistral

![Mistral apps icon](/assets/icons/m.png ':size=40')

By setting the Mistral AI API key, you can use apps that utilize Mistral. Once set, the API key is saved in the `~/monadic/data/.env` file in the following format:

```
MISTRAL_API_KEY=api_key
```

Chat with Mistral is an application that accesses the Mistral AI API to answer questions on a wide range of topics. Code with Mistral assists in creating program code.

<details>
<summary>chat_with_mistral_app.rb</summary>

[chat_with_mistral_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/nightly/docker/services/ruby/apps/talk_to_mistral/chat_with_mistral_app.rb ':include :type=code')

</details>

<details>
<summary>code_with_mistral_app.rb</summary>

[code_with_mistral_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/nightly/docker/services/ruby/apps/talk_to_mistral/code_with_mistral_app.rb ':include :type=code')

</details>


## Ollama

![Ollama apps icon](/assets/icons/ollama.png ':size=40')

By introducing additional images and containers, you can use apps that utilize Ollama. [Ollama](https://ollama.com/) is a platform that allows you to use language models in a local environment on Docker. The following models are available:

- Llama
- Phi
- Mistral
- Gemma

For information on how to introduce Ollama in Monadic Chat, refer to [Using Ollama](/ollama).
