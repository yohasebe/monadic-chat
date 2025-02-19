# Basic Apps

Currently, the following basic apps are available. You can select any of the basic apps and adjust the behavior of the AI agent by changing parameters or rewriting the initial prompt. The adjusted settings can be exported/imported to/from an external JSON file.

Basic apps use OpenAI's models. If you want to use models from other providers, see [Language Models](./language-models.md).

For information on how to develop your own apps, refer to the [App Development](./develop_apps.md) section.

> Click the dropdown to see the recipe file of each app. The files are the same as the ones in the `main` branch of the Monadic Chat's [GitHub repository](https://github.com/yohasebe/monadic-chat).

Some apps are available for models by multiple providers. If not specified, the app is available for OpenAI's models.

## Assistant

### Chat

![Chat app icon](./assets/icons/chat.png ':size=40')

This is a standard chat application. The AI responds to the text input by the user. Emojis corresponding to the content are also displayed.

<details>
<summary>chat_app.rb</summary>

[chat_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/chat/chat_app.rb ':include :type=code')

</details>

Coding Assistant apps are also available for the following models:

- OpenAI
- Anthropic Claude
- xAI Grok
- Google Gemini
- Mistral AI
- Perplexity
- DeepSeek

### Chat Plus

![Chat app icon](./assets/icons/chat.png ':size=40')

This is a chat application that is "monadic" and has additional features compared to the standard chat application. The AI responds to the user's text input and while doing so, it also provides additional information as follows:

- reasoning: The reasoning and thought process behind its response.
- topics: The list of topics discussed in the conversation so far.
- people: The list of people mentioned in the conversation so far.
- notes: The list of notes that should be remembered during the conversation.

<details>
<summary>chat_plus_app.rb</summary>

[chat_plus_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/chat_plus/chat_plus_app.rb ':include :type=code')

</details>

### Voice Chat

![Voice Chat app icon](./assets/icons/voice-chat.png ':size=40')

This application allows you to chat using voice, utilizing OpenAI's Whisper voice recognition API and the browser's speech synthesis API. The initial prompt is basically the same as the Chat app. A web browser that supports the Text to Speech API, such as Google Chrome or Microsoft Edge, is required.

![Voice input](./assets/images/voice-input-stop.png ':size=400')

While the user is speaking, a waveform is displayed. When the user stops speaking, the probability value (p-value, 0 - 1) of the voice recognition result is displayed.

![Voice p-value](./assets/images/voice-p-value.png ':size=400')

<details>
<summary>voice_chat_app.rb</summary>

[voice_chat_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/voice_chat/voice_chat_app.rb ':include :type=code')

</details>

### Wikipedia

![Wikipedia app icon](./assets/icons/wikipedia.png ':size=40')

This is basically the same as Chat, but for questions about events that occurred after the language model's cutoff date, which GPT cannot answer, it searches Wikipedia for answers. If the query is in a language other than English, the Wikipedia search is conducted in English, and the results are translated back into the original language.

<details>
<summary>wikipedia_app.rb</summary>

[wikipedia_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/wikipedia/wikipedia_app.rb ':include :type=code')

</details>

### Math Tutor

![Math Tutor app icon](./assets/icons/math.png ':size=40')

