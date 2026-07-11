# Chat & Assistant Apps

General-purpose conversation and assistant apps: standard and metadata-enriched chat, voice conversation, and assistants for encyclopedic lookup, math, second opinions, research, and Monadic Chat itself.

## Chat

![Chat app icon](../assets/icons/chat.png ':size=40')

Start a standard conversation with the AI, which will respond to your text with appropriate emojis. For complex questions, web search is available for models that support tool/function calling — whether a provider uses its built-in search or the Tavily API (requires a `TAVILY_API_KEY`) is shown in the [Provider Capabilities table](../basic-usage/basic-apps.md#provider-capabilities).

You can also use the `From URL` feature to extract content from any website using Selenium-based web scraping, regardless of the provider.

Availability for this app follows the [App Availability by Provider](../basic-usage/basic-apps.md#app-availability) table.


## Chat Plus

![Chat app icon](../assets/icons/chat-plus.png ':size=40')

Engage in a "monadic" chat that reveals the AI's thought process. As the AI responds, it also provides structured metadata to add context to the conversation:

- **Reasoning**: The thought process behind the response.
- **Topics**: A list of topics discussed so far.
- **People**: A list of people mentioned in the conversation.
- **Notes**: Key points to remember during the conversation.


## Voice Chat :id=voice-chat

![Voice Chat app icon](../assets/icons/voice-chat.png ':size=40')

Chat with the AI using your voice. This app uses your provider's speech recognition API for voice input, and the text-to-speech provider selected in the Speech Settings panel for voice output. The browser's built-in Web Speech API is the default output option and requires no API key; provider TTS engines (OpenAI, ElevenLabs, Gemini, Mistral, xAI Grok) can be selected instead. The initial prompt is the same as the standard Chat app, and you can use different AI models for responses.

While you speak, a visual waveform is displayed; after you stop, a confidence score (p-value) for the speech recognition result is shown — see [Speech Input](../basic-usage/message-input.md#speech-input) for details.

Voice Chat supports the same providers indicated in the [availability table](../basic-usage/basic-apps.md#app-availability). You can freely mix any chat provider with any available TTS provider — for example, using Claude for the conversation while xAI Grok handles the voice. For speech input/output settings, see [Speech Settings Panel](../basic-usage/web-interface.md#speech-settings-panel).

**Expressive Speech**: When you enable Auto Speech and pick a compatible TTS provider, a small ✨ **Expressive Speech** badge appears under the Text-to-Speech Provider dropdown, and the assistant's replies gain expressive audio cues (pauses, laughter, voice directives) that never surface in the chat transcript. The mechanism is chosen automatically per provider — see [Speech Settings Panel](../basic-usage/web-interface.md#speech-settings-panel) for how each provider implements it.


## Wikipedia

![Wikipedia app icon](../assets/icons/wikipedia.png ':size=40')

Ask questions about recent events or topics outside the AI's knowledge cutoff. This app functions like the standard Chat but automatically searches Wikipedia for answers when needed. If your query is in a language other than English, the app searches the English Wikipedia and translates the results back to your language.


## Math Tutor

![Math Tutor app icon](../assets/icons/math-tutor.png ':size=40')

Explore math-related questions and answers. The app uses [KaTeX](https://katex.org/) to render beautiful mathematical notation in its responses.

!> **Caution:** LLMs are known to struggle with calculations requiring multiple steps or complex logic and can produce incorrect results.  Double-check any mathematical output from this app, and if accuracy is critical, it is recommended to use the Code Interpreter app to perform the calculations.


## Second Opinion

![Second Opinion app icon](../assets/icons/second-opinion.png ':size=40')

Get a second opinion on any answer to ensure accuracy and gain diverse perspectives. First, ask your question to get an initial response. Then, ask the app to "double-check this answer," and it will consult a different AI provider to review and comment on the first response.

Second Opinion is available wherever the [availability table](../basic-usage/basic-apps.md#app-availability) lists support.


## Research Assistant

![Research Assistant app icon](../assets/icons/research-assistant.png ':size=40')

Accelerate your academic and scientific research with an intelligent assistant. This app uses powerful web search capabilities to retrieve and analyze information from online sources. Use it to find current information, verify facts, and research topics comprehensively, receiving reliable insights, summaries, and explanations to advance your work.

Research Assistant availability matches the [availability table](../basic-usage/basic-apps.md#app-availability). Whether web search uses a provider's native search or the Tavily API (requires `TAVILY_API_KEY`) is shown in the [Provider Capabilities table](../basic-usage/basic-apps.md#provider-capabilities); Selenium-based URL content extraction is available for all providers.

> **Note**: Gemini Research Assistant uses an internal web search agent (`gemini_web_search`) instead of native Google Search grounding. This enables web search to work alongside file operations and progress tracking, working around certain Gemini API limitations.

For more details, see the Chat app description above or [Reading Text from URLs](../basic-usage/message-input.md#reading-text-from-urls).


## Monadic Chat Help

![Help app icon](../assets/icons/help.png ':size=40')

Get help with Monadic Chat from this AI-powered assistant. It provides contextual assistance based on the project's official documentation, answering questions about features, usage, and troubleshooting in any language.

The help system uses a pre-built knowledge base created from the English documentation. When you ask a question, it searches this knowledge base to provide an accurate, relevant answer. For more details on the architecture, see the [Help System](../advanced-topics/help-system.md) documentation.
