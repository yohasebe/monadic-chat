# Language Models

Monadic Chat supports multiple AI model providers. Each provider offers different capabilities and model types. For a complete overview of which apps are compatible with which models, see the [App Availability by Provider](./basic-apps.md#app-availability) section in the Basic Apps documentation.

## Default Models Configuration

You can configure default models for each provider by setting environment variables in the `~/monadic/config/env` file. These default models will be used when no specific model is defined in an app recipe file.

```
# Default models for each provider
OPENAI_DEFAULT_MODEL=gpt-4.1
ANTHROPIC_DEFAULT_MODEL=claude-3-5-sonnet-20241022
COHERE_DEFAULT_MODEL=command-r-plus
GEMINI_DEFAULT_MODEL=gemini-2.0-flash
MISTRAL_DEFAULT_MODEL=mistral-large-latest
GROK_DEFAULT_MODEL=grok-2
PERPLEXITY_DEFAULT_MODEL=sonar
DEEPSEEK_DEFAULT_MODEL=deepseek-chat
```

These environment variables are used for:
1. AI User functionality
2. Chat apps where no model is explicitly specified in the recipe

When a model is explicitly specified in an app recipe file, that specified model takes precedence over the environment variable settings.

## OpenAI Models

Monadic Chat uses OpenAI's language models to provide features such as chat, speech recognition, speech synthesis, image generation, and video recognition. Therefore, it is recommended to set the OpenAI API key. However, if the model you want to use in the chat is not an OpenAI model, it is not necessary to set the OpenAI API key.

Once the OpenAI API key is set, it is saved in the `~/monadic/config/env` file in the following format:

```
OPENAI_API_KEY=api_key
```

For apps using OpenAI's language models, refer to the [Basic Apps](./basic-apps.md) section.

?> For apps using OpenAI's gpt-4.1, gpt-4o, and gpt-4o-mini series models, the "Predicted Outputs" feature is available. By using the string `__DATA__` as a separator in the prompt to distinguish between instructions to the AI agent and data to be corrected or processed by the AI agent, you can speed up the response from the AI and reduce the number of tokens (See OpenAI [Predicted Outputs](https://platform.openai.com/docs/guides/latency-optimization#use-predicted-outputs)).

## Anthropic Models

![Anthropic apps icon](../assets/icons/a.png ':size=40')

By setting the Anthropic API key, you can use apps that utilize Claude. Once set, the API key is saved in the `~/monadic/config/env` file in the following format:

```
ANTHROPIC_API_KEY=api_key
```

?> For apps using Anthropic Claude's Sonnet series models, OpenAI's gpt-4o, gpt-4o-mini, and o1 models, or Google Gemini models, it is possible to upload a PDF directly and have the AI agent recognize its contents. (See [Uploading PDFs](./message-input.md#uploading-pdfs))

## Google Models

![Google apps icon](../assets/icons/google.png ':size=40')

By setting the Google Gemini API key, you can use apps that utilize Gemini. Once set, the API key is saved in the `~/monadic/config/env` file in the following format:

```
GEMINI_API_KEY=api_key
```

## Cohere Models

![Cohere apps icon](../assets/icons/c.png ':size=40')

By setting the Cohere API key, you can use apps that utilize Cohere's models. Once set, the API key is saved in the `~/monadic/config/env` file in the following format:

```
COHERE_API_KEY=api_key
```

## Mistral Models

![Mistral apps icon](../assets/icons/m.png ':size=40')

By setting the Mistral AI API key, you can use apps that utilize Mistral. Once set, the API key is saved in the `~/monadic/config/env` file in the following format:

```
MISTRAL_API_KEY=api_key
```

## xAI Models

![xAI apps icon](../assets/icons/x.png ':size=40')

By setting the xAI API key, you can use apps that utilize xAI. Once set, the API key is saved in the `~/monadic/config/env` file in the following format:

```
XAI_API_KEY=api_key
```

## Perplexity Models

![Perplexity apps icon](../assets/icons/p.png ':size=40')

By setting the Perplexity API key, you can use apps that utilize Perplexity. Once set, the API key is saved in the `~/monadic/config/env` file in the following format:

```
PERPLEXITY_API_KEY=api_key
```

## DeepSeek Models

![DeepSeek apps icon](../assets/icons/d.png ':size=40')

By setting the DeepSeek API key, you can use apps that utilize DeepSeek. Once set, the API key is saved in the `~/monadic/config/env` file in the following format:

```
DEEPSEEK_API_KEY=api_key
```

## Ollama Models

![Ollama apps icon](../assets/icons/ollama.png ':size=40')

By introducing additional images and containers, you can use apps that utilize Ollama. [Ollama](https://ollama.com/) is a platform that allows you to use language models in a local environment on Docker. The following models are available:

- Llama
- Phi
- Mistral
- Gemma

For information on how to introduce Ollama in Monadic Chat, refer to [Using Ollama](./ollama).
