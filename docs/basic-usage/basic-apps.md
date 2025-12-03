# Basic Apps

The following basic apps are available. You can select any of the basic apps and adjust the behavior of the AI agent by changing parameters or rewriting the initial prompt. The adjusted settings can be exported/imported to/from an external JSON file.

Most basic apps support multiple AI providers. See the table below for specific app availability by provider.

For information on how to develop your own apps, refer to the [App Development](../advanced-topics/develop_apps.md) section.

## App Availability by Provider :id=app-availability

The table below shows which apps are available for which AI model providers.


| App | OpenAI | Claude | Cohere | DeepSeek | Google Gemini | xAI Grok | Mistral | Perplexity | Ollama |
|-----|:------:|:------:|:------:|:--------:|:------:|:----:|:-------:|:----------:|:------:|
| Chat | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Chat Plus | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Voice Chat | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | |
| Wikipedia | ✅ | | | | | | | | |
| Math Tutor | ✅ | ✅ | | | ✅ | ✅ | | | |
| Second Opinion | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Research Assistant | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | |
| Language Practice | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | |
| Language Practice Plus | ✅ | | | | | | | | |
| Translate | ✅ | | ✅ | | | | | | |
| Voice Interpreter | ✅ | | ✅ | | | | | | |
| Novel Writer | ✅ | | | | | | | | |
| Image Generator | ✅ | | | | ✅ | ✅ | | | |
| Video Generator | ✅ | | | | ✅ | | | | |
| Mail Composer | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | |
| Mermaid Grapher | ✅ | | | | | | | | |
| DrawIO Grapher | ✅ | ✅ | | | | | | | |
| Syntax Tree | ✅ | ✅ | | | | | | | |
| Concept Visualizer | ✅ | ✅ | | | | | | | |
| Speech Draft Helper | ✅ | | | | | | | | |
| Visual Web Explorer | ✅ | ✅ | | | ✅ | ✅ | | | |
| Video Describer | ✅ | | | | | | | | |
| PDF Navigator | ✅ | | | | | | | | |
| Content Reader | ✅ | | | | | | | | |
| Code Interpreter | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | | |
| Coding Assistant | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | |
| Jupyter Notebook | ✅ | ✅ | | | ✅ | ✅ | | | |
| Monadic Chat Help | ✅ | | | | | | | | |

## Provider Capabilities Overview

| Provider | Vision Support | Tool/Function Calling | Web Search |
|----------|----------------|----------------------|------------|
| OpenAI | ✅ | ✅ | ✅ Native |
| Claude | ✅ | ✅ | ✅ Native |
| Gemini | ✅ | ✅ | ✅ Native |
| Mistral | ✅ | ✅ | ✅ Tavily |
| Cohere | ✅ | ✅ | ✅ Tavily |
| xAI Grok | ✅ | ✅ | ✅ Native |
| Perplexity | ✅ | ❌ | ✅ Native |
| DeepSeek | ❌ | ✅ | ✅ Tavily |
| Ollama | Model-dependent | Model-dependent | ✅ Tavily |

## Assistant :id=assistant

### Chat

![Chat app icon](../assets/icons/chat.png ':size=40')

Start a standard conversation with the AI, which will respond to your text with appropriate emojis. For complex questions, web search is available for models that support tool/function calling:
- **Native Search**: OpenAI, Claude, Gemini, Grok, and Perplexity use their built-in web search capabilities (enabled by default).
- **Tavily Search**: Mistral, Cohere, DeepSeek, and Ollama use the Tavily API when configured (requires a `TAVILY_API_KEY`).

You can also use the `From URL` feature to extract content from any website using Selenium-based web scraping, regardless of the provider.

<!-- > 📸 **Screenshot needed**: Chat app interface showing a conversation with emojis -->

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

![Voice input](../assets/images/voice-input-stop.png ':size=400')

While the user is speaking, a waveform is displayed. When the user stops speaking, the probability value (p-value, 0 - 1) of the voice recognition result is displayed.

![Voice p-value](../assets/images/voice-p-value.png ':size=400')


