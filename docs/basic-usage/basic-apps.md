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

A blank cell in **both** columns indicates an artifact-centric app where the generated output (image, video, diagram, document, etc.) is the value, not the conversation. Use the per-card **Copy** / **Download** controls or the shared folder to retain artifacts; KB save is intentionally not available because the surrounding chat does not carry retrieval value.

## Provider Capabilities Overview :id=provider-capabilities

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

## App Categories

Each app is documented in detail on its own page. Follow the links below for descriptions, key features, and usage tips.

### Chat & Assistant Apps

General-purpose conversation apps, from standard and voice chat to math tutoring, second opinions, web-based research, and the built-in documentation assistant. See [Chat & Assistant Apps](../apps/chat-apps.md).

- Chat
- Chat Plus
- Voice Chat
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

Generate images from text descriptions, edit existing images with natural-language instructions, and create image variations. See [Image Generator](../apps/image-generator.md).

### Video Generator

Create videos from text descriptions or existing images, with remix support for modifying generated videos. See [Video Generator](../apps/video-generator.md).

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

A unified, project-wide library of saved conversations and imported documents (PDF, Office, Markdown, source code) that every app can retrieve from. See [Knowledge Base](../apps/knowledge-base.md).

### Coding & Notebook Apps

Write and execute code in a sandboxed Docker environment, manage files in the shared folder, and build Jupyter Notebooks. See [Coding & Notebook Apps](../apps/coding-apps.md).

- Code Interpreter
- Coding Assistant
- Jupyter Notebook

### Music Lab & Music Analyst

Learn music theory hands-on with playable examples and backing tracks, and evaluate recorded performances with measured features and interpretive critique. See [Music Lab & Music Analyst](../apps/music-apps.md).

- Music Lab
- Music Analyst

### AutoForge / Artifact Builder

Autonomous web-app generation: builds complete single-file web applications and CLI tools through AI orchestration. See [AutoForge / Artifact Builder](../apps/auto_forge.md).
