# Monadic Chat Web Interface

<!-- SCREENSHOT: Main web interface showing chat area, sidebar with settings, and status indicators -->

The web interface is made up of the conversation area, the message input area, and a set of side panels.

## Browser Modes :id=browser-modes

Monadic Chat supports two different browser modes for accessing its web interface:

### Internal Browser Mode :id=internal-browser-mode

The internal browser mode runs within the Electron desktop application, providing a dedicated window with Monadic Chat-specific features.

In internal browser mode, five buttons appear at the bottom-right corner (hover over each for its name):
- **Zoom In**: Increase the page zoom factor
- **Zoom Out**: Decrease the page zoom factor
- **Reset Zoom**: Reset page zoom to default
- **Reset All**: After you confirm, clear the page's stored data (local storage and caches) and reload it, returning to the initial app selection. Cookies, such as the theme and the conversation language, are kept
- **Monadic Chat Console**: Show the main console window

### External Browser Mode :id=external-browser-mode

In external browser mode, Monadic Chat launches your default web browser and connects to the local server (at `http://localhost:4567`).

## Language Settings :id=language-settings

Select the **Conversation Language** in the Monadic Chat Info panel. It sets the language for speech-to-text, text-to-speech and the AI's responses. 57 languages are available, plus **Automatic**. Right-to-Left (RTL) text display is applied for Arabic, Hebrew, Persian, and Urdu.

