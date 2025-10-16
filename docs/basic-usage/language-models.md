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
| xAI Grok | ✅ Select models⁶ | ✅ | ✅ Native |
| Perplexity | ✅ All models | ❌ | ✅ Native |
| DeepSeek | ❌ | ✅ | ✅⁴ |
| Ollama | ❓ Model dependent⁸ | ❓ Model dependent⁸ | ✅⁴ |

¹ Vision availability varies by OpenAI model family; refer to <https://platform.openai.com/docs/models> for specifics.  
² Native web search for providers with built-in support; others can use Tavily when configured.  
³ Anthropic indicates vision support per model at <https://docs.anthropic.com/claude/docs/models-overview>.  
⁴ Web search via Tavily API (requires `TAVILY_API_KEY`).  
⁵ Vision-capable models for Mistral are documented at <https://docs.mistral.ai/>.  
⁶ xAI publishes Grok model details (including vision support) at <https://docs.x.ai/docs/models>.  
⁷ Cohere outlines vision-enabled variants at <https://docs.cohere.com/docs/models>.  
⁸ Depends on specific model capabilities

## Default Models Configuration

You can configure default models for each provider by setting configuration variables in the `~/monadic/config/env` file. These default models will be used when no specific model is defined in an app recipe file.

```
# Default models for each provider
OPENAI_DEFAULT_MODEL=gpt-4.1
ANTHROPIC_DEFAULT_MODEL=claude-sonnet-4-20250514
COHERE_DEFAULT_MODEL=command-a-03-2025
GEMINI_DEFAULT_MODEL=gemini-2.5-flash
MISTRAL_DEFAULT_MODEL=mistral-large-latest
GROK_DEFAULT_MODEL=grok-4-fast-reasoning
PERPLEXITY_DEFAULT_MODEL=sonar-reasoning-pro
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
WEBSEARCH_MODEL=gpt-4.1-mini
```

### App Defaults
- **Chat apps**: Web search disabled by default - can be enabled manually when needed
- **Research Assistant**: Web search enabled by default with specialized search prompts

## Reasoning and Thinking Features

Monadic Chat provides advanced reasoning and thinking capabilities across multiple AI providers. The Web UI automatically adapts to show appropriate controls based on the selected provider and model.

### Unified Interface

The reasoning/thinking selector in the Web UI intelligently adapts to each provider's terminology and options:

| Provider | Parameter Name | Available Options | Description |
|----------|---------------|-------------------|-------------|
| OpenAI | Reasoning Effort | minimal, low, medium, high | Controls computational depth for O1/O3/O4 models |
| Anthropic | Thinking Level | minimal, low, medium, high | Maps to thinking budget (1024-25000 tokens) for Claude 4 models |
| Google | Thinking Mode | minimal, low, medium, high | Adjusts reasoning dial for Gemini 2.5 preview models |
| xAI | Reasoning Effort | low, medium, high | Controls Grok's reasoning depth (no minimal option) |
| DeepSeek | Reasoning Mode | Off (minimal), On (medium) | Enables/disables step-by-step reasoning |
| Perplexity | Research Depth | minimal, low, medium, high | Controls web search and analysis depth for Sonar models |

### Provider-Specific Reasoning Models

#### OpenAI Reasoning Models
See <https://platform.openai.com/docs/guides/reasoning> for the latest reasoning-capable models. When a selected model supports reasoning, Monadic exposes the appropriate controls automatically.

#### Anthropic Thinking Models
Refer to <https://docs.anthropic.com/claude/docs/thinking-with-claude> for details on Claude thinking budgets. Monadic maps the provider's settings to the UI automatically.

#### Google Thinking Models
Consult <https://ai.google.dev/gemini-api/docs/reasoning> for Gemini reasoning capabilities. Supported models expose the reasoning selector in Monadic.

#### xAI Grok Reasoning
Consult xAI's guidance for Grok reasoning capabilities. When a selected Grok model supports reasoning, Monadic exposes the `reasoning_effort` selector (low/medium/high) automatically.

#### DeepSeek Reasoning
DeepSeek's official guidance covers the reasoning features available in their models. Monadic toggles reasoning mode automatically when the chosen model supports it.

#### Perplexity Research Models
Perplexity documents research depth options for Sonar at <https://docs.perplexity.ai/docs/model-cards>. Monadic maps those options to the unified selector.

#### Mistral Reasoning Models
Review Mistral's reasoning lineup in their documentation; Monadic surfaces the appropriate controls for supported models.

### Automatic Feature Detection

The Web UI automatically:
- Detects whether the selected model supports reasoning/thinking features
- Shows or hides the reasoning selector accordingly
- Adapts the label and options to match the provider's terminology
- Disables the selector for models that don't support these features

### Important Notes

!> **Note**: Reasoning/thinking parameters are primarily for simple text generation tasks. For complex operations involving tool calling, code generation, or document creation (like Concept Visualizer, Code Interpreter, Jupyter Notebook), these parameters are automatically disabled to ensure proper functionality.

?> **Tip**: When switching between providers, the reasoning selector will automatically update to show the appropriate options for that provider's models.

## OpenAI Models

