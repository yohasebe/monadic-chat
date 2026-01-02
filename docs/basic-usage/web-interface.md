# Monadic Chat Web Interface

<!-- SCREENSHOT: Main web interface showing chat area, sidebar with settings, and status indicators -->

## Browser Modes :id=browser-modes

Monadic Chat supports two different browser modes for accessing its web interface:

### Internal Browser Mode :id=internal-browser-mode

The internal browser mode runs within the Electron desktop application, providing a dedicated window with Monadic Chat-specific features.

When running in internal browser mode, five additional buttons appear at the bottom-right corner:
- **Zoom In**: Increase the page zoom factor
- **Zoom Out**: Decrease the page zoom factor
- **Reset Zoom**: Reset page zoom to default
- **Reset All**: Completely reset the application including all stored data (localStorage, cookies, cache, etc.) and return to the initial app selection. This provides a fresh start as if you just launched Monadic Chat.
- **Monadic Chat Console**: Show the main console window


### External Browser Mode :id=external-browser-mode

In external browser mode, Monadic Chat launches your default web browser and connects to the local server (at `http://localhost:4567`).


## Application Modes :id=application-modes

**Standalone Mode (Default)**<br />
Runs locally on a single device for personal use.

**Server Mode**<br />
Allows multiple devices on the local network to connect to the same Monadic Chat instance. The interface adapts to different screen sizes. Jupyter Notebook functionality is disabled by default for security reasons.

Configure the application mode in the Console Settings panel.

## Language Settings :id=language-settings

The interface supports 58 languages. Select your preferred language from the dropdown in the Info panel to configure speech-to-text, text-to-speech, and AI response language. Right-to-Left (RTL) text display is automatically applied for Arabic, Hebrew, Persian, and Urdu.

You can change the language at any time during a conversation. Your language preference is saved and restored on your next session.

## System Settings Screen :id=system-settings-screen

<!-- SCREENSHOT: System settings panel showing Base App selector, Model dropdown, reasoning controls, token limits, and various chat options -->

**Base App** <br />
Select one of the basic apps. Each app has different default parameters and initial prompts. See [Base Apps](./basic-apps.md) for details.

**Model** <br />
Select the AI model to use. Available models depend on the selected app.

**Reasoning/Thinking Control** <br />
Adjust the reasoning depth for models that support advanced thinking. The selector adapts to each provider's terminology (OpenAI: Reasoning Effort, Anthropic: Thinking Level, Google: Thinking Mode, xAI: Reasoning Effort, DeepSeek: Reasoning Mode, Perplexity: Research Depth).

**Max Output Tokens** <br />
Limit the maximum number of tokens in the API response.

**Max Context Size** <br />
The maximum number of messages to keep active in the conversation context.

**Parameters**<br />
Temperature, Top P, Presence Penalty, Frequency Penalty

**Show Initial Prompt**<br />
Display or edit the system prompt sent to the AI.

**Show Initial Prompt for AI-User**<br />
Display or edit the system prompt for the AI User feature.

**Prompt Caching**<br />
Enable prompt caching to reduce API costs and improve response time.

**Math Rendering**<br />
Render mathematical expressions using MathJax.

**AI User Provider**<br />
Select a provider for the AI User feature, which automatically generates follow-up messages as if written by a human user.

**Start from assistant**<br />
The assistant makes the first message when starting a conversation.

**Chat Interaction Controls**<br />
Options for voice-based conversations. Click the `toggle all` link to enable or disable all options at once.

**Auto speech**<br />
Automatically read the assistant's response aloud using synthesized speech.

**Easy submit**<br />
Press Enter to send messages without clicking the Send button.

**Web Search**<br />
Allow the AI to search the web for current information. Available for models that support tool/function calling.

**Start Session / Continue Session** <br />
Start a new chat or continue your current conversation.

## Info Panel :id=info-panel

<!-- SCREENSHOT: Info panel showing Monadic Chat version, links to related websites, current base app name and description -->

**Monadic Chat Info**<br />
Links to related websites and the current version.

**Current Base App**<br />
Name and description of the selected app.

## Status Panel :id=status-panel

