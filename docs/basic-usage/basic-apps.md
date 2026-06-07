# Basic Apps

The following basic apps are available. You can select any of the basic apps and adjust the behavior of the AI agent by changing parameters or rewriting the initial prompt. The adjusted settings can be exported/imported to/from an external JSON file.

Most basic apps support multiple AI providers. See the table below for specific app availability by provider.

For information on how to develop your own apps, refer to the [App Development](../advanced-topics/develop_apps.md) section.

## App Availability by Provider :id=app-availability

The table below shows which apps are available for which AI model providers.


| App | OpenAI | Claude | Cohere | DeepSeek | Google Gemini | xAI Grok | Mistral | Ollama |
|-----|:------:|:------:|:------:|:--------:|:------:|:----:|:-------:|:------:|
| Chat | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Chat Plus | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | |
| Voice Chat | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Wikipedia | ✅ | | | | | | | |
| Math Tutor | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | |
| Second Opinion | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | |
| Research Assistant | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | |
| Language Practice | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Language Practice Plus | ✅ | ✅ | | | | | | |
| Translate | ✅ | | ✅ | | | | | |
| Voice Interpreter | ✅ | | ✅ | | | | | |
| Novel Writer | ✅ | | | | | | ✅ | |
| Image Generator | ✅ | | | | ✅ | ✅ | | |
| Video Generator | | | | | ✅ | ✅ | | |
| Mail Composer | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Mermaid Grapher | ✅ | ✅ | | | ✅ | ✅ | | |
| DrawIO Grapher | ✅ | ✅ | | | ✅ | ✅ | | |
| Syntax Tree | ✅ | ✅ | | | | | | |
| Concept Visualizer | ✅ | ✅ | | | | | | |
| Speech Draft Helper | ✅ | | | | | | | |
| Web Insight | ✅ | ✅ | | | ✅ | ✅ | | |
| Video Describer | ✅ | | | | | | | |
| Knowledge Base | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Code Interpreter | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | |
| Coding Assistant | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Jupyter Notebook | ✅ | ✅ | | | ✅ | ✅ | | |
| Auto Forge | ✅ | ✅ | | | | ✅ | | |
| Music Lab | ✅ | ✅ | | | ✅ | ✅ | | |
| Music Analyst | | | | | ✅ | | | |
| Document Generator | | ✅ | | | | | | |
| Monadic Chat Help | ✅ | | | | | | | |

## Privacy Filter and Knowledge Base by App :id=privacy-kb-by-app

Privacy Filter (PF) and Knowledge Base save (KB) are **mutually exclusive** at the app level. Apps that handle PII intentionally are scoped as "ephemeral with PF on"; apps whose conversations have long-term retrieval value are scoped to KB save with PF off. A third group (artifact-centric apps such as image / video / diagram / document generators) supports neither — the artifact lives in `~/monadic/data/`, and the surrounding conversation is iteration-log noise that would only pollute KB search.

To preserve a PF-protected conversation, use **Privacy Export** (encrypted, optionally masked-only). To browse or share a KB entry, use the **Browse** modal in the right sidebar.

| App | Privacy Filter | Knowledge Base Save |
|-----|:--:|:--:|
| Chat | | ✅ |
| Chat Plus | ✅ | |
| Voice Chat | | ✅ |
| Wikipedia | | ✅ |
| Math Tutor | | ✅ |
| Second Opinion | ✅ | |
| Research Assistant | | ✅ |
| Language Practice | | ✅ |
| Language Practice Plus | | ✅ |
| Translate | ✅ | |
| Voice Interpreter | | ✅ |
| Novel Writer | | ✅ |
| Image Generator | | |
| Video Generator | | |
| Mail Composer | ✅ | |
| Mermaid Grapher | | |
| DrawIO Grapher | | |
| Syntax Tree | | |
| Concept Visualizer | | |
| Speech Draft Helper | | ✅ |
| Web Insight | | ✅ |
| Video Describer | | ✅ |
| Knowledge Base | | ✅ |
| Code Interpreter | | ✅ |
| Coding Assistant | | ✅ |
| Jupyter Notebook | | ✅ |
| Auto Forge | | |
| Music Lab | | |
| Music Analyst | | |
| Document Generator | | |
| Monadic Chat Help | | ✅ |

