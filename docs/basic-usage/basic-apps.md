# Basic Apps

Currently, the following basic apps are available. You can select any of the basic apps and adjust the behavior of the AI agent by changing parameters or rewriting the initial prompt. The adjusted settings can be exported/imported to/from an external JSON file.

Basic apps use OpenAI's models. If you want to use models from other providers, see [Language Models](./language-models.md).

For information on how to develop your own apps, refer to the [App Development](../advanced-topics/develop_apps.md) section.

## App Availability by Provider :id=app-availability

The table below shows which apps are available for which AI model providers. If not specified in the app's description, the app is available for OpenAI's models only.

| App | OpenAI | Claude | Cohere | DeepSeek | Google Gemini | xAI Grok | Mistral | Perplexity |
|-----|:------:|:------:|:------:|:--------:|:------:|:----:|:-------:|:----------:|
| Chat | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Chat Plus | ✅ | | | | | | | |
| Voice Chat | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | |
| Wikipedia | ✅ | | | | | | | |
| Math Tutor | ✅ | | | | | | | |
| Second Opinion | ✅ | | | | | | | |
| Research Assistant | ✅ | ✅ | ✅ | | ✅ | ✅ | ✅ | ✅ |
| Language Practice | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Language Practice Plus | ✅ | | | | | | | |
| Translate | ✅ | | | | | | | |
| Voice Interpreter | ✅ | | | | | | | |
| Novel Writer | ✅ | | | | | | | |
| Image Generator | ✅ | | | | ✅ | ✅ | | |
| Video Generator | | | | | ✅ | | | |
| Mail Composer | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Mermaid Grapher | ✅ | | | | | | | |
| DrawIO Grapher | ✅ | ✅ | | | | | | |
| Speech Draft Helper | ✅ | | | | | | | |
| Video Describer | ✅ | | | | | | | |
| PDF Navigator | ✅ | | | | | | | |
| Content Reader | ✅ | | | | | | | |
| Code Interpreter | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | | |
| Coding Assistant | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Jupyter Notebook | ✅ | ✅ | | | | | | |

## Assistant :id=assistant

### Chat

![Chat app icon](../assets/icons/chat.png ':size=40')

This is a standard chat application. The AI responds to the text input by the user. Emojis corresponding to the content are also displayed.

Chat apps are also available for the following models:

- OpenAI
- Anthropic Claude
- xAI Grok
- Google Gemini
- Mistral AI
- Perplexity
- DeepSeek

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

### Wikipedia

![Wikipedia app icon](../assets/icons/wikipedia.png ':size=40')

This is basically the same as Chat, but for questions about events that occurred after the language model's cutoff date, which GPT cannot answer, it searches Wikipedia for answers. If the query is in a language other than English, the Wikipedia search is conducted in English, and the results are translated back into the original language.

### Math Tutor

![Math Tutor app icon](../assets/icons/math.png ':size=40')