Monadic Chat uses OpenAI's language models to provide features such as chat, speech recognition, speech synthesis, image generation, and video recognition. Therefore, it is recommended to set the OpenAI API key. However, if the model you want to use in the chat is not an OpenAI model, it is not necessary to set the OpenAI API key.

### Model Selection Guidance
OpenAI frequently updates its catalogue. Refer to <https://platform.openai.com/docs/models> for the latest lineup and configure `OPENAI_DEFAULT_MODEL` as needed (Monadic defaults to `gpt-4.1`).

Once the OpenAI API key is set, it is saved in the `~/monadic/config/env` file in the following format:

```
OPENAI_API_KEY=api_key
```

For apps using OpenAI's language models, refer to the [Basic Apps](./basic-apps.md) section.

?> For apps using OpenAI's gpt-4.1 family (gpt-4.1, gpt-4.1-mini) or gpt-4o-series models, the "Predicted Outputs" feature is available. By using the string `__DATA__` as a separator in the prompt to distinguish between instructions to the AI agent and data to be corrected or processed by the AI agent, you can speed up the response from the AI and reduce the number of tokens (see OpenAI [Predicted Outputs](https://platform.openai.com/docs/guides/latency-optimization#use-predicted-outputs)).

## Anthropic Models

![Anthropic apps icon](../assets/icons/a.png ':size=40')

By setting the Anthropic API key, you can use apps that utilize Claude.

### Model Selection Guidance
See <https://docs.anthropic.com/claude/docs/models-overview> for Anthropic's current models and set `ANTHROPIC_DEFAULT_MODEL` accordingly.

Once set, the API key is saved in the `~/monadic/config/env` file in the following format:

```
ANTHROPIC_API_KEY=api_key
```

?> For apps using Anthropic Claude's Sonnet series models, OpenAI's gpt-4.1 or gpt-4o series (including o1), or Google Gemini models, it is possible to upload a PDF directly and have the AI agent recognize its contents. (See [Uploading PDFs](./message-input.md#uploading-pdfs))

## Google Models

![Google apps icon](../assets/icons/google.png ':size=40')

By setting the Google Gemini API key, you can use apps that utilize Gemini.

### Model Selection Guidance
Google maintains the authoritative Gemini model list at <https://ai.google.dev/gemini-api/docs/models>. Choose the appropriate model via `GEMINI_DEFAULT_MODEL`.

Once set, the API key is saved in the `~/monadic/config/env` file in the following format:

```
GEMINI_API_KEY=api_key
```

## Cohere Models

![Cohere apps icon](../assets/icons/c.png ':size=40')

By setting the Cohere API key, you can use apps that utilize Cohere's models.

### Model Selection Guidance
Monadic Chat does not catalogue Cohere models. Review Cohere's official model list (<https://docs.cohere.com/docs/models>) and set the preferred `COHERE_DEFAULT_MODEL` (default: `command-a-03-2025`).

Once set, the API key is saved in the `~/monadic/config/env` file in the following format:

```
COHERE_API_KEY=api_key
```

## Mistral Models

![Mistral apps icon](../assets/icons/m.png ':size=40')

By setting the Mistral AI API key, you can use apps that utilize Mistral.

### Model Selection Guidance
For the latest Mistral portfolio, refer to <https://docs.mistral.ai/>. Adjust `MISTRAL_DEFAULT_MODEL` as needed (Monadic defaults to `mistral-large-latest`).

Once set, the API key is saved in the `~/monadic/config/env` file in the following format:

```
MISTRAL_API_KEY=api_key
```

## xAI Models

![xAI apps icon](../assets/icons/x.png ':size=40')

By setting the xAI API key, you can use apps that utilize Grok.

### Model Selection Guidance
xAI publishes the authoritative Grok model matrix at <https://docs.x.ai/docs/models>. Configure `GROK_DEFAULT_MODEL` accordingly (default: `grok-4-fast-reasoning`).

Once set, the API key is saved in the `~/monadic/config/env` file in the following format:

```
XAI_API_KEY=api_key
```

## Perplexity Models

![Perplexity apps icon](../assets/icons/p.png ':size=40')

By setting the Perplexity API key, you can use apps that utilize Perplexity.

### Model Selection Guidance
Perplexity documents supported Sonar models at <https://docs.perplexity.ai/docs/model-cards>. Set `PERPLEXITY_DEFAULT_MODEL` (default: `sonar-reasoning-pro`) to match your use case.

Once set, the API key is saved in the `~/monadic/config/env` file in the following format:

```
PERPLEXITY_API_KEY=api_key
```

## DeepSeek Models

![DeepSeek apps icon](../assets/icons/d.png ':size=40')

By setting the DeepSeek API key, you can use apps that utilize DeepSeek. Refer to the provider's documentation for the latest model list; Monadic defaults to `deepseek-chat`.

```
DEEPSEEK_API_KEY=api_key
```

## Ollama Models

![Ollama apps icon](../assets/icons/ollama.png ':size=40')

Ollama is now built into Monadic Chat! [Ollama](https://ollama.com/) is a platform that allows you to run language models locally. No API key is required since it runs on your own machine.

### Discovering Models

Browse the Ollama library at <https://ollama.com/library> for the latest set of downloadable models. Specify your preferred default via `OLLAMA_DEFAULT_MODEL`.

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
