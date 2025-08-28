# Basic Apps

The following basic apps are available. You can select any of the basic apps and adjust the behavior of the AI agent by changing parameters or rewriting the initial prompt. The adjusted settings can be exported/imported to/from an external JSON file.

Most basic apps support multiple AI providers. See the table below for specific app availability by provider. For information on available models from each provider, see [Language Models](./language-models.md).

For information on how to develop your own apps, refer to the [App Development](../advanced-topics/develop_apps.md) section.

## App Availability by Provider :id=app-availability

The table below shows which apps are available for which AI model providers.


| App | OpenAI | Claude | Cohere | DeepSeek | Google Gemini | xAI Grok | Mistral | Perplexity | Ollama |
|-----|:------:|:------:|:------:|:--------:|:------:|:----:|:-------:|:----------:|:------:|
| Chat | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Chat Plus | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Voice Chat | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | |
| Wikipedia | ✅ | | | | | | | | |
| Math Tutor | ✅ | | | | | | | | |
| Second Opinion | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Research Assistant | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | |
| Language Practice | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | |
| Language Practice Plus | ✅ | | | | | | | | |
| Translate | ✅ | | | | | | | | |
| Voice Interpreter | ✅ | | | | | | | | |
| Novel Writer | ✅ | | | | | | | | |
| Image Generator | ✅ | | | | ✅ | ✅ | | | |
| Video Generator | | | | | ✅ | | | | |
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

## Assistant :id=assistant

### Chat

![Chat app icon](../assets/icons/chat.png ':size=40')

This is a standard chat application. The AI responds to the text input by the user with appropriate emojis. Web search capabilities are available but disabled by default for user control over costs and privacy. You can enable web search manually in the app settings when you need current information.

<!-- > 📸 **Screenshot needed**: Chat app interface showing a conversation with emojis -->

Chat apps are also available for the following models:

- OpenAI
- Anthropic Claude
- xAI Grok
- Google Gemini
- Mistral AI
- Perplexity
- DeepSeek
- Cohere
- Ollama (local models)

### Chat Plus

![Chat app icon](../assets/icons/chat-plus.png ':size=40')

This is a chat application that is "monadic" and has additional features compared to the standard chat application. The AI responds to the user's text input and while doing so, it also provides additional information as follows:

- reasoning: The reasoning and thought process behind its response.
- topics: The list of topics discussed in the conversation so far.
- people: The list of people mentioned in the conversation so far.
- notes: The list of notes that should be remembered during the conversation.


### Voice Chat :id=voice-chat

![Voice Chat app icon](../assets/icons/voice-chat.png ':size=40')

This application allows you to chat using voice, utilizing OpenAI's Speech-to-Text recognition API and the browser's speech synthesis API. The initial prompt is basically the same as the Chat app. The app can use different AI models to generate responses. A web browser that supports the Text to Speech API, such as Google Chrome or Microsoft Edge, is required.

![Voice input](../assets/images/voice-input-stop.png ':size=400')

While the user is speaking, a waveform is displayed. When the user stops speaking, the probability value (p-value, 0 - 1) of the voice recognition result is displayed.

![Voice p-value](../assets/images/voice-p-value.png ':size=400')


Voice Chat apps are also available for the following models:

- OpenAI
- Anthropic Claude
- xAI Grok
- Google Gemini
- Mistral AI
- Cohere
- DeepSeek
- Perplexity

### Wikipedia

![Wikipedia app icon](../assets/icons/wikipedia.png ':size=40')

This is basically the same as Chat, but for questions about events that occurred after the language model's cutoff date, which GPT cannot answer, it searches Wikipedia for answers. If the query is in a language other than English, the Wikipedia search is conducted in English, and the results are translated back into the original language.

### Math Tutor

![Math Tutor app icon](../assets/icons/math-tutor.png ':size=40')

