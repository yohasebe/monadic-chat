# Monadic Chat Web Interface

![](../assets/images/monadic-chat-web.png ':size=700')

## Browser Modes :id=browser-modes

Monadic Chat supports two different browser modes for accessing its web interface:

### Internal Browser Mode :id=internal-browser-mode

The internal browser mode runs directly within the Electron desktop application using webview functionality. This mode provides an all-in-one experience where you can interact with the chat interface without switching between applications.

Benefits of internal browser mode:
- All functionality contained within a single application window
- Full copy/paste support between the chat and other applications
- Keyboard shortcuts for common operations
- Built-in search functionality for conversations
- Consistent experience across platforms

When running in internal browser mode, four additional buttons appear at the bottom-right corner of the interface:
- **Zoom In**: Increases the page zoom factor
- **Zoom Out**: Decreases the page zoom factor
- **Reset App**: Clears session data, reloads the UI, and resets to the initial app selection
- **Monadic Chat Console**: Shows the main console window


### External Browser Mode :id=external-browser-mode

In external browser mode, Monadic Chat launches your default web browser and connects to the local server (at `http://localhost:4567`).


## Application Modes :id=application-modes

Monadic Chat supports two application modes that determine how the server operates:

### Standalone Mode (Default) :id=standalone-mode

In standalone mode, Monadic Chat runs locally on a single device and binds only to localhost (127.0.0.1). This is the default mode for personal use.

### Server Mode :id=server-mode

Server mode allows multiple clients to connect to a single Monadic Chat instance. When running in server mode:
- The web interface binds to all network interfaces (0.0.0.0) rather than just localhost
- Multiple users can access the same Monadic Chat instance from different devices on the local network
- The interface is responsive and adapts to different screen sizes (including tablets and smartphones)
- Some features like Jupyter notebook functionality are disabled for security reasons unless explicitly enabled
- A mobile-optimized layout automatically activates for screen widths of 767px or less

You can configure the application mode in the Console Settings panel on startup or through configuration variables in `~/monadic/config/env`.

## Language Settings :id=language-settings

Monadic Chat provides comprehensive language support through a unified language selector located in the Info panel:

### Supported Languages :id=supported-languages

The interface supports 58 languages, displayed with their native names and English translations (e.g., "日本語 (Japanese)", "العربية (Arabic)"). You can select your preferred language from the dropdown menu, which will:

- Configure the speech-to-text (STT) language for voice input
- Set the text-to-speech (TTS) language for audio output  
- Instruct the AI assistant to respond in your chosen language (works with all providers: OpenAI, Claude, Gemini, DeepSeek, Grok, Mistral, Perplexity, and Cohere)
- Automatically apply Right-to-Left (RTL) text display for Arabic, Hebrew, Persian, and Urdu

### Dynamic Language Switching :id=dynamic-language-switching

You can change the language at any time during an active conversation:
- The new language preference takes effect immediately for new messages
- Previous messages in the conversation remain unchanged
- Your language preference is saved in a cookie and restored on your next visit

### RTL Language Support :id=rtl-support

For Right-to-Left languages, Monadic Chat automatically:
- Displays message content with RTL text alignment
- Adjusts the message input field for RTL typing
- Maintains LTR layout for UI elements to preserve navigation consistency
- Keeps code blocks and technical content in LTR format for readability

## System Settings Screen :id=system-settings-screen

![](../assets/images/chat-settings.png ':size=700')

**Base App** <br />
Select one of the basic apps provided by Monadic Chat. Each app has different default parameter values and unique initial prompts. For the characteristics of each app, see [Base Apps](./basic-apps.md).

**Model** <br />
Models available for the selected app are displayed. If a default model is set for the app, the default model is pre-selected. You can change the model by selecting a different one from the dropdown list.  With many basic apps, the model list is automatically retrieved from the API, and multiple models are selectable. Please note that using a model other than the default one might result in errors if the model isn't suitable for the app.