A blank cell in **both** columns indicates an artifact-centric app where the generated output (image, video, diagram, document, etc.) is the value, not the conversation. Use the per-card **Copy** / **Download** controls or the shared folder to retain artifacts; KB save is intentionally not available because the surrounding chat does not carry retrieval value.

## Provider Capabilities Overview

| Provider | Vision Support | Tool/Function Calling | Web Search |
|----------|----------------|----------------------|------------|
| OpenAI | ✅ | ✅ | ✅ Native |
| Claude | ✅ | ✅ | ✅ Native |
| Gemini | ✅ | ✅ | ✅ Native |
| Mistral | ✅ | ✅ | ✅ Tavily |
| Cohere | ✅ | ✅ | ✅ Tavily |
| xAI Grok | ✅ | ✅ | ✅ Native |
| DeepSeek | ❌ | ✅ | ✅ Tavily |
| Ollama | Model-dependent | Model-dependent | ✅ Tavily |

## Assistant :id=assistant

### Chat

![Chat app icon](../assets/icons/chat.png ':size=40')

Start a standard conversation with the AI, which will respond to your text with appropriate emojis. For complex questions, web search is available for models that support tool/function calling:
- **Native Search**: OpenAI, Claude, Gemini, and Grok use their built-in web search capabilities (enabled by default).
- **Tavily Search**: Mistral, Cohere, DeepSeek, and Ollama use the Tavily API when configured (requires a `TAVILY_API_KEY`).

You can also use the `From URL` feature to extract content from any website using Selenium-based web scraping, regardless of the provider.

Availability for this app follows the provider table at the top of this page.


### Chat Plus

![Chat app icon](../assets/icons/chat-plus.png ':size=40')

Engage in a "monadic" chat that reveals the AI's thought process. As the AI responds, it also provides structured metadata to add context to the conversation:

- **Reasoning**: The thought process behind the response.
- **Topics**: A list of topics discussed so far.
- **People**: A list of people mentioned in the conversation.
- **Notes**: Key points to remember during the conversation.


### Voice Chat :id=voice-chat

![Voice Chat app icon](../assets/icons/voice-chat.png ':size=40')

Chat with the AI using your voice. This app uses your provider's speech recognition API and your browser's speech synthesis API to create a voice-based conversation. The initial prompt is the same as the standard Chat app, and you can use different AI models for responses. A modern web browser that supports the Text to Speech API (like Google Chrome or Microsoft Edge) is required.

While the user is speaking, a waveform is displayed. When the user stops speaking, the probability value (p-value, 0 - 1) of the voice recognition result is displayed.

