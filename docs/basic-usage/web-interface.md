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
- **Reset All**: After you confirm, clear the page's stored data (local storage and caches) and reload it, returning to the initial app selection. Cookies, such as the theme, the conversation language and whether the menu is shown, are kept
- **Monadic Chat Console**: Show the main console window

### External Browser Mode :id=external-browser-mode

In external browser mode, Monadic Chat launches your default web browser and connects to the local server (at `http://localhost:4567`).

## Language Settings :id=language-settings

Select the **Conversation Language** in the Monadic Chat Info panel. It sets the language for speech-to-text, text-to-speech and the AI's responses. 57 languages are available, plus **Automatic**. Right-to-Left (RTL) text display is applied for Arabic, Hebrew, Persian, and Urdu.

You can change the language at any time during a conversation. The choice is stored in a browser cookie. The language of the interface itself is set with **UI Language** in the settings window (see [Console Panel](./console-panel.md#settings-panel)).

## System Settings Screen :id=system-settings-screen

<!-- SCREENSHOT: System settings panel showing Base App selector, Model dropdown, reasoning controls, token limits, and parameters -->

This screen is where you choose the app and model for a session and adjust the conversation parameters. Once a session starts, the bar at the top has two tabs, **Current settings** and **Session**: **Current settings** shows this screen and **Session** shows the conversation, where you left it. **Continue Session** under the settings also goes back to the conversation. After you open a chat from the history, **Session** continues it, as **Continue Session** does. The bar also shows the app, the model and badges.

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
The bar at the top shows badges for the features in effect: **Web Search**, **Math**, **Knowledge Base**, and the current reasoning effort (when it is not off). The Knowledge Base badge appears while **Use Knowledge Base for retrieval (this session)** is on. In [Live Conversation](../apps/chat-apps.md#live-conversation), some of these settings have no UI, so the corresponding badges do not appear.

The top bar of the page shows the conversation status.

## Sidebar Panels :id=info-panel

The sidebar has four tabs at the top: **Menu**, which holds the following panels from top to bottom, **Work screen** (see [Work Screen](#work-screen) below), **Files** (see [Files Tab](#shared-folder-panel)) and **History** (see [History Tab](#chat-history-panel), shown while chats are kept). The page opens on Menu. Click a panel's title to collapse or expand it.

The tabs, and the bar with **Current settings** above the conversation, stay at the top while the column under them scrolls. Drag the border between the conversation and the sidebar to change the sidebar's width; you can also select the border with the Tab key and use ← and → (Home and End for the narrowest and widest). The width is kept, and is the same for every tab. On a narrow window, the sidebar and the conversation take turns at the full width.

**Monadic Chat Info**<br />
Links to the homepage and GitHub, the current version, the **Conversation Language** selector, the **Web Search** and **Math Rendering** switches, the name and description of the current base app, **Help Data** (the help database used by the Monadic Chat Help app: its status and an install button), and the list of **Available Variables**.

- **Web Search**: Allow the AI to search the web for current information. Available for models that support tool/function calling. In [Live Conversation](../apps/chat-apps.md#live-conversation), web search is part of the app's own Tools toggle instead (off by default).
- **Math Rendering**: Render mathematical expressions using KaTeX. When it is off, the model is asked to write formulas in plain text or Unicode, and to return LaTeX source, when you ask for it, in a code block.

**AI Assistant & AI User**<br />
The models in use for the assistant and for the AI User feature, and the statistics of the current session (message and token counts).

**PDF Database**<br />
Shown only for apps with a PDF database. See [PDF Database Panel](#pdf-database-display-panel) below.

**Knowledge Base**<br />
**Save** the current conversation to the Knowledge Base, **Browse** it, and turn **Use Knowledge Base for retrieval (this session)** on or off. See [Knowledge Base](../apps/knowledge-base.md).

**Session Controls**<br />
- **Reset**: Clear the current conversation and reset parameters to defaults while keeping your app selection. To also clear the page's stored data and return to the initial app selection, use **Reset All** in the internal browser
- **Import**: Load conversation data from a JSON file. If the saved session uses a deprecated model that has a successor, the successor is used and a notification is shown
- **Export**: Save the current conversation to a JSON file
- **PDF Export**: Save the current conversation as a PDF file with syntax highlighting and formatting

**Session Context**<br />
Shown for apps that keep monadic context: the context tracked in the conversation, which you can edit and save.

**Theme**<br />
System, Light or Dark.

**Interaction**<br />
- **Auto speech**: Automatically read the assistant's response aloud using synthesized speech
- **Easy submit**: Send messages with the Enter key, or by clicking **Stop** after speech input
- **Auto scroll while streaming**: Follow the response as it is written
- **Show new items in the work screen**: When the AI shows something new, the sidebar switches to the [work screen](#work-screen). When off, the work screen announces it and you switch yourself
- **Start from assistant**: The assistant makes the first message when starting a conversation

These controls are hidden in [Live Conversation](../apps/chat-apps.md#live-conversation), which manages audio itself.

**Speech**<br />
See [Speech Panel](#speech-settings-panel) below.

## Work Screen :id=work-screen

The **Work screen** tab shows the browser the AI uses in the current conversation, as it draws, while the tab is shown. It is view only. When the AI opens a browser (for example in [Web Insight](../apps/analysis-apps.md#web-insight)), the sidebar switches to this tab.

The browser stays open after the reply and closes after five minutes without use. **Reset** closes it. Screenshots that the AI captures without opening a browser are not shown here.

The work screen also shows the images the AI makes, such as an image generated by [Image Generator](../apps/image-generator.md). A row at the top lists the items of the work screen; click one to show it. The browser is one of them: it stays in the row after it closes (the work screen then says so) until you remove it with its ×. Each image is a file in the chat's folder of the shared folder: the work screen shows its path and **Save as…** (**Download** in a web browser), which saves a copy anywhere you choose. The × on an image's tab removes it from the work screen; the file stays in the shared folder. The conversation shows one line with the image's path and **Save as…**; click the path to show the image in the work screen.

The work screen also shows files of the shared folder: images, text files (with line numbers; a long file shows its beginning), audio, video, and PDFs (a page at a time: move between pages with ‹ and › or the ← and → keys, zoom with − and +, and select text on the page). To open one, click it in the [Files tab](#shared-folder-panel). The AI can also show a file of the shared folder there while it talks about it. A file is not copied: if it changes or is removed in the shared folder after it was opened, the work screen says so; **Open it as it is now** shows the file again as it is. **Reload** reads a file shown again at any time. A file opened again, by you or by the AI, takes the place of the one shown before.

Some text files are drawn: Markdown (`.md`), Mermaid diagrams (`.mmd`), tables (`.csv`, `.tsv`: the first row is the header, and the first 2,000 rows and 50 columns are shown), SVG images, static HTML pages (`.html`: scripts do not run, links do not open, and only images embedded as `data:` show), Vega-Lite charts (`.vl.json`, with the data in the file), draw.io diagrams (`.drawio`, the first page; images the diagram names are not loaded), and tunes in ABC notation (`.abc`, drawn as a score). **Drawn** and **Source** above the file switch between the drawing and the text with line numbers. Nothing drawn is loaded from the network. A file larger than 8 MB, or one that cannot be drawn, is not drawn: the work screen says why, and **Source** shows its text.

The AI can also write a text it made, such as a table, a diagram, a chart or a long document, as a new file in the chat's folder and show it in the work screen in one step. A line under the reply names each file the AI showed in the work screen; click it to show that version again (if the file changed since, the work screen says so).

The items stay in a row in the order they came. Move along it with ‹ and › above the item, or with the ← and → keys while the work screen has the focus.

When you send a message, the AI is told what is on the work screen: the name, path and status of each item, the item your tab shows, and what part of it is in view (the lines of a text file, the page of a PDF, the position in audio or video, and how many characters you selected). The contents of the items are not sent this way.

The AI can also look at the item your tab shows, when it needs to see it: an image as it is, or a text file as text: either the lines you have in view and a few lines around them, or the file from its beginning (a long file is cut). A PDF is looked at as the part of the page in view (an image of it as your tab draws it), the text of that whole page, and any text you selected in it; or as the text of its first 100 pages. To see what is in view, the AI asks your tab, which answers while the work screen shows the file. The text of a PDF is read in the Python container; when it is not running, the AI gets the image and the selected text only. The browser is looked at as a picture of what it shows in its window (not the whole page), with the page's title and its address without the part after `?` or `#`; this works only in the desktop app's containers, not when the server runs on the host for development. It looks at the item selected in the tab you sent the message from, as it is at that moment; if the file changed or you selected another item meanwhile, it looks at nothing rather than at something else. When the work screen shows a file drawn, the AI cannot tell which of its lines are in view; it reads the file's text from its beginning instead, and is told that this is the text, not the drawing. Audio and video cannot be looked at. The AI can look only with a model that takes images. A line under the reply says what the AI looked at (its name, version and lines) and whether it was sent to the AI provider; if the reply ends without an answer, the line is under your message. The conversation and the history keep that line, not what was looked at. If the chat is reset before the request is sent, nothing of it is sent.

When the AI shows something new, the work screen shows it, unless you are typing a message or turned off **Show new items in the work screen** in the Interaction panel. What you open yourself is always shown. If the sidebar is hidden, it stays hidden. The work screen keeps up to eight items: when a new one comes, the oldest item is removed from the work screen (its file stays in the shared folder). The item an open page (a web browser tab) is showing, the latest image and an open browser are kept. When every item is kept, remove one with its × before opening another; a browser that opens then is shown once you remove one.

## Speech Panel :id=speech-settings-panel

<!-- SCREENSHOT: Speech panel showing Speech-to-Text model selector, Text-to-Speech provider and voice dropdowns, and TTS speed slider -->

!> **Note:** To use the speech feature, you need to use the Google Chrome, Microsoft Edge, or Safari browser.

This panel is not used in [Live Conversation](../apps/chat-apps.md#live-conversation) — that app has its own voice and speed selectors in its control row.

**Speech-to-Text Model**<br />
Select your preferred speech-to-text model. Available options include OpenAI, Gemini, ElevenLabs, Cohere, Mistral, and xAI models.

**Text-to-Speech Provider**<br />
Select the provider for speech synthesis (OpenAI, ElevenLabs, Gemini, Mistral, Grok TTS, or Web Speech API).

**Expressive Speech**<br />
When Auto speech is on and the selected TTS provider supports Expressive Speech (OpenAI's TTS model with instructions, xAI Grok, ElevenLabs v3 and v4, Gemini TTS), an **Expressive Speech** badge appears beneath the provider dropdown. The speech then carries tone, pauses, laughter and the like that suit the reply; the chat shows the reply as written. Hover the badge for a description.

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

## History Tab :id=chat-history-panel

Monadic Chat keeps your chats on this computer, in `~/monadic/state`, outside the shared folder. A chat is kept from the first message you write, and each new message updates it.

What is kept of a chat: the text of its messages, the app, the model and the system prompt, the main settings (such as reasoning effort, context size, web search and the conversation language), and the [Session Context](../advanced-topics/session-context.md). Images, the contents of attached files, thinking and the records of tool calls are not kept. The API keys set in Monadic Chat and 1Password references are removed from what is kept, chat names included. Other secrets written in a chat, such as a password or a key that Monadic Chat does not have, are kept as written: do not paste them into a chat.

Backups of your computer (such as Time Machine) and sync services that hold `~/monadic` copy the history too. **Export Document DB** in the Actions menu does not include the history.

The **History** tab lists the kept chats, the latest activity first, and is shown while chats are kept.

- The search box finds chats by their names and by the words in them. **Show more** adds older chats.
- Each chat shows its name (or its first and latest topics), the app, the number of messages and when it last had a new message.
- Click a chat to continue it in this tab with its messages, app, model and settings. The app's tools are set up anew, and Auto speech and Start from assistant are off for the continued chat. The chat that was in this tab stays in the history. On a narrow window, the conversation is shown after the chat is continued.
- The **⋯** button of a chat holds **Continue**, **Name** and **Remove from the history**. **Name** gives the chat a name (up to 120 characters); press Enter to save it or Esc to cancel. **Remove from the history** asks you to confirm in the row. A removed chat can no longer be read from Monadic Chat; files the chat made in the shared folder, exported files and backups of your computer are not removed.
- A chat open in a tab is marked "Open in a tab" and can be neither continued nor removed from another tab. To continue or remove it, start a new chat in the tab that has it open.

## Files Tab :id=shared-folder-panel

The **Files** tab shows what the shared folder (`~/monadic/data`) holds, one folder at a time. Click a folder to open it; use the path at the top, or the up-arrow button, to go back. Click a file to open it in the [work screen](#work-screen) (images, text files, audio, video and PDFs); clicking another kind of file selects it.

Each entry shows its name, when it was last modified, its size and what it is:

- **What it is** comes from Monadic Chat's own record where it has one (the folders of chats, files named `pub_…`) and otherwise only from the entry's name, marked "(by its name)". A name does not tell whether a file is still needed. The videos and subtitles the page plays are kept by Monadic Chat outside the shared folder; files named `pub_…` in the shared folder are not used and can be moved to the trash.
- Entries Monadic Chat or your own setup reads (your scripts, apps and helpers, your Docker services, the backup of the document database) are marked with a lock and the reason.
- The folder of a chat open in a tab is marked "in use".
- Files made by Monadic Chat's own test runs (named `monadic-test-…`) are marked "Made by a test run"; names that test runs used before are marked "Possibly left by a test run".
- Links are listed as links and not followed.
- Sizes of folders are counted in the background and appear as they finish. A size shown as "≥" was counted only in part (a very large folder, or one partly unreadable).

The search box finds entries by name, the menu beside it orders them by name, modification time (**Newest first**) or size (**Largest first**; kept for the next time), and the filter button narrows the list to one kind of item or to items not modified in the last 30, 90 or 365 days. While a filter is on, a band above the list says so, with a button to clear it. **Show more** adds the next 50 entries. A line above the list says when it is loading, when the folder is empty or nothing matches, and what went wrong, what was copied or what moving to the Trash did; a result stays until you close it.

Select entries with the box before each one: Shift+click selects a range, and Cmd/Ctrl+click on a name selects it without opening it. In the list, ↑ and ↓ move, Shift+↑ and ↓ extend the selection, Space selects, Enter opens, Cmd/Ctrl+A selects all shown, and Esc clears the selection. The select button above the list holds **Select all shown**, **Select all that can be moved to the Trash** (every matching entry, shown or not), **Select test files** and **Skip folders when selecting all**. While entries are selected, a band above the list shows their count and total size, with buttons to copy the paths a chat uses for them (`/monadic/data/…`, one per line), to move them to the Trash, and to clear the selection.

The **⋯** button of an entry (or the Menu key, or Shift+F10, in the list) holds what can be done with it: open it, copy its path, show it in your file manager (in the desktop app; neither a folder nor a file is opened) and move it to the Trash.

In the desktop app, entries can be moved to the system's Trash. Only entries Monadic Chat allows are moved: entries that are kept for a reason, and the folder of a chat open in a tab and what is in it, can be selected (to copy their paths) but are not moved, and the band says how many of the selected cannot be moved. In a browser, the button is shown but cannot be used, and the band says so. Confirm in the dialog that names the count and the first items. Moved items can be put back from the Trash.

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
