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

This is a standard chat application. The AI responds to the text input by the user with appropriate emojis. Web search functionality is available for models that support tool/function calling. For providers with native web search support (OpenAI, Claude, Gemini, Grok, Perplexity), it is enabled by default. For other models, it is available when the Tavily API is configured.

<!-- > 📸 **Screenshot needed**: Chat app interface showing a conversation with emojis -->

Availability for this app follows the provider table at the top of this page.

### Chat Plus

![Chat app icon](../assets/icons/chat-plus.png ':size=40')

This is a chat application that is "monadic" and has additional features compared to the standard chat application. The AI responds to the user's text input and while doing so, it also provides additional information as follows:

- reasoning: The reasoning and thought process behind its response.
- topics: The list of topics discussed in the conversation so far.
- people: The list of people mentioned in the conversation so far.
- notes: The list of notes that should be remembered during the conversation.


### Voice Chat :id=voice-chat

![Voice Chat app icon](../assets/icons/voice-chat.png ':size=40')

This application allows you to chat using voice, utilizing the configured provider's speech recognition API together with the browser's speech synthesis API. The initial prompt is basically the same as the Chat app. The app can use different AI models to generate responses. A web browser that supports the Text to Speech API, such as Google Chrome or Microsoft Edge, is required.

![Voice input](../assets/images/voice-input-stop.png ':size=400')

While the user is speaking, a waveform is displayed. When the user stops speaking, the probability value (p-value, 0 - 1) of the voice recognition result is displayed.

![Voice p-value](../assets/images/voice-p-value.png ':size=400')


