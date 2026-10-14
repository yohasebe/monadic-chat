# Chat & Assistant Apps

General-purpose conversation and assistant apps: standard and metadata-enriched chat, voice conversation, and assistants for encyclopedic lookup, math, second opinions, research, and Monadic Chat itself.

## Chat

![Chat app icon](../assets/icons/chat.png ':size=40')

Have a standard conversation with the AI, which responds with appropriate emojis. Web search is available for models that support tool calling; whether a provider uses its built-in search or the Tavily API (requires a `TAVILY_API_KEY`) is shown in the [Provider Capabilities table](../basic-usage/basic-apps.md#provider-capabilities).

With the `Text from URL` button below the message box, you can read the text of a web page into your message, with any provider.

Availability for this app follows the [App Availability by Provider](../basic-usage/basic-apps.md#app-availability) table.


## Chat Plus

![Chat app icon](../assets/icons/chat-plus.png ':size=40')

A chat that keeps track of the conversation. As the AI responds, it updates these lists in the side panel:

- **Topics**: The topics discussed so far.
- **People**: The people mentioned in the conversation.
- **Notes**: Key facts and preferences to remember.

Chat Plus also has web search and the Privacy Filter. The OpenAI version can search the PDFs in the [PDF Database](../basic-usage/pdf_storage.md) and cite them.


## Voice Chat :id=voice-chat

![Voice Chat app icon](../assets/icons/voice-chat.png ':size=40')

Chat with the AI using your voice. Your speech is transcribed with the **Speech-to-Text Model** selected in the Speech panel, and the replies are read aloud with the **Text-to-Speech Provider** selected there. The default output is the browser's built-in Web Speech API, which needs no API key; OpenAI, ElevenLabs, Gemini, Mistral, and xAI Grok voices can be selected instead. The chat provider and the speech providers can be combined freely, for example Claude for the conversation and xAI Grok for the voice.

While you speak, a waveform is shown. When the speech-to-text model returns a confidence value, a p-value is shown after you stop; see [Speech Input](../basic-usage/message-input.md#speech-input).

Voice Chat supports the providers indicated in the [availability table](../basic-usage/basic-apps.md#app-availability). For the speech settings, see [Speech Panel](../basic-usage/web-interface.md#speech-settings-panel).

**Expressive Speech**: When Auto Speech is on and a compatible text-to-speech provider is selected, an ✨ **Expressive Speech** badge appears under the Text-to-Speech Provider menu, and the replies are spoken with expressive cues (pauses, laughter, voice directions) that do not appear in the text. How this is done depends on the provider; see [Speech Panel](../basic-usage/web-interface.md#speech-settings-panel).

For a continuous, hands-free conversation that streams audio directly to the provider's realtime speech-to-speech API, see [Live Conversation](#live-conversation) below.


## Live Conversation :id=live-conversation

Talk with the AI in a continuous, hands-free voice conversation. Unlike [Voice Chat](#voice-chat) — which runs speech recognition, the language model, and speech synthesis as three separate steps — Live Conversation streams audio directly to the provider's realtime speech-to-speech API, so responses start sooner and the exchange flows without button presses.

Three variants are available, one per provider: OpenAI, xAI Grok, and Google Gemini. A variant can be selected only when its provider's API key is configured.

**How it works**: Click `Start` to open the conversation, then speak naturally — the end of each utterance is detected automatically (voice activity detection) and the turn proceeds on its own. Click `End` to close the session. There is no text input in this app. Headphones are recommended: with speakers, the assistant's voice feeds back into the microphone and can trigger unintended turns.

**Voice and speed**: Pick the assistant's voice from the selector in the app's control row (the text-to-speech settings in the Speech panel do not apply here). The number of available voices is 10 for OpenAI (default: alloy), 26 for xAI (default: eve), and 30 for Gemini (default: Kore). A playback speed slider (0.25–1.5) is available for OpenAI only. Your voice choice is remembered per provider.

**Turn detection** (OpenAI variant only): Choose how the end of your utterance is decided. The default judges by silence; the "by meaning" modes (patient / balanced / quick) ask the model to wait until your point sounds complete instead. How much difference this makes depends on the language and on how you speak, so try both. The choice is remembered and applies from the next session.

**Display**: During a conversation, the default live view shows two zones — the partner's previous utterance and the one in progress. Check `Cards while talking` to show the conversation as cards during the conversation instead. The setting applies only while a session is running: once it ends, the display always returns to the card list, where the conversation can be edited, saved, and loaded like any other.

In the live view the sentence the assistant is currently speaking is highlighted, so you can follow the voice in the text — useful when the reply is long, since the text arrives well ahead of the audio. The highlight follows the audio itself, pauses while a tool is running, and stops where the speech stopped if you interrupt. It is not shown in the card display.

**Tools** (off by default): Enable the `Tools` toggle to let the assistant call tools during the conversation: current time, Python code execution, Knowledge Base search, and web search (web search requires a `TAVILY_API_KEY`). Python and Knowledge Base are available only while their respective containers are running. A turn that used tools stays on a single card, with a 🛠 badge naming the tool at the paragraph boundary where it was called (red on failure); the status line shows "Using ..." while a call runs.

**Session behavior**: The conversation stops automatically after a period of silence (default: 3 minutes). Gemini sessions have a 15-minute connection limit; when it is reached, the app reconnects automatically and the conversation continues. The Privacy Filter does not apply — audio reaches the provider directly. The conversation can be saved to the Knowledge Base like other conversations. Thinking-process display is not available, because realtime models do not emit a reasoning trace.

**Cost**: While connected, billing accrues during silent time as well, and the rate differs considerably between providers — check each provider's pricing page before a long session. A running cost estimate based on actual usage is shown at the top of the window.


## Wikipedia

![Wikipedia app icon](../assets/icons/wikipedia.png ':size=40')

Ask questions about recent events or topics outside the AI's knowledge. This app works like Chat, and searches Wikipedia when needed. It searches the English Wikipedia by default, and other language editions when asked. Wikipedia is available with OpenAI.


## Math Tutor

![Math Tutor app icon](../assets/icons/math-tutor.png ':size=40')

Explore math-related questions and answers. The app uses [KaTeX](https://katex.org/) to render beautiful mathematical notation in its responses.

Math Tutor can run Python code to calculate, and keeps the concepts, formulas, and tips of the session in the side panel.

!> **Caution:** LLMs can make mistakes in calculations with many steps or complex logic. Check the results, and ask the app to calculate with Python when accuracy matters.


## Second Opinion

![Second Opinion app icon](../assets/icons/second-opinion.png ':size=40')

Get a second opinion on an answer. First, ask your question and get an answer. Then ask the app to "double-check this answer"; it asks which provider should review the answer (OpenAI if you do not name one) and shows the review. You can also ask several providers (two to five) at once.

Second Opinion is available wherever the [availability table](../basic-usage/basic-apps.md#app-availability) lists support.


## Research Assistant

![Research Assistant app icon](../assets/icons/research-assistant.png ':size=40')

An assistant for academic and scientific research. It searches the web, reads and analyzes the sources, and keeps the topics, findings, and sources of the session in the side panel. Use it to find current information, check facts, and summarize a topic.

Research Assistant availability matches the [availability table](../basic-usage/basic-apps.md#app-availability). Whether web search uses the provider's own search or the Tavily API (requires `TAVILY_API_KEY`) is shown in the [Provider Capabilities table](../basic-usage/basic-apps.md#provider-capabilities). The OpenAI version can also search the PDFs in the [PDF Database](../basic-usage/pdf_storage.md). To read a web page into your message, see [Reading Text from URLs](../basic-usage/message-input.md#reading-text-from-urls).


## Monadic Chat Help

![Help app icon](../assets/icons/help.png ':size=40')

Ask questions about Monadic Chat: its features, how to use it, and how to solve problems, in any language. The assistant searches the Monadic Chat documentation and answers based on it.

The documentation is searched in the help data, which is installed from **Help Data** in the Monadic Chat Info panel. Monadic Chat Help uses OpenAI, so it needs an OpenAI API key. See [Help System](../advanced-topics/help-system.md).