**Reasoning/Thinking Control** <br />
For models with advanced reasoning capabilities, this selector automatically adapts to show provider-specific controls. The label and options change based on the selected provider and model (e.g., "Reasoning Effort" for OpenAI, "Thinking Level" for Claude, "Thinking Mode" for Gemini). Options typically range from minimal to high computational effort, allowing you to balance response quality with processing time. This control is only visible for models that support reasoning/thinking features and is automatically hidden for standard models. See the [Reasoning and Thinking Features](./language-models.md#reasoning-and-thinking-features) section for detailed information.


**Max Output Tokens** <br />
Specify the maximum number of tokens to be returned in the API response. When the checkmark is on, the response is limited to the specified number of tokens. The method for counting tokens varies depending on the model. For OpenAI models, see [What are tokens and how to count them](https://help.openai.com/en/articles/4936856-what-are-tokens-and-how-to-count-them).

**Max Context Size** <br />
The maximum number of utterances to keep active in the ongoing chat. Only active utterances are sent to the API as context information. Inactive utterances can still be referenced on the screen and are also saved when exported.

**Parameters**<br />

These elements are sent as parameters to the API. For details on each parameter, see the Chat API [Reference](https://platform.openai.com/docs/api-reference/chat). Note that parameters not supported by the selected model are ignored.

- Temperature (Note: For reasoning models, this parameter is replaced by "Reasoning Effort")
- Top P
- Presence Penalty
- Frequency Penalty

**Show Initial Prompt**<br />
Turn on to display or edit the text sent to the API as the initial prompt (also called the system prompt). The initial prompt can specify the character settings of the conversation and the format of the response. Default text is set according to the purpose of each app, but it can be freely changed.


**Show Initial Prompt for AI-User**<br />
Displays the initial prompt given to the AI user when the AI User feature is enabled. When the AI user is enabled, the first message must be created by the (non-AI) user.  Afterward, the AI will create messages on your behalf, based on the AI assistant's messages. You can edit or append to the messages entered in the text box by the AI user. The initial prompt for the AI user can be freely changed.

**Prompt Caching**<br />
Specify whether to enable prompt caching for the API. How caching works depends on the provider:
- **Anthropic Claude**: When enabled, explicitly marks system prompts, images, and PDFs for caching using cache_control. This reduces API costs and improves response time.
- **OpenAI**: Automatically caches prompts of 128+ tokens for 5-10 minutes without any special configuration. This reduces API costs for cached portions. While this setting doesn't affect OpenAI's automatic caching, keeping it enabled helps maintain consistency when switching between providers.

**Math Rendering**<br />
Request the AI agent to use MathJax format when displaying mathematical expressions and render mathematical expressions in the response using MathJax.

**AI User Provider**<br />
Select a provider for the AI User feature from the dropdown menu. The dropdown only shows providers for which you have configured valid API tokens in the settings. The AI User feature automatically generates responses as if they were written by a human user, helping to test conversations and see how the assistant responds to different inputs. After the assistant has replied, clicking the `Run` button next to the AI User provider dropdown will generate a natural follow-up message based on the conversation history, which you can edit before sending. This feature supports multiple providers (OpenAI, Claude, Gemini, Cohere, Mistral, Perplexity, DeepSeek, and Grok) and intelligently handles provider-specific formatting requirements.

The badge next to the selector shows the resolved default as `Provider (model - effort)` when the selected model supports reasoning/thinking; otherwise it shows `Provider (model)`. On first load the badge initializes automatically after models are populated (no reload required). AI User requests also apply provider-specific defaults for reasoning parameters and omit unsupported ones. Examples:

- OpenAI: adds `reasoning_effort` for reasoning/Responses models; omits `temperature` on those models
- Claude: enables `thinking` and maps the effort to a safe `budget_tokens`
- Gemini: configures `thinkingBudget` based on model presets/caps
- xAI Grok: maps UI effort to provider-supported values (e.g., minimal→low)
- Cohere: enables reasoning path and uses a conversation-compaction workaround when needed
- Perplexity, DeepSeek: apply safe defaults and avoid unsupported sampling settings


**Start from assistant**<br />
When on, the assistant makes the first utterance when starting a conversation.

**Chat Interaction Controls**<br />
Options to configure Monadic Chat for conversations using voice input. For conversations with voice input, it is recommended to turn on all the following options (`Start from assistant`, `Auto speech`, `Easy submit`). You can toggle all options at once by clicking the `toggle all` link, which intelligently checks all boxes if any are unchecked, or unchecks all if they're all checked.

**Auto speech**<br />
When on, the assistant's response is automatically read aloud using synthesized speech when it is returned. You can select the voice, speaking speed, and language (automatic or specified) for synthesized speech on the web interface.

**Easy submit**<br />
When on, pressing the Enter key on the keyboard automatically sends the message in the text area without clicking the `Send` button. If you are using voice input, pressing the Enter key or clicking the `Stop` button will automatically send the message.

**Web Search**<br />
When enabled, allows the AI to search the web for current information. This option is only available for models that support tool/function calling. The search behavior depends on the provider:
- OpenAI models that support the Responses API's native search will use it automatically (see <https://platform.openai.com/docs/guides/reasoning/knowledge-retrieval>). Others fall back to the Tavily integration when configured.
- For providers without native search, configure a Tavily API key so Monadic can issue external lookups where allowed.
- The AI decides when to search based on the query context.


**Start Session / Continue Session** <br />
Click this button to start a chat based on the options and parameters specified in the System Settings. If you have already started a session and click the `Settings` button to return to the System Settings panel, this button will be labeled `Continue Session`. Clicking it will return you to your ongoing conversation without resetting it.

## Info Panel :id=info-panel

![](../assets/images/monadic-chat-info.png ':size=400')

**Monadic Chat Info**<br />
Links to related websites and the version of Monadic Chat are shown. Clicking `API Usage` will take you to the OpenAI page. Note that the API Usage shown is the overall API usage and may not be limited to Monadic Chat.  The style in which Monadic Chat was installed (Docker or Local) is displayed in parentheses after the version number.

**Current Base App**<br />
The name and description of the currently selected base app are displayed. When Monadic Chat is launched, information about the default app, `Chat`, is displayed.

## Status Panel :id=status-panel

![](../assets/images/monadic-chat-status.png ':size=400')

**Monadic Chat Status**<br />
Shows the current status of the conversation. The status is updated in real-time as the conversation progresses.

**Model Selected**<br />
Displays the model currently selected for the conversation.

**Model Chat Stats**<br />
Shows details such as the number of messages and tokens exchanged in the current session.


## Session Panel :id=session-panel

![](../assets/images/monadic-chat-session.png ':size=400')

**Reset**<br />
Clicking the `Reset` button discards the current conversation and returns to the initial state while preserving the current app selection. All app parameters will be reset to their default values. When changing apps by selecting a different app in the dropdown, a confirmation dialog will appear asking if you want to reset the current conversation, as changing apps will reset all parameters.

?> **Note:** This Reset button in the Session panel maintains your current app selection, unlike the Reset App button in the internal browser which also resets to the initial app selection.

**Settings**<br />
Clicking the `Settings` button returns to the System Settings panel without discarding the current conversation. To return to the current conversation, click `Continue Session`.

**Import**<br />
Clicking the `Import` button discards the current conversation and loads conversation data saved in an external file (JSON). The settings saved in the external file will also be applied.

**Export**<br />
Clicking the `Export` button saves the current settings and conversation data to an external file (JSON).

**PDF Export**<br />
Clicking the `PDF Export` button opens the browser's print dialog, allowing you to save the current conversation as a PDF file. The PDF export includes all messages, code blocks with syntax highlighting, mathematical equations (rendered via MathJax), and images. The output is formatted for A4 paper size with proper pagination to ensure readability when printed or saved as PDF.

## Speech Settings Panel :id=speech-settings-panel

![](../assets/images/monadic-chat-tts.png ':size=400')

!> **Note:** To use the speech feature, you need to use the Google Chrome, Microsoft Edge, or Safari browser.

**Text-to-Speech Provider**<br />
Select the provider used for speech synthesis. Monadic exposes the providers you have configured (for example, OpenAI Text-to-Speech, ElevenLabs, Gemini TTS, or the browser's Web Speech API). Refer to each provider's documentation for the latest model variants, required API keys, and capabilities.

- **ElevenLabs (v3 Alpha)** — When the ElevenLabs API key is present, Monadic also surfaces the new `eleven_v3` model. It delivers the most expressive voices ElevenLabs offers, but is currently in alpha: expect higher latency, a 3,000 character limit per request, and plan for user review of generated takes. Playback starts only after ElevenLabs finishes generating the entire clip (streaming is unavailable), so the UI waits before audio begins.

**Text-to-Speech Voice**<br />
You can specify the voice used for speech synthesis. Available voices depend on the selected provider; consult the provider's documentation or interface for the latest options. When using the Web Speech API, the list of voices depends on your browser and operating system.

**Text-to-Speech Speed**<br />
You can adjust the playback speed of the synthesized speech, with values ranging from 0.7 (slower) to 1.2 (faster). Actual quality and supported ranges depend on the selected provider; consult provider documentation for guidance. The Web Speech API also supports speed adjustment, but quality may vary by browser and operating system.

**Speech-to-Text (STT) Language**<br />
Speech-to-Text API is used for speech recognition, and if `Automatic` is selected, it automatically recognizes voice input in different languages. If you want to specify a particular language, select the language from the selector. Monadic Chat uses the STT model configured in the console settings; refer to the provider documentation for current model offerings.
Reference: [OpenAI Whisper API FAQ](https://help.openai.com/en/articles/7031512-whisper-api-faq)


## PDF Database Display Panel :id=pdf-database-display-panel

![](../assets/images/monadic-chat-pdf-db.png ':size=400')

?> This panel is displayed only when an app with PDF reading functionality is selected.

**Uploaded PDF**<br />
This displays a list of PDFs uploaded by clicking the `Import PDF` button. You can give a unique display name to the file when uploading a PDF. If not specified, the original file name is used. Multiple PDF files can be uploaded. Clicking the trash can icon to the right of the PDF file display name will discard the contents of that PDF file.

!> **Warning:** The text from PDF files is converted to text embeddings and stored in the PGVector database. The database will be cleared when the Docker container is rebuilt or when Monadic Chat is updated. Export the database using the `Export Document DB` feature to save and restore the data.