This application responds using mathematical notation with [MathJax](https://www.mathjax.org/). It is suitable for math-related questions and answers.

?> Caution: LLMs are known to struggle with calculations requiring multiple steps or complex logic and can produce incorrect results.  Double-check any mathematical output from this app, and if accuracy is critical, it is recommended to use the Code Interpreter app to perform the calculations.

<details>
<summary>math_tutor_app.rb</summary>

[math_tutor_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/math_tutor/math_tutor_app.rb ':include :type=code')

</details>

### Second Opinion

![Second Opinion app icon](./assets/icons/second-opinion.png ':size=40')

This app generates an answer to your question. To verify the validity of that answer, it also asks the same question to the same LLM model and compares the answers. This application can be used to prevent hallucinations or misunderstandings in AI responses.

<details>
<summary>second_opinion_app.rb</summary>

[second_opinion_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/second_opinion/second_opinion_app.rb ':include :type=code')

</details>

### Research Assistant

![Research Assistant app icon](./assets/icons/research-assistant.png ':size=40')


This app is designed to support academic and scientific research by serving as an intelligent research assistant. It leverages web search via the Tavily API to retrieve and analyze information from the web, including data from web pages, images, audio files, and documents. The research assistant provides reliable and detailed insights, summaries, and explanations to advance your scientific inquiries.

<details>
<summary>research_assistant_app.rb</summary>

[research_assistant_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/research_assistant/research_assistant_app.rb ':include :type=code')

?> The Research Assistant app uses the [Tavily API](https://tavily.com/) to retrieve and analyze information from the web. You can make up to 1,000 requests per month for free. 
</details>

## Language Related

### Language Practice

![Language Practice app icon](./assets/icons/language-practice.png ':size=40')

This is a language learning application where the conversation starts with the assistant's speech. The assistant's speech is played back using speech synthesis. The user starts speech input by pressing the Enter key and ends it by pressing the Enter key again.

<details>
<summary>language_practice_app.rb</summary>

[language_practice_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/language_practice/language_practice_app.rb ':include :type=code')

</details>

### Language Practice Plus

![Language Practice Plus app icon](./assets/icons/language-practice-plus.png ':size=40')

This is a language learning application where the conversation starts with the assistant's speech, played back using speech synthesis.  The user starts and ends speech input by pressing the Enter key. In addition to the usual response, the assistant includes linguistic advice, presented as text, not speech.


<details>
<summary>language_practice_plus_app.rb</summary>

[language_practice_plus_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/language_practice_plus/language_practice_plus_app.rb ':include :type=code')

</details>

### Translate

![Translate app icon](./assets/icons/translate.png ':size=40')

This app translates the user's input text into another language. First, the assistant asks for the target language. Then, it translates the input text into the specified language. If you want to specify how a particular phrase should be translated, enclose the relevant part of the input text in parentheses and provide the desired translation within the parentheses.

<details>
<summary>translate_app.rb</summary>

[translate_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/translate/translate_app.rb ':include :type=code')

</details>

### Voice Interpreter

![Voice Interpreter app icon](./assets/icons/voice-chat.png ':size=40')

This app translates the user's voice input into another language and speaks the translation using speech synthesis. First, the assistant asks for the target language. Then, it translates the input text into the specified language.

<details>
<summary>voice_interpreter_app.rb</summary>

[voice_interpreter_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/voice_interpreter/voice_interpreter_app.rb ':include :type=code')

</details>

## Content Generation

### Novel Writer

![Novel Writer app icon](./assets/icons/novel.png ':size=40')

This application is for co-writing novels with the assistant. The story unfolds based on the user's prompts, maintaining consistency and flow.  The AI agent first asks for the story's setting, characters, genre, and target word count.  The user can then provide prompts, and the AI agent will continue the story based on those prompts.

<details>
<summary>novel_writer_app.rb</summary>

[novel_writer_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/novel_writer/novel_writer_app.rb ':include :type=code')

</details>

### Image Generator

![Image Generator app icon](./assets/icons/image-generator.png ':size=40')

This application generates images based on descriptions. If the prompt is not specific or is written in a language other than English, it returns an improved prompt and asks whether to proceed with the improved prompt. It uses the Dall-E 3 API internally.

Images are saved in the `Shared Folder` and also displayed in the chat.

<details>
<summary>image_generator_app.rb</summary>

[image_generator_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/image_generator/image_generator_app.rb ':include :type=code')

</details>

### Mail Composer

![Mail Composer app icon](./assets/icons/mail-composer.png ':size=40')

This application is for drafting emails in collaboration with the assistant. The assistant drafts emails based on the user's requests and specifications.

<details>
<summary>mail_composer_app.rb</summary>

[mail_composer_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/mail_composer/mail_composer_app.rb ':include :type=code')

</details>

### Mermaid Grapher

![Mermaid Grapher app icon](./assets/icons/diagram-draft.png ':size=40')

This application visualizes data using [mermaid.js](https://mermaid.js.org/). When you input any data or instructions, the agent generates Mermaid code for a flowchart and renders the image.

<details>
<summary>mermaid_grapher_app.rb</summary>

[mermaid_grapher_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/mermaid_grapher/mermaid_grapher_app.rb ':include :type=code')

</details>

### Music Composer

![Music Composer app icon](./assets/icons/music.png ':size=40')

This application creates simple sheet music using [ABC notation](https://en.wikipedia.org/wiki/ABC_notation) and plays it in Midi. Specify the instrument and the genre or style of music to be used.

<details>
<summary>music_composer_app.rb</summary>

[music_composer_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/music_composer/music_composer_app.rb ':include :type=code')

</details>

### Speech Draft Helper

![Speech Draft Helper app icon](./assets/icons/speech-draft-helper.png ':size=40')

This application helps you draft speeches. You can ask the assistant to draft a speech based on a specific topic or provide a speech draft (plain text, Word, PDF) and ask the assistant to improve it. It can also generate an MP3 file of the speech.

<details>
<summary>speech_draft_helper_app.rb</summary>

[speech_draft_helper_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/speech_draft_helper/speech_draft_helper_app.rb ':include :type=code')

</details>

## Content Analysis

### Video Describer

![Video Describer app icon](./assets/icons/video.png ':size=40')

This application analyzes video content and describes what is happening. The app extracts frames from the video, converts them into base64 PNG images, and extracts audio data, saving it as an MP3 file. Based on this information, the AI provides a description of the visual and audio content.

To use this app, store the video file in the `Shared Folder` and provide the file name.  Specify the frames per second (fps) for frame extraction. If the total number of frames exceeds 50, only 50 frames will be proportionally extracted from the video.

<details>
<summary>video_describer_app.rb</summary>

[video_describer_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/video_describer/video_describer_app.rb ':include :type=code')

</details>

### PDF Navigator

![PDF Navigator app icon](./assets/icons/pdf-navigator.png ':size=40')

This application reads PDF files and allows the assistant to answer user questions based on the content. Click the `Upload PDF` button to specify the file. The content of the file is divided into segments of the length specified by `max_tokens`, and text embeddings are calculated for each segment. Upon receiving input from the user, the text segment closest to the input sentence's text embedding value is passed to GPT along with the user's input, and a response is generated based on that content.

?> The PDF Navigator app uses [PyMuPDF](https://pymupdf.readthedocs.io/en/latest/) to extract text from PDF files and the text data and its embeddings are stored in [PGVector](https://github.com/pgvector/pgvector) database.

![PDF button](./assets/images/app-pdf.png ':size=700')

![Import PDF](./assets/images/import-pdf.png ':size=400')

![PDF DB Panel](./assets/images/monadic-chat-pdf-db.png ':size=400')

<details>
<summary>pdf_navigator_app.rb</summary>

[pdf_navigator_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/pdf_navigator/pdf_navigator_app.rb ':include :type=code')

</details>

### Content Reader

![Content Reader app icon](./assets/icons/document-reader.png ':size=40')

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


<details>
<summary>content_reader_app.rb</summary>

[content_reader_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/content_reader/content_reader_app.rb ':include :type=code')

</details>

## Code Generation

### Code Interpreter

![Code Interpreter app icon](./assets/icons/code-interpreter.png ':size=40')

This application allows the AI to create and execute program code. The execution of the program uses a Python environment within a Docker container. Text data and images obtained as execution results are saved in the `Shared Folder` and also displayed in the chat.  If you have a file (such as Python code or CSV data) that you want the AI to read, save the file in the `Shared Folder` and specify the file name in the User message. If the AI cannot find the file location, please verify the file name and inform the message that it is accessible from the current code execution environment.

<details>
<summary>code_interpreter_app.rb</summary>

[code_interpreter_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/code_interpreter/code_interpreter_app.rb ':include :type=code')

</details>

Code Interpreter apps are also available for the following models:

- Anthropic Claude

### Coding Assistant

![Coding Assistant app icon](./assets/icons/coding-assistant.png ':size=40')

This application is designed for writing computer program code. You can interact with an AI configured as a professional software engineer. It answers various questions, writes code, makes appropriate suggestions, and provides helpful advice through user prompts.

> While Code Interpreter executes the code, Coding Assistant specializes in providing code snippets and advice. A long code snippet will be divided into multiple parts, and the user will be asked if they want to proceed with the next part.

<details>
<summary>coding_assistant_app.rb</summary>

[coding_assistant_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/coding_assistant/coding_assistant_app.rb ':include :type=code')

</details>

Coding Assistant apps are also available for the following models:

- OpenAI
- Anthropic Claude
- xAI Grok
- Google Gemini
- Mistral AI
- Perplexity
- DeepSeek

### Jupyter Notebook

![Jupyter Notebook app icon](./assets/icons/jupyter-notebook.png ':size=40')

This application allows the AI to create Jupyter Notebooks, add cells, and execute code within the cells based on user requests. The execution of the code uses a Python environment within a Docker container. The created Notebook is saved in the `Shared Folder`.

> You can start or stop JupyterLab by asking the AI agent. Alternatively, you can use the `Start JupyterLab` or `Stop JupyterLab` menu items in the `Console Panel` menu bar.
<br /><br />![Action menu](./assets/images/jupyter-start-stop.png ':size=190')

<details>
<summary>jupyter_notebook_app.rb</summary>

[jupyter_notebook_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/jupyter_notebook/jupyter_notebook_app.rb ':include :type=code')

</details>

Jupyter Notebook apps are also available for the following models:

- OpenAI
- Anthropic Claude
