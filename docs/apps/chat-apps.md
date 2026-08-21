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

For a continuous, hands-free conversation that streams audio directly to the provider's realtime speech-to-speech API, see [Live Conversation](#live-conversation) below.


## Live Conversation :id=live-conversation

Talk with the AI in a continuous, hands-free voice conversation. Unlike [Voice Chat](#voice-chat) — which runs speech recognition, the language model, and speech synthesis as three separate steps — Live Conversation streams audio directly to the provider's realtime speech-to-speech API, so responses start sooner and the exchange flows without button presses.

Three variants are available, one per provider: OpenAI, xAI Grok, and Google Gemini. A variant can be selected only when its provider's API key is configured.

**How it works**: Click `Start` to open the conversation, then speak naturally — the end of each utterance is detected automatically (voice activity detection) and the turn proceeds on its own. Click `End` to close the session. There is no text input in this app. Headphones are recommended: with speakers, the assistant's voice feeds back into the microphone and can trigger unintended turns.

**Voice and speed**: Pick the assistant's voice from the selector in the app's control row (the Speech Settings panel's TTS settings do not apply here). The number of available voices is 10 for OpenAI (default: alloy), 26 for xAI (default: eve), and 30 for Gemini (default: Kore). A playback speed slider (0.25–1.5) is available for OpenAI only. Your voice choice is remembered per provider.

**Turn detection** (OpenAI variant only): Choose how the end of your utterance is decided. The default judges by silence; the "by meaning" modes (patient / balanced / quick) ask the model to wait until your point sounds complete instead. How much difference this makes depends on the language and on how you speak, so try both. The choice is remembered and applies from the next session.

**Display**: During a conversation, the default live view shows two zones — the partner's previous utterance and the one in progress. Check `Cards while talking` to use the conventional stacked cards during the conversation instead. The setting applies only while a session is running: once it ends, the display always returns to the card list, where the conversation can be edited, saved, and loaded like any other.

In the live view the sentence the assistant is currently speaking is highlighted, so you can follow the voice in the text — useful when the reply is long, since the text arrives well ahead of the audio. The highlight follows the audio itself, pauses while a tool is running, and stops where the speech stopped if you interrupt. It is not shown in the card display.

**Tools** (off by default): Enable the `Tools` toggle to let the assistant call tools during the conversation: current time, Python code execution, Knowledge Base search, and web search (web search requires a `TAVILY_API_KEY`). Python and Knowledge Base are available only while their respective containers are running. A turn that used tools stays on a single card, with a 🛠 badge naming the tool at the paragraph boundary where it was called (red on failure); the status line shows "Using ..." while a call runs.

**Session behavior**: The conversation stops automatically after a period of silence (default: 3 minutes). Gemini sessions have a 15-minute connection limit; when it is reached, the app reconnects automatically and the conversation continues. The Privacy Filter does not apply — audio reaches the provider directly. The conversation is saved to the Knowledge Base. Thinking-process display is not available, because realtime models do not emit a reasoning trace.

**Cost**: While connected, billing accrues during silent time as well. Approximate rates: OpenAI ~$6/hour, xAI ~$4.80/hour, Gemini ~$1.38/hour (estimates — refer to each provider's pricing page for current rates). A running cost estimate for the session is shown at the top of the window. This readout is specific to Live Conversation: it is the only app whose charges keep accruing while nobody is speaking, so the total is kept in view rather than left to be discovered afterwards.


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
