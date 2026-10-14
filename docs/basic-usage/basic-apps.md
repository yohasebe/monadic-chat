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
| Live Conversation | ✅ | | | | ✅ | ✅ | | |
| Wikipedia | ✅ | | | | | | | |
| Math Tutor | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | |
| Second Opinion | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | |
| Research Assistant | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | |
| Language Practice | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Language Practice Plus | ✅ | ✅ | | | | | | |
| Translate | ✅ | | ✅ | ✅ | | | | |
| Voice Interpreter | ✅ | | ✅ | | | | | |
| Novel Writer | ✅ | | | ✅ | | | ✅ | |
| Image Generator | ✅ | | | | ✅ | ✅ | | |
| Video Generator | | | | | ✅ | ✅ | | |
| Music Generator | | | | | ✅ | | | |
| Mail Composer | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Mermaid Grapher | ✅ | ✅ | | | ✅ | ✅ | | |
| DrawIO Grapher | ✅ | ✅ | | | ✅ | ✅ | | |
| Syntax Tree | ✅ | ✅ | | | | | | |
| Concept Visualizer | ✅ | ✅ | | | | | | |
| Speech Draft Helper | ✅ | | | | | | | |
| Web Insight | ✅ | ✅ | | | ✅ | ✅ | | |
| Video Describer | ✅ | | | | ✅ | ✅ | | |
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

An app supports either the Privacy Filter (PF) or saving to the Knowledge Base (KB), not both. Apps that create images, videos, diagrams, music or documents support neither: their output is saved in the shared folder (`~/monadic/data`).

To keep a conversation that used the Privacy Filter, click the Privacy indicator in the top bar and use **Export this conversation** (it can be encrypted, and masked). To see what is saved in the Knowledge Base, click **Browse** in the Knowledge Base panel.

| App | Privacy Filter | Knowledge Base Save |
|-----|:--:|:--:|
| Chat | | ✅ |
| Chat Plus | ✅ | |
| Voice Chat | | ✅ |
| Live Conversation | | ✅ |
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
| Music Generator | | |
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

A blank cell in **both** columns marks an app whose output (image, video, diagram, document, etc.) is saved as a file. Keep it with the controls on the message or from the shared folder.

## Provider Capabilities Overview :id=provider-capabilities

| Provider | Vision Support | Tool/Function Calling | Web Search |
|----------|----------------|----------------------|------------|
| OpenAI | ✅ | ✅ | ✅ Native |
| Claude | ✅ | ✅ | ✅ Native |
| Gemini | ✅ | ✅ | ✅ Native |
| Mistral | ✅ | ✅ | ✅ Tavily |
| Cohere | ✅ | ✅ | ✅ Tavily |
| xAI Grok | ✅ | ✅ | ✅ Native |
| DeepSeek | ✅ | ✅ | ✅ Tavily |
| Ollama | Model-dependent | Model-dependent | ✅ Tavily |

## App Categories

Each app is documented in detail on its own page. Follow the links below for descriptions, key features, and usage tips.

### Chat & Assistant Apps :id=chat-assistant-apps

General-purpose conversation apps, from standard and voice chat to math tutoring, second opinions, web-based research, and the built-in documentation assistant. See [Chat & Assistant Apps](../apps/chat-apps.md).

- Chat
- Chat Plus
- Voice Chat
- Live Conversation
- Wikipedia
- Math Tutor
- Second Opinion
- Research Assistant
- Monadic Chat Help

### Language Learning Apps

Apps for practicing languages in spoken conversation, translating text, and interpreting speech into another language. See [Language Learning Apps](../apps/language-apps.md).

- Language Practice
- Language Practice Plus
- Translate
- Voice Interpreter

### Writing & Document Apps

Apps for co-writing novels, drafting emails and speeches, and generating Office documents (Excel, PowerPoint, Word, PDF). See [Writing & Document Apps](../apps/writing-apps.md).

- Novel Writer
- Mail Composer
- Speech Draft Helper
- Document Generator

### Image Generator

Generate images from text descriptions, and edit images with natural-language instructions. See [Image Generator](../apps/image-generator.md).

### Video Generator

Create videos from text descriptions or from an image. See [Video Generator](../apps/video-generator.md).

### Music Generator

Generate music from text descriptions — full songs with vocals and lyrics, or fast instrumental clips. See [Music Generator](../apps/music-generator.md).

### Diagram & Visualization Apps

Create diagrams from natural-language descriptions using Mermaid.js, Draw.io, and LaTeX/TikZ, with live browser previews and visual self-verification. See [Diagram & Visualization Apps](../apps/diagram-apps.md).

- Mermaid Grapher
- DrawIO Grapher
- Syntax Tree
- Concept Visualizer

### Web & Media Analysis Apps

Capture and interact with web pages through a controlled browser, and analyze the visual and auditory content of videos. See [Web & Media Analysis Apps](../apps/analysis-apps.md).

- Web Insight
- Video Describer

### Knowledge Base

A unified, project-wide library of saved conversations and imported documents (PDF, Office, Markdown, source code). An entry is retrievable from the app that saved it, or, once it is scoped `Global`, from the other apps that search the Knowledge Base (with **Use Knowledge Base for retrieval (this session)** on). See [Knowledge Base](../apps/knowledge-base.md).

### Coding & Notebook Apps

Write and execute code in a sandboxed Docker environment, manage files in the shared folder, and build Jupyter Notebooks. See [Coding & Notebook Apps](../apps/coding-apps.md).

- Code Interpreter
- Coding Assistant
- Jupyter Notebook

### Music Lab & Music Analyst

Learn music theory hands-on with playable examples and backing tracks, and evaluate recorded performances with measured features and interpretive critique. See [Music Lab & Music Analyst](../apps/music-apps.md).

- Music Lab
- Music Analyst

### Auto Forge

Builds single-file web applications and command-line tools from your description. See [Auto Forge](../apps/auto_forge.md).
