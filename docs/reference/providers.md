# Providers & Models

Monadic Chat is a multi-provider environment: the same apps and tools run on several AI providers, so a task can be reproduced with different models and the results compared. This page is an overview and index — each linked page is the authoritative reference for its topic.

## Supported Providers

Chat providers, each with its own vendor adapter:

- **OpenAI** — chat, code generation, vision, image generation, speech-to-text, and text-to-speech
- **Anthropic Claude** — chat, code generation, and vision
- **Google Gemini** — chat, vision, image generation, video generation, music generation, speech-to-text, and text-to-speech
- **Mistral AI** — chat, code generation, vision, text-to-speech, and speech-to-text
- **Cohere** — chat, vision, and speech-to-text
- **xAI Grok** — chat, code generation, vision, image generation, video generation, text-to-speech, and speech-to-text
- **DeepSeek** — chat
- **Ollama** — chat with local models on your own machine. Ollama runs natively on the host OS (not in a Docker container); vision and tool-calling support depend on the installed model. See [Using Ollama](/advanced-topics/ollama.md).

Speech-only service:

- **ElevenLabs** — text-to-speech voices and Scribe speech-to-text; not a chat provider

For providers without a native web search capability, web search is provided through the **Tavily** API — see [Comparing Providers](#comparing-providers) below.

## API Key Setup

Each provider requires its own API key. Enter keys in the console's **Settings → API Keys** panel or write them directly to `~/monadic/config/env` — the panel and the file edit the same configuration. The full list of key variables is in the [Configuration Reference](/reference/configuration.md#api-keys), and the panel itself is described in [Console Panel](/basic-usage/console-panel.md).

The apps and UI options for each provider become selectable once its key is configured. You can start with a single key and add more providers later.

## Choosing and Pinning Models

The model an app uses is resolved in this order (highest priority first):

1. Environment variables in `~/monadic/config/env` — per-provider `*_DEFAULT_MODEL` variables such as `OPENAI_DEFAULT_MODEL`
2. `providerDefaults` in `model_spec.js` — the default model set shipped with the app
3. Hardcoded fallbacks in code

See [Configuration Priority](/reference/configuration.md#configuration-priority) and the `*_DEFAULT_MODEL` variable table in [Model Settings](/reference/configuration.md#model-settings).

In the web UI, the Model dropdown shows a curated list by default; the **All** toggle reveals every available model from the provider. See [Model Selection in the UI](/reference/configuration.md#model-selection-in-the-ui).

## Comparing Providers

Several features make cross-provider comparison a first-class workflow:

- **Same app, different providers** — most basic apps are available for multiple providers, so an identical task can be run on each. See [App Availability by Provider](/basic-usage/basic-apps.md#app-availability).
- **Capability differences** — vision, tool calling, and web search support vary by provider. The [Provider Capabilities Overview](/basic-usage/basic-apps.md#provider-capabilities) table also shows which providers use native web search and which use Tavily.
- **Second Opinion** — an app in which one provider's answer is evaluated and critiqued by another provider. See [Chat Apps](/apps/chat-apps.md#second-opinion).
- **Programmatic experiments via MCP** — the Conduit MCP server exposes `monadic_parallel_query` (the same prompt sent to several providers concurrently), `monadic_second_opinion` (cross-provider grading and critique), and `monadic_confidence` (agreement-based confidence assessment). See [MCP Integration](/advanced-topics/mcp-integration.md#capability-surface).

## Local and Offline Options

- **Ollama** runs open-weight models entirely on your own machine — see [Using Ollama](/advanced-topics/ollama.md).
- The **Knowledge Base** (document import and RAG) uses a local Qdrant vector database with local embedding inference; importing and searching documents requires no provider API key. See [Knowledge Base](/apps/knowledge-base.md) and [Vector Database](/docker-integration/vector-database.md).