Voice Chat supports the same providers indicated in the availability table. You can freely mix any chat provider with any available TTS provider — for example, using Claude for the conversation while xAI Grok handles the voice. For speech input/output settings, see [Speech Settings Panel](./web-interface.md#speech-settings-panel).

**Expressive Speech**: When you enable Auto Speech and pick a compatible TTS provider, a small ✨ **Expressive Speech** badge appears under the Text-to-Speech Provider dropdown. Three mechanisms are supported, chosen automatically by the selected provider:

- **Inline markers** (xAI Grok, ElevenLabs v3): the assistant weaves short markers (brief pauses, laughter, a whispered aside) into the text, and the TTS engine interprets them as stage directions. The markers never surface in the chat transcript — only their audio effect does.
- **Instruction mode** (OpenAI `gpt-4o-mini-tts`): the assistant emits a separate voice directive — tone, pacing, emotion, pronunciation, pauses — alongside the reply. The OpenAI TTS engine reads the directive but does not speak it; the directive matches the mood of the reply and is invisible in the transcript.
- **Hybrid mode** (Gemini TTS): Gemini supports both of the above simultaneously. The assistant may use inline markers, a voice directive, or both, and Google's engine interprets the combination. Everything except the spoken reply is stripped from the transcript.

Hover the badge for a tooltip that describes the active mechanism. Turning off Auto Speech, or switching to a TTS provider without Expressive Speech support, silently disables the feature.

<!-- SCREENSHOT: Voice input interface showing waveform animation while speaking -->

The voice input feature displays a visual waveform while you speak. After stopping, it shows a confidence score (p-value) indicating the accuracy of speech recognition.

<!-- SCREENSHOT: Voice input after stopping, showing transcribed text with p-value confidence score -->


### Wikipedia

![Wikipedia app icon](../assets/icons/wikipedia.png ':size=40')

Ask questions about recent events or topics outside the AI's knowledge cutoff. This app functions like the standard Chat but automatically searches Wikipedia for answers when needed. If your query is in a language other than English, the app searches the English Wikipedia and translates the results back to your language.


### Math Tutor

![Math Tutor app icon](../assets/icons/math-tutor.png ':size=40')

Explore math-related questions and answers. The app uses [KaTeX](https://katex.org/) to render beautiful mathematical notation in its responses.

!> **Caution:** LLMs are known to struggle with calculations requiring multiple steps or complex logic and can produce incorrect results.  Double-check any mathematical output from this app, and if accuracy is critical, it is recommended to use the Code Interpreter app to perform the calculations.


### Second Opinion

![Second Opinion app icon](../assets/icons/second-opinion.png ':size=40')

Get a second opinion on any answer to ensure accuracy and gain diverse perspectives. First, ask your question to get an initial response. Then, ask the app to "double-check this answer," and it will consult a different AI provider to review and comment on the first response.

Second Opinion is available wherever the provider table lists support.


### Research Assistant

![Research Assistant app icon](../assets/icons/research-assistant.png ':size=40')

Accelerate your academic and scientific research with an intelligent assistant. This app uses powerful web search capabilities to retrieve and analyze information from online sources. Use it to find current information, verify facts, and research topics comprehensively, receiving reliable insights, summaries, and explanations to advance your work.

Research Assistant availability matches the provider table above. Web search capabilities:
- **Native Search**: OpenAI, Claude, Gemini, Grok (always available)
- **Tavily Search**: Mistral, Cohere, DeepSeek, Ollama (requires `TAVILY_API_KEY`)
- **URL Content Extraction**: Selenium-based web scraping for fetching content from any URL (available for all providers)

> **Note**: Gemini Research Assistant uses an internal web search agent (`gemini_web_search`) instead of native Google Search grounding. This enables web search to work alongside file operations and progress tracking, working around certain Gemini API limitations.

For more details, see the Chat app description above or [Reading Text from URLs](./message-input.md#reading-text-from-urls).


## Language Related :id=language-related

### Language Practice

![Language Practice app icon](../assets/icons/language-practice.png ':size=40')

Practice a new language in a conversation that starts with the assistant speaking to you. The assistant's speech is played via speech synthesis. To respond, press the Enter key to start your speech input and press it again to end.


Language Practice supports the providers indicated in the availability table. For speech synthesis settings, see [Speech Settings Panel](./web-interface.md#speech-settings-panel).


### Language Practice Plus

![Language Practice Plus app icon](../assets/icons/language-practice-plus.png ':size=40')

Take your language learning a step further. This app functions like the standard Language Practice app, but adds linguistic advice (as text) to each of the assistant's responses, helping you improve your skills as you converse.


### Translate

![Translate app icon](../assets/icons/translate.png ':size=40')

Translate text into another language. The assistant will first ask for the target language. You can also guide the translation of specific phrases by enclosing the original text in parentheses and providing your desired translation right after it, like `(original text)desired translation`.

Translate is available for the providers marked in the availability table. Specific language coverage depends on each provider's multilingual support.


### Voice Interpreter

![Voice Interpreter app icon](../assets/icons/voice-chat.png ':size=40')

Translate your voice input into another language and hear the translation spoken aloud. The assistant will first ask for the target language, then translate what you say and speak the result using speech synthesis.

Voice Interpreter follows the provider availability shown in the table above. For speech synthesis settings, see [Speech Settings Panel](./web-interface.md#speech-settings-panel).


## Content Generation :id=content-generation

### Novel Writer

![Novel Writer app icon](../assets/icons/novel-writer.png ':size=40')

Co-write a novel with the assistant. The story unfolds based on your prompts, maintaining consistency and flow. The AI will first ask for the story's setting, characters, and genre. You can then provide prompts to guide the AI as it continues the story.


### Image Generator





![Image Generator app icon](../assets/icons/image-generator.png ':size=40')





Generate images from text descriptions. Image Generator is available with OpenAI, Google Gemini, and xAI (Grok). With providers that support advanced image workflows, you can perform three main operations:





1.  **Image Generation**: Create new images from text.


2.  **Image Editing**: Modify existing images using text prompts. The system automatically uses images you upload or images generated in the current conversation for editing.


3.  **Image Variation**: Generate alternative versions of an existing image, automatically referencing the latest image in the conversation.





With supported models, the image editing feature allows you to:


- Automatically use an existing image from the conversation as a base (latest uploaded or generated)


- Provide text instructions for the changes (prompt-based editing)


- Customize output options including:


  - Image size and quality


  - Output format (PNG, JPEG, WebP)


  - Background transparency


  - Compression level


### Image Editing

To edit an existing image, simply describe the changes you want in natural language. The model will modify the image based on your prompt while preserving the overall composition. Image editing is supported by OpenAI, Google Gemini, and xAI (Grok).

For example, after generating an image, you can say:
- "Make the sky a sunset orange"
- "Add a cat sitting in the window"
- "Change the sign to read 'Hello World'"

The model interprets your instructions and applies changes to the entire image contextually. You can also upload an image and provide editing instructions to modify it.

All generated images are saved in the `Shared Folder` and also displayed in the chat.

### Video Generator

![Video Generator app icon](../assets/icons/video-generator.png ':size=40')

Create videos using state-of-the-art AI models. This app supports both text-to-video and image-to-video generation with different aspect ratios and durations, intelligently leveraging session context for continuous workflows.

Some providers offer both fast and high-quality models. If you prefer higher quality, use keywords like "high quality" or "production" in your request.

**Key Features:**
-   **Text-to-video generation**: Create videos from text descriptions
-   **Image-to-video generation**: Animate existing images by using them as the first frame, automatically detecting uploaded images from the conversation session.
-   **Remix**: Modify existing videos with new prompts (supported by some providers), automatically referencing the last generated video from the conversation session.
-   **Multiple aspect ratios**: Choose between landscape and portrait formats

**Usage:**
1. For text-to-video: Provide a detailed description of the video you want to create
   - Include shot type, subject, action, setting, lighting, and camera movement
2. For image-to-video: Upload an image and describe how it should be animated; the system will automatically use the uploaded image from the session.
3. For remix (supported by some providers): After generating a video, simply request modifications (e.g., "make it longer") without re-specifying the video ID; the system will use the last generated video.
4. Specify quality preferences if needed by using keywords in your prompt

?> **Note:** Generated videos are saved in the `Shared Folder` and displayed in the chat interface.

**Example requests:**
- "Create a video of a sunset over mountains" → text-to-video generation
- "Create a high-quality marketing video" → text-to-video with high-quality model
- "Turn this image into a video of waves gently moving" → image-to-video generation
- "Make the video more colorful" (after generating) → remix with modifications (supported by some providers)

Video Generator is available with the providers indicated in the availability table.


### Mail Composer

![Mail Composer app icon](../assets/icons/mail-composer.png ':size=40')

Draft emails in collaboration with the assistant. The AI will draft emails based on your requests and specifications.


Mail Composer supports each provider shown in the availability table.


### Mermaid Grapher

![Mermaid Grapher app icon](../assets/icons/diagram-draft.png ':size=40')

Visualize your data with [Mermaid.js](https://mermaid.js.org/) diagrams. Simply provide your data or instructions, and the AI will generate and render the appropriate Mermaid code for the diagram.

**Key Features:**
- **Live browser preview**: Diagrams render in a real browser visible via noVNC (`http://localhost:7900`), so you can watch changes in real time
- **Automatic diagram type selection**: The AI chooses the best diagram type for your data (flowchart, sequence, class, state, ER, Gantt, pie, Sankey, mindmap, etc.)
- **Real-time validation**: Diagrams are validated using Selenium and the actual Mermaid.js engine before being displayed
- **Visual self-verification**: The AI captures screenshots of rendered diagrams and visually inspects the output to catch layout issues or rendering errors before responding to the user
- **Error analysis**: When syntax errors occur, analyzes error patterns and provides fix suggestions
- **Preview generation**: A PNG preview image is saved to your shared folder for easy access
- **Web search integration**: Can fetch the latest Mermaid.js documentation and examples for unfamiliar diagram types

**Usage Tips:**
- Simply describe what you want to visualize, and the AI will create the appropriate diagram
- Open `http://localhost:7900` in a separate browser window (or use the noVNC menu item in Electron) to watch diagrams render live
- All preview images are saved as `mermaid_preview_[timestamp].png` in your shared folder

Mermaid Grapher supports each provider shown in the availability table.


### DrawIO Grapher

![DrawIO Grapher app icon](../assets/icons/diagram-draft.png ':size=40')

Create Draw.io diagrams by describing your requirements. The agent generates Draw.io XML, validates the structure, and renders a live preview in the browser via noVNC.

**Key Features:**
- **Live browser preview**: Diagrams render in a real browser visible via noVNC (`http://localhost:7900`), so you can watch changes in real time
- **Automatic XML validation and repair**: The agent validates the generated Draw.io XML and attempts to repair common structural issues
- **Wide diagram type support**: Flowcharts, UML diagrams (class, sequence, activity), ER diagrams, network diagrams, org charts, mind maps, BPMN, Venn diagrams, wireframes, and more
- **Visual self-verification**: The AI captures screenshots of rendered diagrams and visually inspects the output to catch layout issues or rendering errors before responding to the user
- **Preview generation**: A PNG preview image is saved to your shared folder for easy access
- **Downloadable .drawio files**: The generated `.drawio` file is saved to your shared folder and can be imported into Draw.io for further editing

**Usage Tips:**
- Simply describe the diagram you need, and the AI will create the appropriate Draw.io XML
- Open `http://localhost:7900` in a separate browser window (or use the noVNC menu item in Electron) to watch diagrams render live
- All preview images are saved as `drawio_preview_[timestamp].png` in your shared folder

DrawIO Grapher is available for the providers marked in the availability table. File generation fidelity depends on each provider's tooling support.


### Syntax Tree

![Syntax Tree app icon](../assets/icons/syntax-tree.png ':size=40')

Generate linguistic syntax trees from sentences in multiple languages. The app analyzes grammatical structure and creates visual tree diagrams using LaTeX and tikz-qtree. Key features include:

- Support for multiple languages, including English, Japanese, and Chinese.
- Editable SVG output for further modification in vector graphics editors.
- Professional linguistic notation that follows syntactic theory standards.

The generated syntax trees are displayed as SVG images with transparent backgrounds.


Syntax Tree availability matches the provider table.


### Concept Visualizer :id=concept-visualizer

![Concept Visualizer app icon](../assets/icons/diagram-draft.png ':size=40')

Visualize concepts and relationships by describing them in natural language. The app uses LaTeX/TikZ to create a wide variety of diagrams, including mind maps, flowcharts, network diagrams, and even 3D plots. Key features include:

- **Wide variety of diagram types**: Create mind maps, flowcharts, org charts, network diagrams, timelines, Venn diagrams, 3D visualizations, and more.
- **Natural language input**: Simply describe what you want to visualize.
- **Multiple domains**: Suitable for business, educational, scientific, and technical diagrams.
- **Multi-language support**: Handles text in various languages, including CJK (Chinese, Japanese, Korean).
- **Professional output**: Generates high-quality, editable SVG diagrams suitable for presentations and publications.
- **3D capabilities**: Supports 3D scatter plots, surfaces, and other three-dimensional visualizations.

The generated diagrams are saved to your shared folder and can be modified in any vector graphics editor.

Concept Visualizer supports the providers listed in the availability table.


### Speech Draft Helper

![Speech Draft Helper app icon](../assets/icons/speech-draft-helper.png ':size=40')

Draft speeches with the help of an AI assistant. You can ask the assistant to write a speech on a specific topic, or provide an existing draft (as plain text, a Word document, or a PDF) for it to improve. The final speech can be exported as an audio file in a format supported by your text-to-speech provider (e.g., MP3 or WAV).


## Content Analysis :id=content-analysis

### Web Insight :id=web-insight

Browse and capture web content with screenshots. When you provide a URL, the AI captures the page as viewport-sized screenshots. When interaction is needed (clicking, form filling, navigation), the AI opens a headless browser session and performs actions while returning screenshots for visual feedback.

**Key Features:**
- **Screenshot Capture**: Capture entire web pages as multiple viewport-sized images with automatic scrolling
- **Interactive Browsing**: The AI controls a headless Chrome browser — clicking links, filling forms, scrolling pages — and returns screenshots after each action
- **Customizable Viewports**: Desktop, tablet, mobile, and print presets
- **High Autonomy**: The AI operates with high autonomy, executing actions immediately without asking for confirmation at each step

**Interactive Browser Sessions:**

When you ask the AI to interact with a page, it starts a headless browser session in the Selenium container. The AI can click elements, type text, scroll pages, navigate between pages, and more — up to 20 actions per session. After each action, the AI receives a screenshot to verify the result.

When your instruction is ambiguous (e.g., "click the search button" when multiple candidates exist), the AI can annotate candidate elements with numbered labels on a screenshot and ask you to choose the correct one.

For live browser viewing, you can ask the AI to use non-headless mode. This enables real-time viewing via noVNC:

- **Electron app**: Open the noVNC window from **Open > Open noVNC** in the menu bar
- **Development mode**: Open `http://localhost:7900` in a separate browser tab

**Usage Examples:**
- `"Capture screenshots of https://github.com"` - Takes multiple screenshots
- `"Open https://example.com and click the About link"` - Interactive browsing
- `"Search for 'monadic chat' on Google"` - AI navigates and interacts with the page
- `"Take mobile screenshots of https://example.com"` - Uses mobile viewport preset

Web Insight is available with the providers marked in the availability table.


### Video Describer

![Video Describer app icon](../assets/icons/video-describer.png ':size=40')

Get a detailed description of any video's content. The app analyzes a video by extracting keyframes and audio, then uses the AI to describe the visual and auditory information.

To use this app, place a video file in the `Shared Folder`, provide its name, and specify the frames per second (fps) for the analysis.


### Knowledge Base

A unified, project-wide library of conversations and documents. The Knowledge Base is shared across every Monadic Chat app, so anything you save here can be retrieved later from any chat session.

The Knowledge Base replaces the previous PDF Navigator and Content Reader apps. Their functionality is consolidated into a single subsystem that handles conversation transcripts, PDFs, Office files, Markdown, and source code uniformly.

**Two ways to add content:**

1. **Save the current chat session** — the **Save** button in the sidebar serialises the active conversation (messages + participants + metadata) into the Knowledge Base.
2. **Import a file** — open the Knowledge Base Browser and click **Import file** to upload one of the supported formats below. The file is extracted, chunked, embedded, and stored as a single conversation entry that you can search, view, and rename.

**Supported import formats:**

| Format | Extensions | Notes |
|---|---|---|
| Markdown | `.md`, `.markdown`, `.mdx` | YAML frontmatter is promoted into metadata; ATX headings drive section boundaries. |
| Source code | `.rb`, `.py`, `.js` / `.ts`, `.go`, `.java`, `.kt`, `.swift`, `.rs`, `.c` / `.cpp`, `.cs`, `.php`, `.sh`, `.sql`, and others | Top-level `def`/`class`/`func`/etc. mark chunk boundaries. The programming language is recorded as a topic. |
| PDF | `.pdf` | Text and tables are extracted via pdfplumber and serialised as Markdown. PDF metadata title becomes the conversation title. |
| Office | `.docx`, `.xlsx`, `.pptx` | Word paragraphs, Excel sheets, and PowerPoint slides each become a chunk. The Browse modal shows a per-format icon (Word / Excel / PowerPoint). |

**Scope model:**

Each entry is scoped either to a specific app + provider (e.g. `Chat (OpenAI)`) or to `Global`. App-only entries are retrievable only from the same app + provider combination — `Chat (OpenAI)` cannot see entries saved while `Chat (Claude)` was active, and vice versa. `Global` entries are retrievable from every app via the `library_search` tool. Click the rotate icon in the Browse table or the **Make Global / Make app-only** button in the Conversation Viewer to flip between the two.

**Other features:**

- **Save replaces in place** — saving the same chat session a second time updates the existing entry instead of creating a duplicate. The modal switches to "Update Conversation in Knowledge Base" mode (with an "Update" button and a warning banner) when re-saving. The binding clears on Reset, app switch, or when the entry is deleted from Browse.
- **AI-suggested titles** — on first save the title field is auto-populated by your current provider's LLM, using the first few turns of the conversation. The suggestion is a default — type freely to override it. Suggestions are cached so canceling and re-opening the dialog does not re-run the model.
- **Rename** — open the Conversation Viewer, click the pencil icon next to the title, edit, and save. The Browse table updates immediately.
- **Inventory and stats** — the sidebar shows the most recent saves and total counts. The Browse modal supports search, filtering by scope, and sorting.
- **Conversation Viewer** — clicking a row opens a verbatim playback of every message, with system prompts collapsed behind a `<details>` block.
- **RAG opt-in (per session)** — the **Use Knowledge Base for retrieval** toggle in any chat session lets the LLM call `library_search` while answering. The cascade applies the active app's scope filter (`scope_app IN [current_app, "Global"]`). Off by default; locks for the duration of the session once you send the first message. The toggle preference is persisted across sessions so you don't have to flip it every time.
- **Privacy Filter compatibility** — when Privacy Filter is active, snippets returned by `library_search` are masked through the same Privacy Pipeline before they reach the LLM, so PII stored unmasked in the Knowledge Base does not leak via retrieval.

?> The Knowledge Base uses local embeddings (`multilingual-e5-base`) and a Qdrant vector store. Imports run inside the Python container (pdfplumber / python-docx / openpyxl / python-pptx); imported files are also persisted under `~/monadic/data/library/imports/` for traceability. For storage internals see the [Vector Database](../docker-integration/vector-database.md) documentation.


## Code Generation :id=code-generation

### Code Interpreter

![Code Interpreter app icon](../assets/icons/code-interpreter.png ':size=40')

Let the AI create and execute Python code in a sandboxed Docker environment. Any text data or images generated by the code are saved to your `Shared Folder` and displayed in the chat. The app intelligently maintains context of generated files, allowing you to implicitly reference and continue working with them across turns. You can also provide new files (like scripts or data) for the AI to use by placing them in the `Shared Folder` and referencing them by name in your messages.

?> **Note:** For matplotlib plots with Japanese text, the Python container includes Japanese font support (Noto Sans CJK JP) configured through matplotlibrc.

When the code generates plot images, the AI can visually verify the rendered output to detect issues such as garbled text, overlapping labels, or data inconsistencies, and automatically fix and re-execute the code if needed.

Code Interpreter availability matches the provider table. Provider tool-calling specifications may vary, which can affect behavior.


### Coding Assistant

![Coding Assistant app icon](../assets/icons/coding-assistant.png ':size=40')

Work with an AI assistant that functions as a professional software engineer. It supports code creation, file reading/writing, project management, and other development tasks.

**Key Features:**
- Code generation and editing
- File read/write operations in Shared Folder (write/append mode support)
- Directory file listing
- Support for complex coding tasks

?> **Note:** Code Interpreter can execute Python code, while Coding Assistant specializes in code generation and file operations without code execution.

Coding Assistant supports the providers indicated in the availability table.


### Jupyter Notebook :id=jupyter-notebook

![Jupyter Notebook app icon](../assets/icons/jupyter-notebook.png ':size=40')

Let the AI create Jupyter Notebooks, add cells, and execute code based on your requests. The app intelligently maintains context of the current notebook, allowing you to seamlessly continue editing and running code in the same notebook across multiple turns. The code runs in a sandboxed Python environment inside a Docker container, and the created notebook is saved to your `Shared Folder`. When cells produce plot images, the AI can visually verify the output and fix issues before presenting results.

?> You can start or stop JupyterLab by asking the AI agent. Alternatively, you can use the `Start JupyterLab` or `Stop JupyterLab` menu items in the `Console Panel` menu bar.
<br /><br /><!-- SCREENSHOT: Monadic Chat Actions menu showing Start JupyterLab and Stop JupyterLab options -->

?> **Note:** For Server Mode restrictions, see [Web Interface - Server Mode](./web-interface.md#server-mode).

Jupyter Notebook is available for the providers shown in the availability table.


### Monadic Chat Help

![Help app icon](../assets/icons/help.png ':size=40')

Get help with Monadic Chat from this AI-powered assistant. It provides contextual assistance based on the project's official documentation, answering questions about features, usage, and troubleshooting in any language.

The help system uses a pre-built knowledge base created from the English documentation. When you ask a question, it searches this knowledge base to provide an accurate, relevant answer. For more details on the architecture, see the [Help System](../advanced-topics/help-system.md) documentation.


## Specialized Apps :id=specialized-apps

### Auto Forge (Artifact Builder) :id=auto-forge

![Auto Forge app icon](../assets/icons/auto-forge.png ':size=40')

Create complete web applications and command-line tools autonomously through AI orchestration. Auto Forge (marketed as "Artifact Builder") generates single-file HTML applications or standalone scripts without external dependencies.

**Key Features:**
- **Autonomous planning**: AI analyzes requirements and creates detailed implementation plans
- **Single-file output**: Web apps ship as a single HTML file; CLI tools as standalone scripts
- **Project management**: Automatic organization with timestamps and Unicode name support
- **Optional debugging**: Selenium-based automated testing for web applications

For detailed documentation, see [Auto Forge](../apps/auto_forge.md).

Auto Forge is available for the providers shown in the availability table.


### Music Lab :id=music-lab

![Music Lab app icon](../assets/icons/music.png ':size=40')

An interactive lab for learning music theory hands-on: play chords, scales, intervals, and progressions, and generate backing tracks to hear concepts in action. The AI explains music concepts and renders audio examples directly in the browser. To evaluate the musicality and performance of an existing recording, use the Music Analyst app instead.

**Key Features:**
- **Audio/MIDI analysis**: Upload audio files (mp3, wav, m4a, ogg, flac) or MIDI files (mid, midi) to detect tempo, key, time signature, chord progressions, and song structure. MIDI analysis also extracts track/instrument information.
- **Audio playback**: Chords, scales, intervals, and progressions rendered as sheet music with in-browser MIDI synthesis
- **Backing tracks**: Multi-instrument backing tracks (chords + bass) with style-specific patterns (jazz, bossa nova, pop, rock, ballad)
- **Algorithmic melody**: Generate melodies automatically using chord-scale theory, Euclidean rhythms, and contour shaping (lyrical, rhythmic, jazz, latin, gentle styles)
- **Guitar-specific patterns**: Bossa nova arpeggios, rock power chords, ballad fingerpicking
- **Walking bass**: Jazz walking bass with chromatic approach notes, bossa 2-beat feel
- **Comprehensive music theory**: 46 chord types, 15 scales, all church modes, slash chords, enharmonic spelling

Audio analysis requires the optional **Audio Analysis** package (librosa + madmom) — enable it in **Actions → Install Options** and rebuild the Python container.

Music Lab is available for OpenAI, Claude, Gemini, and Grok.

### Music Analyst :id=music-analyst

![Music Analyst app icon](../assets/icons/music.png ':size=40')

Evaluate a recorded performance from two complementary angles: objective measured features and an interpretive critique of the music and playing. To play, generate, and learn music theory hands-on, use the Music Lab app.

**Key Features:**
- **Objective features**: Extract tempo, key, time signature, chord progression, and song structure from an uploaded audio or MIDI file via signal processing.
- **Interpretive critique**: Gemini listens to the audio and comments on character and mood, genre and instrumentation, and performance qualities (expression, dynamics, phrasing, timing, energy), with strengths, weaknesses, and an overall evaluation.
- **Complementary lenses**: Ask for objective facts, an interpretive critique, or both — the two are presented as clearly separated sections.

The interpretive critique analyzes audio in mono at reduced bandwidth, so it does not judge audio fidelity, mix/mastering, or stereo imaging; exact tempo and key come from the objective feature analysis. Critique applies to real audio (mp3, wav, m4a, ogg, flac); MIDI files use objective analysis only.

Objective feature analysis requires the optional **Audio Analysis** package (librosa + madmom) — enable it in **Actions → Install Options** and rebuild the Python container.

Music Analyst is available for Gemini.

### Document Generator :id=document-generator

![Document Generator app icon](../assets/icons/document-generator.png ':size=40')

Generate Office documents using AI, including Excel spreadsheets, PowerPoint presentations, Word documents, and PDFs. Files are automatically saved to your shared folder.

**Key Features:**
- **Excel (.xlsx)**: Data tables, charts, formulas, multiple sheets
- **PowerPoint (.pptx)**: Professional slides with visual layouts
- **Word (.docx)**: Formatted documents with headings, lists, tables
- **PDF**: Professional documents with proper formatting

Document Generator is currently available for Claude.