This application responds using mathematical notation with [MathJax](https://www.mathjax.org/). It is suitable for math-related questions and answers.

?> Caution: LLMs are known to struggle with calculations requiring multiple steps or complex logic and can produce incorrect results.  Double-check any mathematical output from this app, and if accuracy is critical, it is recommended to use the Code Interpreter app to perform the calculations.

### Second Opinion

![Second Opinion app icon](../assets/icons/second-opinion.png ':size=40')

This app generates an answer to your question. To verify the validity of that answer, it also asks the same question to the same LLM model and compares the answers. This application can be used to prevent hallucinations or misunderstandings in AI responses.

### Research Assistant

![Research Assistant app icon](../assets/icons/research-assistant.png ':size=40')

This app is designed to support academic and scientific research by serving as an intelligent research assistant. It retrieves and analyzes information from the web, including data from web pages, images, audio files, and documents. The research assistant provides reliable and detailed insights, summaries, and explanations to advance your scientific inquiries.

Research Assistant apps are also available for the following models:

- OpenAI
- Anthropic Claude  
- xAI Grok
- Google Gemini
- Mistral AI
- Perplexity

?> When using web search functionality: OpenAI, Anthropic Claude, and xAI Grok models use their native web search APIs. For other providers (Gemini, Mistral, etc.), you need an API key from [Tavily](https://tavily.com/) to access the web search API. You can obtain a free API key by signing up on the Tavily website. It comes with 1,000 free API calls per month.

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

![Novel Writer app icon](../assets/icons/novel.png ':size=40')

This application is for co-writing novels with the assistant. The story unfolds based on the user's prompts, maintaining consistency and flow.  The AI agent first asks for the story's setting, characters, genre, and target word count.  The user can then provide prompts, and the AI agent will continue the story based on those prompts.

### Image Generator

![Image Generator app icon](../assets/icons/image-generator.png ':size=40')

This application generates images based on descriptions. 

The OpenAI version exclusively uses the gpt-image-1 model and supports three main operations:

1. **Image Generation**: Create new images from text descriptions
2. **Image Editing**: Modify existing images using text prompts and optional masks
3. **Image Variation**: Generate alternative versions of an existing image

Note that the image editing feature is only available with the gpt-image-1 model.

With the image editing feature, you can:
- Select an existing image as a base
- Specify areas to modify using a mask image (optional)
- Provide text instructions for the changes
- Customize output options including:
  - Image size (square, portrait, landscape)
  - Quality level (standard, hd)
  - Output format (PNG, JPEG, WebP)
  - Background type (transparent, opaque)
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

**Note:** Video generation typically takes 2-6 minutes to complete. Generated videos are saved in the `Shared Folder` and displayed in the chat interface.

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

This application visualizes data using [mermaid.js](https://mermaid.js.org/). When you input any data or instructions, the agent generates Mermaid code for a flowchart and renders the image.

### DrawIO Grapher

![DrawIO Grapher app icon](../assets/icons/diagram-draft.png ':size=40')

This application helps you create Draw.io diagrams. Provide your requirements and the agent will generate a Draw.io XML file that you can download and import into Draw.io for further editing. It can create various diagram types including flowcharts, UML diagrams, entity-relationship diagrams, network diagrams, org charts, mind maps, BPMN diagrams, Venn diagrams, and wireframes. The generated .drawio file will be saved to the shared folder.

DrawIO Grapher apps are available for the following models:

- OpenAI
- Anthropic Claude

### Speech Draft Helper

![Speech Draft Helper app icon](../assets/icons/speech-draft-helper.png ':size=40')

This application helps you draft speeches. You can ask the assistant to draft a speech based on a specific topic or provide a speech draft (plain text, Word, PDF) and ask the assistant to improve it. It can also generate an MP3 file of the speech.

## Content Analysis :id=content-analysis

### Video Describer

![Video Describer app icon](../assets/icons/video.png ':size=40')

This application analyzes video content and describes what is happening. The app extracts frames from the video, converts them into base64 PNG images, and extracts audio data, saving it as an MP3 file. Based on this information, the AI provides a description of the visual and audio content.

To use this app, store the video file in the `Shared Folder` and provide the file name.  Specify the frames per second (fps) for frame extraction. If the total number of frames exceeds 50, only 50 frames will be proportionally extracted from the video.

### PDF Navigator

![PDF Navigator app icon](../assets/icons/pdf-navigator.png ':size=40')

This application reads PDF files and allows the assistant to answer user questions based on the content. Click the `Upload PDF` button to specify the file. The content of the file is divided into segments of the length specified by `max_tokens`, and text embeddings are calculated for each segment. Upon receiving input from the user, the text segment closest to the input sentence's text embedding value is passed to GPT along with the user's input, and a response is generated based on that content.

?> The PDF Navigator app uses [PyMuPDF](https://pymupdf.readthedocs.io/en/latest/) to extract text from PDF files and the text data and its embeddings are stored in [PGVector](https://github.com/pgvector/pgvector) database. For detailed information about the vector database implementation, see the [Vector Database](../docker-integration/vector-database.md) documentation.

![PDF button](../assets/images/app-pdf.png ':size=700')

![Import PDF](../assets/images/import-pdf.png ':size=400')

![PDF DB Panel](../assets/images/monadic-chat-pdf-db.png ':size=400')

### Content Reader

![Content Reader app icon](../assets/icons/document-reader.png ':size=40')

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

Code Interpreter apps are also available for the following models:

- OpenAI
- Anthropic Claude
- Cohere
- DeepSeek
- Google Gemini
- xAI Grok

### Coding Assistant

![Coding Assistant app icon](../assets/icons/coding-assistant.png ':size=40')

This application is designed for writing computer program code. You can interact with an AI configured as a professional software engineer. It answers various questions, writes code, makes appropriate suggestions, and provides helpful advice through user prompts.

> While Code Interpreter executes the code, Coding Assistant specializes in providing code snippets and advice. A long code snippet will be divided into multiple parts, and the user will be asked if they want to proceed with the next part.

Coding Assistant apps are also available for the following models:

- OpenAI
- Anthropic Claude
- xAI Grok
- Google Gemini
- Mistral AI
- Perplexity
- DeepSeek

### Jupyter Notebook :id=jupyter-notebook

![Jupyter Notebook app icon](../assets/icons/jupyter-notebook.png ':size=40')

This application allows the AI to create Jupyter Notebooks, add cells, and execute code within the cells based on user requests. The execution of the code uses a Python environment within a Docker container. The created Notebook is saved in the `Shared Folder`.

> You can start or stop JupyterLab by asking the AI agent. Alternatively, you can use the `Start JupyterLab` or `Stop JupyterLab` menu items in the `Console Panel` menu bar.
<br /><br />![Action menu](../assets/images/jupyter-start-stop.png ':size=190')

Jupyter Notebook apps are also available for the following models:

- OpenAI
- Anthropic Claude