This application responds using mathematical notation with [MathJax](https://www.mathjax.org/). It is suitable for math-related questions and answers.

!> **Caution:** LLMs are known to struggle with calculations requiring multiple steps or complex logic and can produce incorrect results.  Double-check any mathematical output from this app, and if accuracy is critical, it is recommended to use the Code Interpreter app to perform the calculations.

### Second Opinion

![Second Opinion app icon](../assets/icons/second-opinion.png ':size=40')

This app provides a two-step consultation process. **Step 1**: Ask your question and receive an initial answer from the AI. **Step 2**: Request verification by saying phrases like "Get a second opinion," "What does Claude think?" or "Verify this answer." The app will then consult another AI provider (Claude, Gemini, Mistral, etc.) to review and comment on the initial response. This helps ensure accuracy and provides diverse viewpoints on complex topics.

Second Opinion apps are available for all supported models: OpenAI, Claude, Gemini, Mistral, Cohere, Perplexity, xAI Grok, DeepSeek, and Ollama.

### Research Assistant

![Research Assistant app icon](../assets/icons/research-assistant.png ':size=40')

This app is designed to support academic and scientific research by serving as an intelligent research assistant with powerful web search capabilities. It retrieves and analyzes information from online sources, helping you find current information, verify facts, and research topics comprehensively. The research assistant provides reliable and detailed insights, summaries, and explanations to advance your inquiries.

Research Assistant apps are also available for the following models:

- OpenAI
- Anthropic Claude  
- xAI Grok
- Google Gemini
- Mistral AI (requires Tavily API)
- Cohere (requires Tavily API)
- DeepSeek (requires Tavily API)
- Perplexity

?> **Web Search Functionality**: 
> - **Native search**: OpenAI (`gpt-4o-search-preview` models), Anthropic Claude (`web_search_20250305` tool), xAI Grok (Live Search), Google Gemini (native Google Search), and Perplexity (built into sonar models)
> - **Requires Tavily API**: Mistral AI, Cohere, and DeepSeek. You can obtain a free API key from [Tavily](https://tavily.com/) (1,000 free API calls per month)

## Language Related :id=language-related

### Language Practice

![Language Practice app icon](../assets/icons/language-practice.png ':size=40')

This is a language learning application where the conversation starts with the assistant's speech. The assistant's speech is played back using speech synthesis. The user starts speech input by pressing the Enter key and ends it by pressing the Enter key again.


Language Practice apps are available for the following models:

- OpenAI
- Anthropic Claude
- xAI Grok
- Google Gemini
- Mistral AI
- Perplexity
- Cohere
- DeepSeek

### Language Practice Plus

![Language Practice Plus app icon](../assets/icons/language-practice-plus.png ':size=40')

This is a language learning application where the conversation starts with the assistant's speech, played back using speech synthesis.  The user starts and ends speech input by pressing the Enter key. In addition to the usual response, the assistant includes linguistic advice, presented as text, not speech.



### Translate

![Translate app icon](../assets/icons/translate.png ':size=40')

This app translates the user's input text into another language. First, the assistant asks for the target language. Then, it translates the input text into the specified language. If you want to specify how a particular phrase should be translated, enclose the relevant part of the input text in parentheses and provide the desired translation within the parentheses.


### Voice Interpreter

![Voice Interpreter app icon](../assets/icons/voice-chat.png ':size=40')

This app translates the user's voice input into another language and speaks the translation using speech synthesis. First, the assistant asks for the target language. Then, it translates the input text into the specified language.


## Content Generation :id=content-generation

### Novel Writer

![Novel Writer app icon](../assets/icons/novel-writer.png ':size=40')

This application is for co-writing novels with the assistant. The story unfolds based on the user's prompts, maintaining consistency and flow.  The AI agent first asks for the story's setting, characters, genre, and target word count.  The user can then provide prompts, and the AI agent will continue the story based on those prompts.


### Image Generator

![Image Generator app icon](../assets/icons/image-generator.png ':size=40')

This application generates images based on descriptions. 

The OpenAI version uses the latest gpt-image-1 model and supports three main operations:

1. **Image Generation**: Create new images from text descriptions
2. **Image Editing**: Modify existing images using text prompts and optional masks
3. **Image Variation**: Generate alternative versions of an existing image

With the image editing feature, you can:
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

Image Generator apps are also available for the following models:

- OpenAI (using gpt-image-1) - supports image generation, editing, and variation
- Google Gemini (using Imagen 3 and Gemini 2.0 Flash) - supports image generation with automatic model selection and image editing
- xAI Grok - supports image generation

### Video Generator

![Video Generator app icon](../assets/icons/video-generator.png ':size=40')

This application generates videos using Google's Veo model through the Gemini API. It supports both text-to-video and image-to-video generation with different aspect ratios and durations.

**Key Features:**
- **Text-to-video generation**: Create videos from text descriptions
- **Image-to-video generation**: Animate existing images by using them as the first frame
- **Aspect ratio options**: Choose between landscape (16:9) and portrait (9:16) formats
- **Person generation control**: Option to allow or restrict generation of videos containing people


**Usage:**
1. For text-to-video: Provide a detailed description of the video you want to create
2. For image-to-video: Upload an image and describe how it should be animated
3. Specify the desired aspect ratio and person generation preferences
4. The AI will process your request using Google's Veo model

?> **Note:** Video generation typically takes 2-6 minutes to complete. Generated videos are saved in the `Shared Folder` and displayed in the chat interface.

**Example requests:**
- "Create a video of a sunset over mountains" (text-to-video)
- "Turn this image into a video of waves gently moving" (image-to-video with uploaded image)
- "Generate a vertical video of a dancing robot" (9:16 aspect ratio)

Video Generator is available exclusively with Google Gemini models.

### Mail Composer

![Mail Composer app icon](../assets/icons/mail-composer.png ':size=40')

This application is for drafting emails in collaboration with the assistant. The assistant drafts emails based on the user's requests and specifications.


Mail Composer apps are available for the following models:

- OpenAI
- Anthropic Claude
- xAI Grok
- Google Gemini
- Mistral AI
- Perplexity
- Cohere
- DeepSeek

### Mermaid Grapher

![Mermaid Grapher app icon](../assets/icons/diagram-draft.png ':size=40')

This application visualizes data using [mermaid.js](https://mermaid.js.org/). When you input any data or instructions, the agent generates Mermaid code for the appropriate diagram type and renders it.

**Key Features:**
- **Automatic diagram type selection**: The AI chooses the best diagram type for your data (flowchart, sequence, class, state, ER, Gantt, pie, Sankey, mindmap, etc.)
- **Real-time validation**: Diagrams are validated using Selenium and the actual Mermaid.js engine before being displayed
- **Error correction**: If syntax errors occur, the AI automatically analyzes and fixes them
- **Automatic error fixing**: The AI can detect common issues (like incorrect Sankey syntax) and automatically apply fixes
- **Preview generation**: A PNG preview image is saved to your shared folder for easy access
- **Web search integration**: Can fetch the latest Mermaid.js documentation and examples for unfamiliar diagram types

**Enhanced Validation:**
- Uses Selenium WebDriver to validate diagrams with the actual Mermaid.js rendering engine
- Falls back to static validation if Selenium is unavailable
- Provides specific error messages and suggestions for fixing common issues

**Usage Tips:**
- Simply describe what you want to visualize, and the AI will create the appropriate diagram
- For Sankey diagrams, note that the syntax uses CSV format (source,target,value) not arrow notation
- All preview images are saved as `mermaid_preview_[timestamp].png` in your shared folder
- The AI will always validate diagrams before showing them to ensure they render correctly


### DrawIO Grapher

![DrawIO Grapher app icon](../assets/icons/diagram-draft.png ':size=40')

This application helps you create Draw.io diagrams. Provide your requirements and the agent will generate a Draw.io XML file that you can download and import into Draw.io for further editing. It can create various diagram types including flowcharts, UML diagrams, entity-relationship diagrams, network diagrams, org charts, mind maps, BPMN diagrams, Venn diagrams, and wireframes. The generated .drawio file will be saved to the shared folder.


DrawIO Grapher apps are available for the following models:

- OpenAI
- Anthropic Claude

### Syntax Tree

![Syntax Tree app icon](../assets/icons/syntax-tree.png ':size=40')

This application generates linguistic syntax trees from sentences in multiple languages. It analyzes the grammatical structure of sentences and creates visual tree diagrams using LaTeX and tikz-qtree. The app supports:

- Multiple languages including English, Japanese, Chinese, and other languages
- Binary branching analysis (each node has at most 2 children)
- Editable SVG output that can be modified in vector graphics editors
- Comprehensive particle analysis for Japanese (includes all particles/joshi)
- Professional linguistic notation following syntactic theory standards

The generated syntax trees are displayed as SVG images with transparent backgrounds, styled with CSS for web display.


Syntax Tree apps are available for the following models:

- OpenAI
- Anthropic Claude

### Concept Visualizer :id=concept-visualizer

![Concept Visualizer app icon](../assets/icons/diagram-draft.png ':size=40')

This application visualizes various concepts and relationships through diagrams using LaTeX/TikZ. It can create mind maps, flowcharts, organizational charts, network diagrams, and many other types of visual representations based on natural language descriptions. The app supports:

- **Wide variety of diagram types**: Mind maps, flowcharts, organizational charts, network diagrams, timelines, Venn diagrams, 3D visualizations, and more
- **Natural language input**: Simply describe what you want to visualize in plain language
- **Multiple domains**: Business diagrams (SWOT, business models), educational diagrams (concept maps, learning paths), scientific diagrams (molecular structures, food webs, 3D plots), and technical diagrams (system architecture, UML)
- **Multi-language support**: Handles text in various languages including CJK (Chinese, Japanese, Korean)
- **Professional output**: Generates high-quality SVG diagrams suitable for presentations and publications
- **Customizable styling**: Appropriate colors, layouts, and visual elements for each diagram type
- **3D capabilities**: Supports 3D scatter plots, surfaces, and other three-dimensional visualizations using tikz-3dplot

The generated diagrams are displayed as editable SVG images that can be further modified in vector graphics editors.


**Technical Notes:**
- Uses LaTeX/TikZ for diagram generation with comprehensive package support including:
  - Core LaTeX packages for basic diagram creation
  - `texlive-science` for 3D visualizations with tikz-3dplot
  - CJK language support for multi-language text rendering
  - `dvisvgm` for high-quality SVG output
- Generated SVG files are saved to the shared folder and displayed via the `/data/` endpoint
- Automatically detects and loads appropriate TikZ libraries based on diagram type

Concept Visualizer apps are available for the following models:

- OpenAI
- Anthropic Claude

### Speech Draft Helper

![Speech Draft Helper app icon](../assets/icons/speech-draft-helper.png ':size=40')

This application helps you draft speeches. You can ask the assistant to draft a speech based on a specific topic or provide a speech draft (plain text, Word, PDF) and ask the assistant to improve it. It can also generate audio files of the speech (MP3 format for OpenAI and ElevenLabs, WAV format for Gemini).


## Content Analysis :id=content-analysis

### Visual Web Explorer :id=visual-web-explorer

This application captures web pages as screenshots or extracts their text content in Markdown format. It's perfect for creating documentation, archiving web content, or analyzing page content.

**Key Features:**
- **Screenshot Mode**: Capture entire web pages as multiple viewport-sized images with automatic scrolling
- **Text Extraction Mode**: Convert web content to clean Markdown format
- **Provider-specific Image Recognition**: When HTML parsing fails, uses each provider's native vision API for text extraction
- **Customizable Viewports**: Desktop (1920×1080), tablet (1024×768), mobile (375×812), and print (794×1123) presets
- **Overlap Control**: Configure overlap between screenshots for seamless reading
- **Automatic Naming**: Files are named with domain and timestamp

**Usage Examples:**
- `"Capture screenshots of https://github.com"` - Takes multiple screenshots
- `"Extract text from https://example.com"` - Converts to Markdown
- `"Extract text from https://example.com with image recognition"` - Uses vision API when needed
- `"Take mobile screenshots of https://example.com"` - Uses mobile viewport preset


**Technical Notes:**
- Uses Selenium WebDriver for page rendering
- `webpage_fetcher.py` handles HTML to Markdown conversion
- Falls back to provider-specific image recognition APIs when text extraction fails
- Each provider (OpenAI, Claude, Gemini, Grok) uses its native image format

Visual Web Explorer apps are available for the following models:
- OpenAI
- Anthropic Claude
- Google Gemini
- xAI Grok

### Video Describer

![Video Describer app icon](../assets/icons/video-describer.png ':size=40')

This application analyzes video content and describes what is happening. The app extracts frames from the video, converts them into base64 PNG images, and extracts audio data, saving it as an MP3 file. Based on this information, the AI provides a description of the visual and audio content.

To use this app, store the video file in the `Shared Folder` and provide the file name.  Specify the frames per second (fps) for frame extraction. If the total number of frames exceeds 50, only 50 frames will be proportionally extracted from the video.


### PDF Navigator

![PDF Navigator app icon](../assets/icons/pdf-navigator.png ':size=40')

This application reads PDF files and allows the assistant to answer user questions based on the content. Click the `Upload PDF` button to specify the file. The content of the file is divided into segments of the length specified by `max_tokens`, and text embeddings are calculated for each segment. Upon receiving input from the user, the text segment closest to the input sentence's text embedding value is passed to GPT along with the user's input, and a response is generated based on that content.

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

?> The PDF Navigator app uses [PyMuPDF](https://pymupdf.readthedocs.io/en/latest/) to extract text from PDF files and the text data and its embeddings are stored in [PGVector](https://github.com/pgvector/pgvector) database (database name: `monadic_user_docs`). The app now properly connects to the vector database using the `pdf_vector_storage` feature flag, ensuring reliable access to your PDF content. For detailed information about the vector database implementation, see the [Vector Database](../docker-integration/vector-database.md) documentation.

**Configuration Options:**

PDF Navigator behavior can be customized via environment variables in `~/monadic/config/env`:

- `PDF_RAG_TOKENS`: Number of tokens per chunk (default: 4000)
  - Controls how PDF text is split into chunks for embedding
  - Larger values provide more context but may reduce search precision
  - Recommended range: 2000-6000 tokens

- `PDF_RAG_OVERLAP_LINES`: Number of lines to overlap between chunks (default: 4)
  - Provides continuity between adjacent chunks
  - Helps prevent context loss at chunk boundaries
  - Recommended range: 2-10 lines

Example configuration:
```
PDF_RAG_TOKENS=5000
PDF_RAG_OVERLAP_LINES=6
```


![PDF button](../assets/images/app-pdf.png ':size=700')


![Import PDF](../assets/images/import-pdf.png ':size=400')

![PDF DB Panel](../assets/images/monadic-chat-pdf-db.png ':size=400')

### Content Reader

![Content Reader app icon](../assets/icons/content-reader.png ':size=40')

This application features an AI chatbot that examines and explains the content of provided files or web URLs in a clear, beginner-friendly manner.  Users can upload files or URLs containing various text data, including programming code. If a URL is mentioned in the prompt message, the app automatically retrieves and integrates the content into the conversation with GPT.

To specify a file for the AI to read, save the file in the `Shared Folder` and specify the file name in the User message. If the AI cannot find the file, verify the file name and ensure it's accessible from the current code execution environment.

Supported file formats:

- PDF
- Microsoft Word (docx)
- Microsoft PowerPoint (pptx)
- Microsoft Excel (xlsx)
- CSV
- Text (txt)
- PNG
- JPEG
- MP3


## Code Generation :id=code-generation

### Code Interpreter

![Code Interpreter app icon](../assets/icons/code-interpreter.png ':size=40')

This application allows the AI to create and execute program code. The execution of the program uses a Python environment within a Docker container. Text data and images obtained as execution results are saved in the `Shared Folder` and also displayed in the chat.  If you have a file (such as Python code or CSV data) that you want the AI to read, save the file in the `Shared Folder` and specify the file name in the User message. If the AI cannot find the file location, please verify the file name and inform the message that it is accessible from the current code execution environment.

?> **Important Notes:**
> - The app implements automatic error handling to prevent infinite loops when code execution fails
> - If code execution encounters repeated errors, the app will automatically stop retrying and provide an error message
> - For matplotlib plots with Japanese text, the Python container includes Japanese font support (Noto Sans CJK JP) configured through matplotlibrc

<!-- > 📸 **Screenshot needed**: Code Interpreter showing code execution with output and generated plots -->

Code Interpreter apps are also available for the following models:

- OpenAI
- Anthropic Claude (uses the `run_code` tool for code execution)
- Cohere
- DeepSeek
- Google Gemini
- xAI Grok
- Mistral AI

### Coding Assistant

![Coding Assistant app icon](../assets/icons/coding-assistant.png ':size=40')

This application is designed for writing computer program code. You can interact with an AI configured as a professional software engineer. It answers various questions, writes code, makes appropriate suggestions, and provides helpful advice through user prompts.

?> While Code Interpreter executes the code, Coding Assistant specializes in providing code snippets and advice. A long code snippet will be divided into multiple parts, and the user will be asked if they want to proceed with the next part.


Coding Assistant apps are also available for the following models:

- OpenAI
- Anthropic Claude
- xAI Grok
- Google Gemini
- Mistral AI
- Perplexity
- DeepSeek
- Cohere

### Jupyter Notebook :id=jupyter-notebook

![Jupyter Notebook app icon](../assets/icons/jupyter-notebook.png ':size=40')

This application allows the AI to create Jupyter Notebooks, add cells, and execute code within the cells based on user requests. The execution of the code uses a Python environment within a Docker container. The created Notebook is saved in the `Shared Folder`.

> You can start or stop JupyterLab by asking the AI agent. Alternatively, you can use the `Start JupyterLab` or `Stop JupyterLab` menu items in the `Console Panel` menu bar.
<br /><br />![Action menu](../assets/images/jupyter-start-stop.png ':size=190')

<!-- > 📸 **Screenshot needed**: Jupyter Notebook app showing notebook creation and cell execution -->

!> **Security Note:** In Server Mode, Jupyter Notebook functionality is disabled by default for security reasons. To enable it, you must explicitly set `ALLOW_JUPYTER_IN_SERVER_MODE=true` in your configuration file (`~/monadic/config/env`). Only enable this if you understand the security implications of running Jupyter in a multi-user environment.

Jupyter Notebook apps are available for the following providers:

- OpenAI
- Anthropic Claude  
- Google Gemini
- xAI Grok

?> **Provider-specific Notes:**
> - **Gemini**: Uses a combined `create_and_populate_jupyter_notebook` function for better reliability when creating notebooks with cells
> - All providers support creating notebooks, adding cells, and executing Python code within the Jupyter environment

### Monadic Chat Help

![Help app icon](../assets/icons/help.png ':size=40')

This is an AI-powered help assistant for Monadic Chat. It provides contextual assistance based on the project's documentation, answering questions about features, usage, and troubleshooting in any language.

The help system uses a pre-built knowledge base created from the English documentation. When you ask questions, it searches for relevant information and provides accurate answers based on the official documentation. For more details about the help system architecture, see [Help System](../advanced-topics/help-system.md).