<!-- SCREENSHOT: Status panel displaying current conversation status, selected model name, and chat statistics (message count, token count) -->

**Monadic Chat Status**<br />
Current conversation status, updated in real-time.

**Model Selected**<br />
The currently selected model.

**Model Chat Stats**<br />
Message and token counts for the current session.


## Session Panel :id=session-panel

<!-- SCREENSHOT: Session panel with Reset, Settings, Import, Export, and PDF Export buttons -->

**Reset (Reset Conversation)**<br />
Click the `Reset` button to clear the current conversation and reset parameters to defaults while keeping your app selection. This allows you to start fresh with the same app. For a complete reset including all stored data and returning to the initial app selection, use the **Reset All** button in the floating toolbar (Internal Browser Mode only).

**Settings**<br />
Return to the System Settings panel. Click `Continue Session` to return to your conversation.

**Import**<br />
Load conversation data from an external JSON file.

**Export**<br />
Save the current conversation to an external JSON file.

**PDF Export**<br />
Save the current conversation as a PDF file with syntax highlighting and formatting.

## Speech Settings Panel :id=speech-settings-panel

<!-- SCREENSHOT: Speech settings panel showing Speech-to-Text model selector, Text-to-Speech provider and voice dropdowns, and TTS speed slider -->

!> **Note:** To use the speech feature, you need to use the Google Chrome, Microsoft Edge, or Safari browser.

**Speech-to-Text Model**<br />
Select your preferred speech-to-text model. Available options include OpenAI and Gemini models.

**Text-to-Speech Provider**<br />
Select the provider for speech synthesis (OpenAI, ElevenLabs, Gemini, or Web Speech API).

**Text-to-Speech Voice**<br />
Select the voice for speech synthesis. Available voices depend on the selected provider.

**TTS Speed**<br />
Adjust the playback speed of synthesized speech (0.7 to 1.2).


## PDF Database Display Panel :id=pdf-database-display-panel

<!-- SCREENSHOT: PDF database panel listing uploaded PDFs with display names and delete icons -->

?> This panel is displayed only when an app with PDF reading functionality is selected.

**Uploaded PDF**<br />
This displays a list of PDFs uploaded by clicking the `Import PDF` button. You can give a unique display name to the file when uploading a PDF. If not specified, the original file name is used. Multiple PDF files can be uploaded. Clicking the trash can icon to the right of the PDF file display name will discard the contents of that PDF file.

!> **Warning:** PDF files are converted to text embeddings and stored according to your selected storage mode. For Local Storage mode (PGVector), the database will be cleared when the Docker container is rebuilt or when Monadic Chat is updated. Use the `Export Document DB` feature to back up and restore your data. For more information about storage modes, see [PDF Storage Modes](./pdf_storage.md).

## AI User Feature :id=ai-user-feature

The AI User feature allows an AI to generate simulated user responses in a conversation. This enables automated conversation continuation where the AI plays the role of the user, creating follow-up messages based on the conversation context.

### How It Works

When you click the **AI User** button (robot icon) in the message input area, the selected AI provider generates a response as if it were the user. The AI analyzes the recent conversation history and produces a natural follow-up question or comment that a human user might make.

### Configuration

**AI User Provider**<br />
Select which AI provider generates the simulated user responses. This can be different from the main conversation's AI provider. Available providers depend on which API keys you have configured:
- OpenAI
- Claude (Anthropic)
- Gemini (Google)
- Mistral
- Cohere
- Perplexity
- Grok (xAI)
- DeepSeek

**Initial Prompt for AI-User**<br />
Customize the system prompt that guides how the AI generates user responses. You can modify this to adjust the personality, focus areas, or response style of the simulated user.

### Use Cases

- **Hands-free conversation**: Continue a conversation without typing, useful during multitasking
- **Exploration**: Let the AI explore topics by generating follow-up questions automatically
- **Testing**: Test how an assistant handles various user inputs
- **Learning**: Observe how an AI might naturally continue a conversation on a topic

### Tips

- The AI User considers the last 5 messages of conversation history when generating responses
- For best results, start with a clear topic or question before using AI User
- You can use AI User multiple times in succession to create an extended automated conversation
- The generated message appears in the input field, allowing you to review and edit before sending