Voice Chat supports the same providers indicated in the availability table. For speech input/output settings, see [Speech Settings Panel](./web-interface.md#speech-settings-panel).

### Wikipedia

![Wikipedia app icon](../assets/icons/wikipedia.png ':size=40')

Ask questions about recent events or topics outside the AI's knowledge cutoff. This app functions like the standard Chat but automatically searches Wikipedia for answers when needed. If your query is in a language other than English, the app searches the English Wikipedia and translates the results back to your language.

### Math Tutor

![Math Tutor app icon](../assets/icons/math-tutor.png ':size=40')

Explore math-related questions and answers. The app uses [MathJax](https://www.mathjax.org/) to render beautiful mathematical notation in its responses.

!> **Caution:** LLMs are known to struggle with calculations requiring multiple steps or complex logic and can produce incorrect results.  Double-check any mathematical output from this app, and if accuracy is critical, it is recommended to use the Code Interpreter app to perform the calculations.

### Second Opinion

![Second Opinion app icon](../assets/icons/second-opinion.png ':size=40')

Get a second opinion on any answer to ensure accuracy and gain diverse perspectives. First, ask your question to get an initial response. Then, ask the app to "double-check this answer," and it will consult a different AI provider to review and comment on the first response.

Second Opinion is available wherever the provider table lists support.

### Research Assistant

![Research Assistant app icon](../assets/icons/research-assistant.png ':size=40')

Accelerate your academic and scientific research with an intelligent assistant. This app uses powerful web search capabilities to retrieve and analyze information from online sources. Use it to find current information, verify facts, and research topics comprehensively, receiving reliable insights, summaries, and explanations to advance your work.

Research Assistant availability matches the provider table above. Web search capabilities:
- **Native Search**: OpenAI, Claude, Gemini, Grok, Perplexity (always available)
- **Tavily Search**: Mistral, Cohere, DeepSeek, Ollama (requires `TAVILY_API_KEY`)
- **URL Content Extraction**: Selenium-based web scraping for fetching content from any URL (available for all providers)

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





Generate images from text descriptions. With providers that support advanced image workflows, you can perform three main operations:





1.  **Image Generation**: Create new images from text.


2.  **Image Editing**: Modify existing images using text prompts and masks. The system automatically uses images you upload or images generated in the current conversation for editing.


3.  **Image Variation**: Generate alternative versions of an existing image, automatically referencing the latest image in the conversation.





With supported models, the image editing feature allows you to:


- Automatically use an existing image from the conversation as a base (latest uploaded or generated)


- Create mask images to specify areas to modify


  - Click the mask button on uploaded images


  - Draw on the image to select editing areas


- Provide text instructions for the changes


- Customize output options including:


  - Image size and quality


  - Output format (PNG, JPEG, WebP)


  - Background transparency


  - Compression level

### Creating and Using Masks

When editing images, you can create a mask to specify which areas of the image should be modified:

#### Original Image

Here's an example of an original image that we want to edit:

![Original Image](../assets/images/origina-image.jpg ':size=400')

#### Creating a Mask

1. **Open the Mask Editor**: After uploading an image, click on it and select "Create Mask" from the menu

2. **Draw the Mask**: Use the brush tool to paint over areas you want AI to edit (white areas)
   - Use the eraser tool to remove parts of the mask
   - Adjust brush size using the slider
   - Black areas will be preserved, white areas will be edited

![Image Masking](../assets/images/image-masking.png ':size=500')

3. **Save the Mask**: Click "Save Mask" when finished
4. **Apply the Mask**: The mask will be automatically applied to your next image edit operation

The mask editor provides intuitive controls:
- Brush/Eraser toggle buttons
- Adjustable brush size
- Clear mask button
- Preview of the original image underneath the mask

#### Result After Editing

After applying the mask and providing edit instructions, you'll get a result like this:

![Edit Result](../assets/images/image-edit-result.png ':size=400')

The editing process preserves the original image's composition and details while applying your requested changes only to the specified areas marked by your mask.

All generated images are saved in the `Shared Folder` and also displayed in the chat.

Image Generator is available with the providers indicated in the availability table.

### Video Generator

![Video Generator app icon](../assets/icons/video-generator.png ':size=40')

Create videos using state-of-the-art AI models. This app supports both text-to-video and image-to-video generation with different aspect ratios and durations, intelligently leveraging session context for continuous workflows.

Some providers offer both fast and high-quality models. If you prefer higher quality, use keywords like "high quality" or "production" in your request.

**Key Features:**
-   **Text-to-video generation**: Create videos from text descriptions
-   **Image-to-video generation**: Animate existing images by using them as the first frame, automatically detecting uploaded images from the conversation session.
-   **Remix**: Modify existing videos with new prompts (OpenAI Sora 2 only), automatically referencing the last generated video from the conversation session.
-   **Multiple aspect ratios**: Choose between landscape and portrait formats

**Usage:**
1. For text-to-video: Provide a detailed description of the video you want to create
   - Include shot type, subject, action, setting, lighting, and camera movement
2. For image-to-video: Upload an image and describe how it should be animated; the system will automatically use the uploaded image from the session.
3. For remix (OpenAI Sora 2 only): After generating a video, simply request modifications (e.g., "make it longer") without re-specifying the video ID; the system will use the last generated video.
4. Specify quality preferences if needed by using keywords in your prompt

?> **Note:** Generated videos are saved in the `Shared Folder` and displayed in the chat interface.

**Example requests:**
- "Create a video of a sunset over mountains" → text-to-video generation
- "Create a high-quality marketing video" → text-to-video with high-quality model
- "Turn this image into a video of waves gently moving" → image-to-video generation
- "Make the video more colorful" (after generating) → remix with modifications (OpenAI Sora 2 only)

Video Generator is available with the providers indicated in the availability table.

### Mail Composer

![Mail Composer app icon](../assets/icons/mail-composer.png ':size=40')

Draft emails in collaboration with the assistant. The AI will draft emails based on your requests and specifications.


Mail Composer supports each provider shown in the availability table.

### Mermaid Grapher

![Mermaid Grapher app icon](../assets/icons/diagram-draft.png ':size=40')

Visualize your data with [Mermaid.js](https://mermaid.js.org/) diagrams. Simply provide your data or instructions, and the AI will generate and render the appropriate Mermaid code for the diagram.

**Key Features:**
- **Automatic diagram type selection**: The AI chooses the best diagram type for your data (flowchart, sequence, class, state, ER, Gantt, pie, Sankey, mindmap, etc.)
- **Real-time validation**: Diagrams are validated using Selenium and the actual Mermaid.js engine before being displayed
- **Error analysis**: When syntax errors occur, analyzes error patterns and provides fix suggestions
- **Preview generation**: A PNG preview image is saved to your shared folder for easy access
- **Web search integration**: Can fetch the latest Mermaid.js documentation and examples for unfamiliar diagram types

**Usage Tips:**
- Simply describe what you want to visualize, and the AI will create the appropriate diagram
- All preview images are saved as `mermaid_preview_[timestamp].png` in your shared folder


### DrawIO Grapher

![DrawIO Grapher app icon](../assets/icons/diagram-draft.png ':size=40')

Create Draw.io diagrams by describing your requirements. The agent will generate a Draw.io XML file that you can download, import into Draw.io, and edit further. It supports various diagram types, including flowcharts, UML, ER diagrams, and more. The generated `.drawio` file is saved to your shared folder.


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

### Visual Web Explorer :id=visual-web-explorer

Capture web pages as screenshots or extract their text content into Markdown. This app is perfect for creating documentation, archiving web content, or analyzing a page's structure and text.

**Key Features:**
- **Screenshot Mode**: Capture entire web pages as multiple viewport-sized images with automatic scrolling
- **Text Extraction Mode**: Convert web content to clean Markdown format
- **Image Recognition Option**: When HTML parsing is difficult, image recognition mode enables text extraction using each provider's vision API
- **Customizable Viewports**: Desktop, tablet, mobile, and print presets
- **Overlap Control**: Configure overlap between screenshots for seamless reading
- **Automatic Naming**: Files are named with domain and timestamp

**Usage Examples:**
- `"Capture screenshots of https://github.com"` - Takes multiple screenshots
- `"Extract text from https://example.com"` - Converts to Markdown
- `"Extract text from https://example.com with image recognition"` - Uses vision API when needed
- `"Take mobile screenshots of https://example.com"` - Uses mobile viewport preset

Visual Web Explorer is available with the providers marked in the availability table.

### Video Describer

![Video Describer app icon](../assets/icons/video-describer.png ':size=40')

Get a detailed description of any video's content. The app analyzes a video by extracting keyframes and audio, then uses the AI to describe the visual and auditory information.

To use this app, place a video file in the `Shared Folder`, provide its name, and specify the frames per second (fps) for the analysis.


### PDF Navigator

![PDF Navigator app icon](../assets/icons/pdf-navigator.png ':size=40')

Ask questions about the content of your PDF files. After you upload a PDF, the app divides the content into smaller segments and creates text embeddings for each. When you ask a question, the app finds the most relevant segment and provides it to the AI to generate a well-informed answer.

**Key Features:**
- **Vector database integration**: Properly connects to PGVector database through the `@embeddings_db` instance variable
- **Multiple search methods**: Can find closest text snippets, documents, or retrieve specific segments
- **Document management**: List all uploaded PDFs and navigate through different documents
- **Contextual retrieval**: Finds the most relevant text segments based on semantic similarity

**Available Functions:**
- `find_closest_text`: Search for text snippets most similar to your query
- `find_closest_doc`: Find entire documents most relevant to your query
- `list_titles`: View all PDFs currently in the database
- `get_text_snippet`: Retrieve a specific text segment by position
- `get_text_snippets`: Get all text segments from a specific document

?> The PDF Navigator app uses [PyMuPDF](https://pymupdf.readthedocs.io/en/latest/) to extract text from PDF files and the text data and its embeddings are stored in [PGVector](https://github.com/pgvector/pgvector) database (database name: `monadic_user_docs`). The app now properly connects to the vector database using the `pdf_vector_storage` feature flag, ensuring reliable access to your PDF content. For detailed information about the vector database implementation, see the [Vector Database](../docker-integration/vector-database.md) documentation. For information about storage mode options (local vs. cloud), see [PDF Storage](./pdf_storage.md).

**Configuration Options:**

PDF Navigator behavior can be customized via environment variables in `~/monadic/config/env`:

- `PDF_RAG_TOKENS`: Number of tokens per chunk
- `PDF_RAG_OVERLAP_LINES`: Number of lines to overlap between chunks


![PDF button](../assets/images/app-pdf.png ':size=700')


![Import PDF](../assets/images/import-pdf.png ':size=400')

![PDF DB Panel](../assets/images/monadic-chat-pdf-db.png ':size=400')

### Content Reader

![Content Reader app icon](../assets/icons/content-reader.png ':size=40')

Have an AI chatbot explain the content of files or web URLs in a clear, beginner-friendly way. You can upload files (like PDFs, Word documents, or code) or simply mention a URL in your prompt, and the app will automatically retrieve the content for the AI to discuss.

To specify a file for the AI to read, save the file in the `Shared Folder` and specify the file name in the User message. If the AI cannot find the file, verify the file name and ensure it's accessible from the current code execution environment.

Supported file formats:

- PDF
- Microsoft Word (docx)
- Microsoft PowerPoint (pptx)
- Microsoft Excel (xlsx)
- CSV
- Text (txt)

The app can also recognize and describe image files (PNG, JPEG, etc.). Image recognition uses the vision capability of the currently selected model (automatically falls back to a vision-capable model if needed). Additionally, audio files (MP3, etc.) can be transcribed to text. Speech recognition uses the STT model selected in the Speech Settings Panel of the Web UI.


## Code Generation :id=code-generation

### Code Interpreter

![Code Interpreter app icon](../assets/icons/code-interpreter.png ':size=40')

Let the AI create and execute Python code in a sandboxed Docker environment. Any text data or images generated by the code are saved to your `Shared Folder` and displayed in the chat. The app intelligently maintains context of generated files, allowing you to implicitly reference and continue working with them across turns. You can also provide new files (like scripts or data) for the AI to use by placing them in the `Shared Folder` and referencing them by name in your messages.

?> **Note:** For matplotlib plots with Japanese text, the Python container includes Japanese font support (Noto Sans CJK JP) configured through matplotlibrc.

<!-- > 📸 **Screenshot needed**: Code Interpreter showing code execution with output and generated plots -->

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

Let the AI create Jupyter Notebooks, add cells, and execute code based on your requests. The app intelligently maintains context of the current notebook, allowing you to seamlessly continue editing and running code in the same notebook across multiple turns. The code runs in a sandboxed Python environment inside a Docker container, and the created notebook is saved to your `Shared Folder`.

?> You can start or stop JupyterLab by asking the AI agent. Alternatively, you can use the `Start JupyterLab` or `Stop JupyterLab` menu items in the `Console Panel` menu bar.
<br /><br />![Action menu](../assets/images/jupyter-start-stop.png ':size=190')

<!-- > 📸 **Screenshot needed**: Jupyter Notebook app showing notebook creation and cell execution -->

?> **Note:** For Server Mode restrictions, see [Web Interface - Server Mode](./web-interface.md#server-mode).

Jupyter Notebook is available for the providers shown in the availability table.

### Monadic Chat Help

![Help app icon](../assets/icons/help.png ':size=40')

Get help with Monadic Chat from this AI-powered assistant. It provides contextual assistance based on the project's official documentation, answering questions about features, usage, and troubleshooting in any language.

The help system uses a pre-built knowledge base created from the English documentation. When you ask a question, it searches this knowledge base to provide an accurate, relevant answer. For more details on the architecture, see the [Help System](../advanced-topics/help-system.md) documentation.