You can change the language at any time during a conversation. The choice is stored in a browser cookie. The language of the interface itself is set with **UI Language** in the settings window (see [Console Panel](./console-panel.md#settings-panel)).

## System Settings Screen :id=system-settings-screen

<!-- SCREENSHOT: System settings panel showing Base App selector, Model dropdown, reasoning controls, token limits, and parameters -->

This screen is where you choose the app and model for a session and adjust the conversation parameters. During a session, click the summary bar at the top (app, model and badges) to return to it.

**Base App** <br />
Select one of the basic apps. Each app has different default parameters and initial prompts. See [Base Apps](./basic-apps.md) for details.

**Max Context Size** <br />
The maximum number of messages to keep active in the conversation context (default: 100).

**Max Output Tokens** <br />
Limit the maximum number of tokens in the API response (default: 4000).

**Model** <br />
Select the AI model to use. Available models depend on the selected app; turn on **All** to list every model of the provider. Deprecated models are not listed.

**Reasoning/Thinking Control** <br />
Adjust the reasoning depth for models that support advanced thinking. Models with mandatory adaptive reasoning continue to reason even when reasoning controls are off or the app uses structured output; these settings do not eliminate reasoning costs. On such models, an app that asks for no reasoning runs at the lowest level the model offers. Hiding the thinking trace only changes its display. The selector adapts to each provider's terminology (OpenAI: Reasoning Effort, Anthropic: Thinking Level, Google: Thinking Mode, xAI: Reasoning Effort, DeepSeek: Reasoning Mode).

**Show Thinking** <br />
Show or hide the model's thinking/reasoning trace as a collapsible "Thinking Process" panel in each response. The toggle appears only for models that support thinking, and it is linked with the reasoning control: turning it on while the reasoning effort is "None" raises the effort to the model's lowest thinking level, and setting the effort back to "None" turns the toggle off. In [Live Conversation](../apps/chat-apps.md#live-conversation) this toggle is not shown, because realtime models do not emit a reasoning trace.

**Parameters**<br />
Temperature, Presence Penalty, Frequency Penalty

**Initial Prompt for AI Assistant**<br />
Display or edit the system prompt sent to the AI.

**Initial Prompt for AI User**<br />
Display or edit the system prompt for the AI User feature.

**Workflow Viewer**<br />
Show a live diagram of the selected app (Hidden, In Panel or Floating) — how input flows to the response, and which tools, agents and features the app can use. See [Workflow Viewer](./workflow-viewer.md).

**Start Session / Continue Session** <br />
Start a new chat or continue your current conversation.

**Session Indicator Badges**<br />
The summary bar shows badges for the features in effect: **Web Search**, **Math**, **Knowledge Base**, and the current reasoning effort (when it is not off). The Knowledge Base badge appears when the session reads from the Knowledge Base: when **Use Knowledge Base for retrieval (this session)** is on, or when the Knowledge Base app itself is selected. In [Live Conversation](../apps/chat-apps.md#live-conversation), some of these settings have no UI, so the corresponding badges do not appear.

The top bar of the page shows the conversation status and, while it is on, the Privacy Filter indicator.

## Sidebar Panels :id=info-panel

The sidebar holds the following panels, from top to bottom. Click a panel's title to collapse or expand it.

**Monadic Chat Info**<br />
Links to the homepage and GitHub, the current version, the **Conversation Language** selector, the **Web Search** and **Math Rendering** switches, the name and description of the current base app, **Help Data** (the help database used by the Monadic Chat Help app: its status and an install button), and the list of **Available Variables**.

- **Web Search**: Allow the AI to search the web for current information. Available for models that support tool/function calling. In [Live Conversation](../apps/chat-apps.md#live-conversation), web search is part of the app's own Tools toggle instead (off by default).
- **Math Rendering**: Render mathematical expressions using KaTeX. When it is off, the model is asked to write formulas in plain text or Unicode, and to return LaTeX source, when you ask for it, in a code block.

**AI Assistant & AI User**<br />
The models in use for the assistant and for the AI User feature, and the statistics of the current session (message and token counts).

**PDF Database**<br />
Shown only for apps with a PDF database. See [PDF Database Panel](#pdf-database-display-panel) below.

**Shared Folder**<br />
Browse the shared folder. See [Shared Folder Panel](#shared-folder-panel) below.

**Knowledge Base**<br />
**Save** the current conversation to the Knowledge Base, **Browse** it, and turn **Use Knowledge Base for retrieval (this session)** on or off. See [Knowledge Base](../apps/knowledge-base.md).

**Session Controls**<br />
- **Reset**: Clear the current conversation and reset parameters to defaults while keeping your app selection. To also clear the page's stored data and return to the initial app selection, use **Reset All** in the internal browser
- **Import**: Load conversation data from a JSON file. If the saved session uses a deprecated model that has a successor, the successor is used and a notification is shown
- **Export**: Save the current conversation to a JSON file
- **PDF Export**: Save the current conversation as a PDF file with syntax highlighting and formatting
- **Privacy Filter**: Turn the Privacy Filter on or off for the session, in apps that support it. See [Privacy Filter](../advanced-topics/privacy-filter.md)

**Session Context**<br />
Shown for apps that keep monadic context: the context tracked in the conversation, which you can edit and save.

**Theme**<br />
System, Light or Dark.

**Interaction**<br />
- **Auto speech**: Automatically read the assistant's response aloud using synthesized speech
- **Easy submit**: Send messages with the Enter key, or by clicking **Stop** after speech input
- **Auto scroll while streaming**: Follow the response as it is written
- **Start from assistant**: The assistant makes the first message when starting a conversation

These controls are hidden in [Live Conversation](../apps/chat-apps.md#live-conversation), which manages audio itself.

**Speech**<br />
See [Speech Panel](#speech-settings-panel) below.

## Speech Panel :id=speech-settings-panel

<!-- SCREENSHOT: Speech panel showing Speech-to-Text model selector, Text-to-Speech provider and voice dropdowns, and TTS speed slider -->

!> **Note:** To use the speech feature, you need to use the Google Chrome, Microsoft Edge, or Safari browser.

This panel is not used in [Live Conversation](../apps/chat-apps.md#live-conversation) — that app has its own voice and speed selectors in its control row.

**Speech-to-Text Model**<br />
Select your preferred speech-to-text model. Available options include OpenAI, Gemini, ElevenLabs, Cohere, Mistral, and xAI models.

**Text-to-Speech Provider**<br />
Select the provider for speech synthesis (OpenAI, ElevenLabs, Gemini, Mistral, Grok TTS, or Web Speech API).

**Expressive Speech**<br />
When Auto speech is on and the selected TTS provider supports Expressive Speech (OpenAI's TTS model with instructions, xAI Grok, ElevenLabs v3, Gemini TTS), an **Expressive Speech** badge appears beneath the provider dropdown. The speech then carries tone, pauses, laughter and the like that suit the reply; the chat shows the reply as written. Hover the badge for a description.

With Gemini TTS, the speech can include words such as "Oh," or laughter that are not in the text. For language-learning material or other uses that need the text read as written, turn Auto speech off or choose a provider without Expressive Speech.

**Text-to-Speech Voice**<br />
Select the voice for speech synthesis. Available voices depend on the selected provider.

**TTS Speed**<br />
Adjust the playback speed of synthesized speech (0.7 to 1.2).

## PDF Database Panel :id=pdf-database-display-panel

<!-- SCREENSHOT: PDF database panel listing uploaded PDFs with display names and delete icons -->

?> This panel is displayed only when an app with a PDF database is selected.

Click **Import** to upload a PDF; you can give it a title (if you leave it empty, the file name is used). Multiple PDF files can be uploaded. **Refresh** updates the list, the trash can icon next to a PDF removes it, and **Clear All** removes every PDF of the app, each after a confirmation.

PDFs are stored on your computer. Back them up with **Export Document DB** and restore them with **Import Document DB** (Actions menu). For more information, see [PDF Database](./pdf_storage.md).

## Shared Folder Panel :id=shared-folder-panel

The Shared Folder panel shows what the shared folder (`~/monadic/data`) holds. Click `Browse` to open the list. It shows one folder at a time; click a folder to open it, and use the path at the top to go back.

Each entry shows its name, what it is, its size and when it was last modified:

- **What it is** comes from Monadic Chat's own record where it has one (the folders of chats, the copies made for playing an attached video) and otherwise only from the entry's name, marked "(by its name)". A name does not tell whether a file is still needed.
- Entries Monadic Chat or your own setup reads (your scripts, apps and helpers, your Docker services, the backup of the document database) are marked with a lock and the reason.
- The folder of a chat open in a tab is marked "in use".
- Files made by Monadic Chat's own test runs (named `monadic-test-…`) are marked "Made by a test run"; names that test runs used before are marked "Possibly left by a test run".
- Links are listed as links and not followed.
- Sizes of folders are counted in the background and appear as they finish. A size shown as "≥" was counted only in part (a very large folder, or one partly unreadable).

The list can be searched by name, sorted by name, size (`Largest first`) or modification time (`Newest first`), and narrowed to one kind of entry.

In the desktop app, the button on the right of an entry shows it in your file manager, selected in the folder that holds it; neither a folder nor a file is opened. Entries with a check box can be moved to the system's Trash: tick them (or click `Select test files`), click `Move to Trash` and confirm in the dialog that names the count and the first entries. Entries that are kept for a reason, and the folder of a chat open in a tab and what is in it, cannot be selected. Moved entries can be put back from the Trash.

?> Monadic Chat keeps a small hidden file, `.monadic-shared-root`, in the shared folder. Do not remove it: without it, entries cannot be shown in the file manager or moved to the Trash (the list is still shown).

## AI User Feature :id=ai-user-feature

The AI User feature allows an AI to generate simulated user responses in a conversation. This enables automated conversation continuation where the AI plays the role of the user, creating follow-up messages based on the conversation context.

### How It Works

When you click **Run** (the play icon) next to the AI User provider selector in the message input area, the selected AI provider generates a response as if it were the user. The AI analyzes the recent conversation history and produces a natural follow-up question or comment that a human user might make.

### Configuration

**AI User Provider**<br />
Select, in the message input area, which AI provider generates the simulated user responses. This can be different from the main conversation's AI provider. Available providers depend on which API keys you have configured (OpenAI, Anthropic, Gemini, Cohere, Mistral, DeepSeek, Grok).

**Initial Prompt for AI User**<br />
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

## Response Verification :id=response-verification

Each AI response has a **Verify this response** action below it. Clicking it cross-checks the answer by asking a diverse panel of your other configured providers the same question — using the same conversation context the answer was written in — and judging how much they independently agree. Agreement across independent models is a trust signal: when diverse providers converge on the same answer it is more likely correct, and when they scatter the answer warrants more scrutiny.

### How It Works

- The question (and the prior conversation context) is sent to a panel of distinct configured providers, each on a cost-efficient model.
- A separate moderator model reads the panel's answers — anonymized, so it cannot favor any one provider — and reports how strongly they agree.
- The result appears under the response: a confidence level, what the panel agrees on, the points of disagreement, each member's own answer (expandable), the moderating model, and whether the original answer is corroborated or disputed.
- While verification runs, a spinner is shown and other actions are paused until it completes.

### Confidence Levels

- **High** — the panel strongly agrees; recommendation: trust.
- **Medium** — partial agreement; recommendation: verify.
- **Low** — the panel diverges; recommendation: escalate.
- If the original answer disagrees with the panel's consensus, it is flagged as disputed regardless of how much the panel agrees internally.

### Requirements and Limitations

- A meaningful cross-provider check needs **at least two configured providers**. With a single provider, verification falls back to a weaker self-consistency signal (clearly labeled), and a model that cannot vary its output reports that agreement cannot be measured rather than implying false confidence.
- Verification makes several model calls (the panel plus the moderator), so it spends additional tokens.

### Persistence

- A verification result is kept when you reload the page and when you export or import the conversation as JSON.
- It is **not** included when you save the conversation to a Knowledge Base or export to PDF — it is commentary about an answer, not part of the conversation's content.

The same capability is available to external agents through the `monadic_confidence` tool — see [MCP Integration](/advanced-topics/mcp-integration.md).