Voice Chat supports the same providers indicated in the availability table. For speech input/output settings, see [Speech Settings Panel](./web-interface.md#speech-settings-panel).

### Wikipedia

![Wikipedia app icon](../assets/icons/wikipedia.png ':size=40')

This is basically the same as Chat, but for questions about events that occurred after the language model's cutoff date, which the AI model cannot answer, it searches Wikipedia for answers. If the query is in a language other than English, the Wikipedia search is conducted in English, and the results are translated back into the original language.

### Math Tutor

![Math Tutor app icon](../assets/icons/math-tutor.png ':size=40')

This application responds using mathematical notation with [MathJax](https://www.mathjax.org/). It is suitable for math-related questions and answers.

!> **Caution:** LLMs are known to struggle with calculations requiring multiple steps or complex logic and can produce incorrect results.  Double-check any mathematical output from this app, and if accuracy is critical, it is recommended to use the Code Interpreter app to perform the calculations.

### Second Opinion

![Second Opinion app icon](../assets/icons/second-opinion.png ':size=40')

This app provides a two-step consultation process. **Step 1**: Ask your question and receive an initial answer from the AI. **Step 2**: Request verification by saying phrases like "Get a second opinion" or "Double-check this answer." The app will then consult another AI provider to review and comment on the initial response. This helps ensure accuracy and provides diverse viewpoints on complex topics.

Second Opinion is available wherever the provider table lists support.

### Research Assistant

![Research Assistant app icon](../assets/icons/research-assistant.png ':size=40')

This app is designed to support academic and scientific research by serving as an intelligent research assistant with powerful web search capabilities. It retrieves and analyzes information from online sources, helping you find current information, verify facts, and research topics comprehensively. The research assistant provides reliable and detailed insights, summaries, and explanations to advance your inquiries.

Research Assistant availability matches the provider table above. For details on web search functionality (native search, Tavily API, URL content extraction), see the Chat app description or [Reading Text from URLs](./message-input.md#reading-text-from-urls).

## Language Related :id=language-related

### Language Practice

![Language Practice app icon](../assets/icons/language-practice.png ':size=40')

This is a language learning application where the conversation starts with the assistant's speech. The assistant's speech is played back using speech synthesis. The user starts speech input by pressing the Enter key and ends it by pressing the Enter key again.


Language Practice supports the providers indicated in the availability table. For speech synthesis settings, see [Speech Settings Panel](./web-interface.md#speech-settings-panel).

### Language Practice Plus

![Language Practice Plus app icon](../assets/icons/language-practice-plus.png ':size=40')

This is a language learning application where the conversation starts with the assistant's speech, played back using speech synthesis.  The user starts and ends speech input by pressing the Enter key. In addition to the usual response, the assistant includes linguistic advice, presented as text, not speech.



### Translate

![Translate app icon](../assets/icons/translate.png ':size=40')

This app translates the user's input text into another language. First, the assistant asks for the target language. Then, it translates the input text into the specified language. If you want to specify how a particular phrase should be translated, enclose the relevant part of the input text in parentheses and provide the desired translation within the parentheses.

Translate is available for the providers marked in the availability table. Specific language coverage depends on each provider's multilingual support.


### Voice Interpreter

![Voice Interpreter app icon](../assets/icons/voice-chat.png ':size=40')

This app translates the user's voice input into another language and speaks the translation using speech synthesis. First, the assistant asks for the target language. Then, it translates the input text into the specified language.

Voice Interpreter follows the provider availability shown in the table above. For speech synthesis settings, see [Speech Settings Panel](./web-interface.md#speech-settings-panel).


## Content Generation :id=content-generation

### Novel Writer

![Novel Writer app icon](../assets/icons/novel-writer.png ':size=40')

This application is for co-writing novels with the assistant. The story unfolds based on the user's prompts, maintaining consistency and flow.  The AI agent first asks for the story's setting, characters, and genre.  The user can then provide prompts, and the AI agent will continue the story based on those prompts.


### Image Generator

![Image Generator app icon](../assets/icons/image-generator.png ':size=40')

This application generates images based on descriptions. When the selected provider supports advanced image workflows, the app can perform three main operations:

1. **Image Generation**: Create new images from text descriptions
2. **Image Editing**: Modify existing images using text prompts and optional masks
3. **Image Variation**: Generate alternative versions of an existing image

With supported models, the image editing feature allows you to:
- Select an existing image as a base
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

This application generates videos using state-of-the-art AI models. It supports both text-to-video and image-to-video generation with different aspect ratios and durations.

Some providers offer both fast and high-quality models. If you prefer higher quality, use keywords like "high quality" or "production" in your request.

**Key Features:**
- **Text-to-video generation**: Create videos from text descriptions
- **Image-to-video generation**: Animate existing images by using them as the first frame
- **Remix**: Modify existing videos with new prompts (OpenAI Sora 2 only)
- **Multiple aspect ratios**: Choose between landscape and portrait formats

**Usage:**
1. For text-to-video: Provide a detailed description of the video you want to create
   - Include shot type, subject, action, setting, lighting, and camera movement
2. For image-to-video: Upload an image to the shared folder and describe how it should be animated
3. For remix (OpenAI Sora 2 only): Request modifications after generating a video
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

This application is for drafting emails in collaboration with the assistant. The assistant drafts emails based on the user's requests and specifications.


Mail Composer supports each provider shown in the availability table.

### Mermaid Grapher

![Mermaid Grapher app icon](../assets/icons/diagram-draft.png ':size=40')

This application visualizes data using [mermaid.js](https://mermaid.js.org/). When you input any data or instructions, the agent generates Mermaid code for the appropriate diagram type and renders it.

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

This application helps you create Draw.io diagrams. Provide your requirements and the agent will generate a Draw.io XML file that you can download and import into Draw.io for further editing. It can create various diagram types including flowcharts, UML diagrams, entity-relationship diagrams, network diagrams, org charts, mind maps, BPMN diagrams, Venn diagrams, and wireframes. The generated .drawio file will be saved to the shared folder.


DrawIO Grapher is available for the providers marked in the availability table. File generation fidelity depends on each provider's tooling support.

### Syntax Tree

![Syntax Tree app icon](../assets/icons/syntax-tree.png ':size=40')

This application generates linguistic syntax trees from sentences in multiple languages. It analyzes the grammatical structure of sentences and creates visual tree diagrams using LaTeX and tikz-qtree. The app supports:

- Multiple languages including English, Japanese, Chinese, and other languages
- Editable SVG output that can be modified in vector graphics editors
- Professional linguistic notation following syntactic theory standards

The generated syntax trees are displayed as SVG images with transparent backgrounds.


Syntax Tree availability matches the provider table.

### Concept Visualizer :id=concept-visualizer

![Concept Visualizer app icon](../assets/icons/diagram-draft.png ':size=40')

This application visualizes various concepts and relationships through diagrams using LaTeX/TikZ. It can create mind maps, flowcharts, organizational charts, network diagrams, and many other types of visual representations based on natural language descriptions. The app supports:

- **Wide variety of diagram types**: Mind maps, flowcharts, organizational charts, network diagrams, timelines, Venn diagrams, 3D visualizations, and more
- **Natural language input**: Simply describe what you want to visualize in plain language
- **Multiple domains**: Business diagrams (SWOT, business models), educational diagrams (concept maps, learning paths), scientific diagrams (molecular structures, food webs, 3D plots), and technical diagrams (system architecture, UML)
- **Multi-language support**: Handles text in various languages including CJK (Chinese, Japanese, Korean)
- **Professional output**: Generates high-quality SVG diagrams suitable for presentations and publications
- **Customizable styling**: Appropriate colors, layouts, and visual elements for each diagram type
- **3D capabilities**: Supports 3D scatter plots, surfaces, and other three-dimensional visualizations

The generated diagrams are displayed as editable SVG images saved to the shared folder, which can be further modified in vector graphics editors.

Concept Visualizer supports the providers listed in the availability table.

### Speech Draft Helper

![Speech Draft Helper app icon](../assets/icons/speech-draft-helper.png ':size=40')

This application helps you draft speeches. You can ask the assistant to draft a speech based on a specific topic or provide a speech draft (plain text, Word, PDF) and ask the assistant to improve it. Audio export is available in the formats supported by the configured text-to-speech provider (for example, MP3 or WAV).


## Content Analysis :id=content-analysis

### Visual Web Explorer :id=visual-web-explorer

This application captures web pages as screenshots or extracts their text content in Markdown format. It's perfect for creating documentation, archiving web content, or analyzing page content.

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

This application analyzes video content and describes what is happening. The app extracts frames from the video, converts them into base64 PNG images, and extracts audio data, saving it as an MP3 file. Based on this information, the AI provides a description of the visual and audio content.

To use this app, store the video file in the `Shared Folder` and provide the file name.  Specify the frames per second (fps) for frame extraction.


### PDF Navigator

![PDF Navigator app icon](../assets/icons/pdf-navigator.png ':size=40')

This application reads PDF files and allows the assistant to answer user questions based on the content. Click the `Upload PDF` button to specify the file. The content of the file is divided into segments of the length specified by `max_tokens`, and text embeddings are calculated for each segment. Upon receiving input from the user, the text segment closest to the input sentence's text embedding value is passed to the AI along with the user's input, and a response is generated based on that content.

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

This application features an AI chatbot that examines and explains the content of provided files or web URLs in a clear, beginner-friendly manner.  Users can upload files or URLs containing various text data, including programming code. If a URL is mentioned in the prompt message, the app automatically retrieves and integrates the content into the conversation with the AI.

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

This application allows the AI to create and execute program code. The execution of the program uses a Python environment within a Docker container. Text data and images obtained as execution results are saved in the `Shared Folder` and also displayed in the chat.  If you have a file (such as Python code or CSV data) that you want the AI to read, save the file in the `Shared Folder` and specify the file name in the User message. If the AI cannot find the file location, please verify the file name and inform the message that it is accessible from the current code execution environment.

?> **Note:** For matplotlib plots with Japanese text, the Python container includes Japanese font support (Noto Sans CJK JP) configured through matplotlibrc.

<!-- > 📸 **Screenshot needed**: Code Interpreter showing code execution with output and generated plots -->

Code Interpreter availability matches the provider table. Provider tool-calling specifications may vary, which can affect behavior.

### Coding Assistant

![Coding Assistant app icon](../assets/icons/coding-assistant.png ':size=40')

An AI assistant that functions as a professional software engineer. Supports code creation, file reading/writing, project management, and other development tasks.

**Key Features:**
- Code generation and editing
- File read/write operations in Shared Folder (write/append mode support)
- Directory file listing
- Support for complex coding tasks

?> **Note:** Code Interpreter can execute Python code, while Coding Assistant specializes in code generation and file operations without code execution.

Coding Assistant supports the providers indicated in the availability table.

### Jupyter Notebook :id=jupyter-notebook

![Jupyter Notebook app icon](../assets/icons/jupyter-notebook.png ':size=40')

This application allows the AI to create Jupyter Notebooks, add cells, and execute code within the cells based on user requests. The execution of the code uses a Python environment within a Docker container. The created Notebook is saved in the `Shared Folder`.

?> You can start or stop JupyterLab by asking the AI agent. Alternatively, you can use the `Start JupyterLab` or `Stop JupyterLab` menu items in the `Console Panel` menu bar.
<br /><br />![Action menu](../assets/images/jupyter-start-stop.png ':size=190')

<!-- > 📸 **Screenshot needed**: Jupyter Notebook app showing notebook creation and cell execution -->

?> **Note:** For Server Mode restrictions, see [Web Interface - Server Mode](./web-interface.md#server-mode).

Jupyter Notebook is available for the providers shown in the availability table.

### Monadic Chat Help

![Help app icon](../assets/icons/help.png ':size=40')

This is an AI-powered help assistant for Monadic Chat. It provides contextual assistance based on the project's documentation, answering questions about features, usage, and troubleshooting in any language.

The help system uses a pre-built knowledge base created from the English documentation. When you ask questions, it searches for relevant information and provides accurate answers based on the official documentation. For more details about the help system architecture, see [Help System](../advanced-topics/help-system.md).
