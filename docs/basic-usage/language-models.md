# Language Models

Monadic Chat supports multiple AI model providers. Each provider offers different capabilities and model types. For a complete overview of which apps are compatible with which models, see the [App Availability by Provider](./basic-apps.md#app-availability) section in the Basic Apps documentation.

## Provider Capabilities Overview

| Provider | Vision Support | Tool/Function Calling | Web Search |
|----------|----------------|----------------------|------------|
| OpenAI | ✅ All models¹ | ✅ | ✅ Native² |
| Claude | ✅ Opus/Sonnet³ | ✅ | ✅⁴ |
| Gemini | ✅ All models | ✅ | ✅⁴ |
| Mistral | ✅ Select models⁵ | ✅ | ✅⁴ |
| Cohere | ✅ Vision models⁷ | ✅ | ✅⁴ |
| xAI Grok | ✅ Vision models⁶ | ✅ | ✅ Native |
| Perplexity | ✅ All models | ❌ | ✅ Native |
| DeepSeek | ❌ | ✅ | ✅⁴ |
| Ollama | ❓ Model dependent⁸ | ❓ Model dependent⁸ | ✅⁴ |

¹ Except o1, o1-mini, o3-mini  
² Native web search for gpt-4.1/gpt-4.1-mini via Responses API, others use Tavily when available  
³ Haiku models don't support vision  
⁴ Web search via Tavily API (requires `TAVILY_API_KEY`)  
⁵ Pixtral, mistral-medium-latest, and mistral-small-latest models  
⁶ grok-2-vision models only  
⁷ command-a-vision models only  
⁸ Depends on specific model capabilities

## Default Models Configuration

You can configure default models for each provider by setting configuration variables in the `~/monadic/config/env` file. These default models will be used when no specific model is defined in an app recipe file.

```
# Default models for each provider
OPENAI_DEFAULT_MODEL=gpt-4.1
ANTHROPIC_DEFAULT_MODEL=claude-3-5-sonnet-20241022
COHERE_DEFAULT_MODEL=command-r-plus
GEMINI_DEFAULT_MODEL=gemini-2.5-flash
MISTRAL_DEFAULT_MODEL=mistral-large-latest
GROK_DEFAULT_MODEL=grok-2
PERPLEXITY_DEFAULT_MODEL=sonar
DEEPSEEK_DEFAULT_MODEL=deepseek-chat
OLLAMA_DEFAULT_MODEL=llama3.2:3b
```

These configuration variables are used for:
1. AI User functionality
2. Chat apps where no model is explicitly specified in the recipe

When a model is explicitly specified in an app recipe file, that specified model takes precedence over the configuration variable settings.

## Web Search Configuration

Web search is available in two ways:

### 1. Native Web Search
- **OpenAI**: gpt-4.1 and gpt-4.1-mini use native web search via Responses API (default)
- **Perplexity**: All models have built-in web search
- **xAI Grok**: Native Live Search API support

### 2. Tavily Web Search
- Available for providers that don't have native web search
- Required for: Google Gemini, Mistral AI, Cohere, DeepSeek

### Configuration Options
```
# Tavily API key for web search
TAVILY_API_KEY=your_tavily_api_key

# Model for web search when using reasoning models (o1, o3)
WEBSEARCH_MODEL=gpt-4o-mini
```

### App Defaults
- **Chat apps**: Web search disabled by default for user control (cost and privacy considerations) - can be enabled manually when needed
- **Research Assistant**: Web search enabled by default with specialized search prompts

## Reasoning Models

Reasoning models use advanced computational processes to think through problems step-by-step before responding. Monadic Chat automatically detects these models and adjusts parameters accordingly.

### OpenAI Reasoning Models
- **O1 Series**: o1, o1-mini, o1-preview, o1-pro
- **O3 Series**: o3, o3-pro
- **O4 Series**: o4-mini

These models use `reasoning_effort` parameter ("low", "medium", "high") instead of temperature settings.

### Gemini Thinking Models
- **2.5 Preview Series**: gemini-2.5-flash-preview, gemini-2.5-pro-preview
- Advanced reasoning with adjustable computing budget

### Mistral Reasoning Models
- **Magistral Series**: magistral-medium, magistral-small
- Multilingual reasoning capabilities (French, German, Spanish, Italian, etc.)

### Key Differences from Standard Models
- Use `reasoning_effort` instead of temperature for reasoning models
- Limited function calling support with reasoning models
- Web search requires automatic model switching
- Some models don't support streaming (o1-pro, o3-pro)

!> **Note**: The `reasoning_effort` parameter is primarily for simple text generation tasks. For complex operations involving tool calling, code generation, or document creation (like Concept Visualizer, Code Interpreter, Jupyter Notebook), the parameter is automatically disabled to ensure proper functionality.

## OpenAI Models

Monadic Chat uses OpenAI's language models to provide features such as chat, speech recognition, speech synthesis, image generation, and video recognition. Therefore, it is recommended to set the OpenAI API key. However, if the model you want to use in the chat is not an OpenAI model, it is not necessary to set the OpenAI API key.

### Available Models
- **GPT-4.5 Series**: gpt-4.5-preview, gpt-4.5-preview-2025-02-27
- **GPT-4.1 Series**: gpt-4.1, gpt-4.1-mini, gpt-4.1-nano (1M+ context window)
- **GPT-4o Series**: gpt-4o, gpt-4o-mini, gpt-4o-audio-preview
- **Reasoning Models**: o1, o1-mini, o1-pro, o3, o3-mini, o3-pro, o4-mini

Once the OpenAI API key is set, it is saved in the `~/monadic/config/env` file in the following format:

```
OPENAI_API_KEY=api_key
```

For apps using OpenAI's language models, refer to the [Basic Apps](./basic-apps.md) section.

?> For apps using OpenAI's gpt-4.1, gpt-4o, and gpt-4o-mini series models, the "Predicted Outputs" feature is available. By using the string `__DATA__` as a separator in the prompt to distinguish between instructions to the AI agent and data to be corrected or processed by the AI agent, you can speed up the response from the AI and reduce the number of tokens (See OpenAI [Predicted Outputs](https://platform.openai.com/docs/guides/latency-optimization#use-predicted-outputs)).

## Anthropic Models

![Anthropic apps icon](../assets/icons/a.png ':size=40')

By setting the Anthropic API key, you can use apps that utilize Claude.

### Available Models
- **Claude 4.0 Series**: claude-opus-4, claude-sonnet-4 (latest generation with reasoning)
- **Claude 3.5 Series**: claude-3-5-sonnet-20241022, claude-3-5-haiku-20250122
- **Claude 3 Series**: claude-3-opus, claude-3-sonnet, claude-3-haiku

Once set, the API key is saved in the `~/monadic/config/env` file in the following format:

```
ANTHROPIC_API_KEY=api_key
```

?> For apps using Anthropic Claude's Sonnet series models, OpenAI's gpt-4o, gpt-4o-mini, and o1 models, or Google Gemini models, it is possible to upload a PDF directly and have the AI agent recognize its contents. (See [Uploading PDFs](./message-input.md#uploading-pdfs))

## Google Models

![Google apps icon](../assets/icons/google.png ':size=40')

By setting the Google Gemini API key, you can use apps that utilize Gemini.

### Available Models
- **Gemini 2.5 Series**: 
  - gemini-2.5-flash, gemini-2.5-pro (with adjustable reasoning dial)
  - gemini-2.5-flash-preview-05-20, gemini-2.5-pro-exp-03-25 (experimental)
  - Deep Think mode available for enhanced reasoning
- **Gemini 2.0 Series**: 
  - gemini-2.0-flash, gemini-2.0-flash-thinking-exp (thinking/reasoning models)
  - 1M token context window
- **Imagen 3**: imagen-3.0-generate-002 (for image generation)

Once set, the API key is saved in the `~/monadic/config/env` file in the following format:

```
GEMINI_API_KEY=api_key
```

## Cohere Models

![Cohere apps icon](../assets/icons/c.png ':size=40')

By setting the Cohere API key, you can use apps that utilize Cohere's models.

### Available Models
- **Command A Series**: command-a-03-2025 (latest), command-a-vision-07-2025 (vision capability)
- **Command R Series**: command-r-plus-08-2024, command-r-08-2024
- **Command Series**: command, command-light

Once set, the API key is saved in the `~/monadic/config/env` file in the following format:

```
COHERE_API_KEY=api_key
```

## Mistral Models

![Mistral apps icon](../assets/icons/m.png ':size=40')

By setting the Mistral AI API key, you can use apps that utilize Mistral.

### Available Models
- **Magistral Series**: magistral-medium, magistral-small (reasoning models)
  - Multilingual reasoning in European languages
  - 1,000 tokens/second performance
- **Large Models**: mistral-large-latest, mistral-medium-latest (vision), mistral-small-latest (vision)
- **Pixtral Series**: pixtral-large-latest, pixtral-large-2411, pixtral-12b-latest (all vision models)
- **Small Models**: mistral-saba-latest, ministral-3b-latest, ministral-8b-latest
- **Open Models**: open-mistral-nemo, codestral (code generation)

Once set, the API key is saved in the `~/monadic/config/env` file in the following format:

```
MISTRAL_API_KEY=api_key
```

## xAI Models

![xAI apps icon](../assets/icons/x.png ':size=40')

By setting the xAI API key, you can use apps that utilize Grok.

### Available Models
- **Grok 3 Series**: grok-3, grok-3-mini, grok-3-pro (reasoning)
- **Grok 2 Series**: grok-2, grok-2-mini, grok-2-vision-1212 (vision)
- **Grok Beta**: grok-beta

Once set, the API key is saved in the `~/monadic/config/env` file in the following format:

```
XAI_API_KEY=api_key
```

## Perplexity Models

![Perplexity apps icon](../assets/icons/p.png ':size=40')

By setting the Perplexity API key, you can use apps that utilize Perplexity.

### Available Models
- **R1 Series**: r1-1776 (reasoning model, based on DeepSeek-R1)
  - 671B parameters, 160K context window
  - Post-trained for unbiased responses
  - Recommended temperature: 0.5-0.7
- **Sonar Series**: sonar, sonar-pro, sonar-reasoning, sonar-reasoning-pro, sonar-deep-research
  - All include built-in web search capabilities
  - Optimized for different use cases from quick searches to deep research

Once set, the API key is saved in the `~/monadic/config/env` file in the following format:

```
PERPLEXITY_API_KEY=api_key
```

## DeepSeek Models

![DeepSeek apps icon](../assets/icons/d.png ':size=40')

By setting the DeepSeek API key, you can use apps that utilize DeepSeek. DeepSeek provides powerful AI models with function calling support. Available models include:

- deepseek-chat (default)
- deepseek-reasoner

?> **Note:** DeepSeek's Code Interpreter app works best with simpler, direct prompts due to the model's sensitivity to prompt complexity.

```
DEEPSEEK_API_KEY=api_key
```

## Ollama Models

![Ollama apps icon](../assets/icons/ollama.png ':size=40')

Ollama is now built into Monadic Chat! [Ollama](https://ollama.com/) is a platform that allows you to run language models locally. No API key is required since it runs on your own machine.

### Popular Models

- **Llama 3.2** (1B, 3B) - Latest Llama model, excellent balance of performance and size
- **Llama 3.1** (8B, 70B) - State-of-the-art model from Meta
- **Gemma 2** (2B, 9B, 27B) - Google's lightweight models
- **Qwen 2.5** (0.5B-72B) - Alibaba's models with various sizes
- **Mistral** (7B) - Fast and capable model
- **Phi 3** (3.8B, 14B) - Microsoft's efficient models

### Setting Up Ollama

1. Build the Ollama container: Actions → Build Ollama Container
2. Start Monadic Chat: Actions → Start
3. The Chat app with Ollama support will appear in the Ollama group

!> **Important:** Ollama models are downloaded during the container build process, not at runtime. The build process will download the model specified in `OLLAMA_DEFAULT_MODEL` or use a custom setup script.

### Default Model Configuration

You can set a default Ollama model in `~/monadic/config/env`:

```
OLLAMA_DEFAULT_MODEL=llama3.2:3b
```

### Custom Model Setup

For custom model installation, create `~/monadic/config/olsetup.sh`:
```bash
#!/bin/bash
ollama pull llama3.2:3b
ollama pull mistral:7b
ollama pull gemma2:9b
```

When `olsetup.sh` exists, only the models in the script will be downloaded (the default model won't be pulled).

For detailed setup instructions and model management, refer to [Using Ollama](../advanced-topics/ollama.md).

## Model Auto-Switching :id=model-auto-switching

Monadic Chat automatically switches models in certain situations to ensure optimal functionality. When this happens, you'll see an "Information" notification in the conversation.

### When Models Are Switched

#### OpenAI
- **Web Search**: Reasoning models (o1) don't support web search and automatically switch to gpt-4.1-mini as fallback
- **Image Processing**: Models without vision capabilities automatically switch to gpt-4.1
- **API Limitations**: Some models (like o3-pro) may be automatically switched by OpenAI to compatible versions

#### xAI Grok
- **Image Processing**: All models automatically switch to grok-2-vision-1212 when images are included

### Notifications

When a model switch occurs, you'll see a blue information card in the conversation showing:
- The originally requested model
- The actual model being used
- The reason for the switch

This ensures transparency about which model is processing your requests.
