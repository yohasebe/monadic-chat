---
title: Monadic Chat
layout: default
---

# Base Apps
{:.no_toc}

[English](/monadic-chat/apps) |
[日本語](/monadic-chat/apps_ja)

## Table of Contents
{:.no_toc}

1. toc
{:toc}

Currently, the following base apps are available for use. By selecting one of them and changing the parameters or rewriting the initial prompt, you can adjust the behavior of the AI agent. You can export/import the adjusted settings to/from an external JSON file.

## Chat

<img src="./assets/icons/chat.png" width="40px"/>

This is the standard application for monadic chat. It conducts text-based conversations. The AI agent generates responses to user input, adds appropriate emojis, and advances the conversation.

Recipe file: [chat_app.rb](https://github.com/yohasebe/monadic-chat/blob/main/docker/services/ruby/apps/chat/chat_app.rb)

## Language Practice

<img src="./assets/icons/language-practice.png" width="40px"/>

This is a language learning application where conversations begin with the assistant's speech. The assistant's speech is played back in a synthesized voice. To speak, press the Enter key to start speech input, and press Enter again to stop speech input.

Recipe file: [language_practice_app.rb](https://github.com/yohasebe/monadic-chat/blob/main/docker/services/ruby/apps/language_practice/language_practice_app.rb)

## Language Practice Plus

<img src="./assets/icons/language-practice-plus.png" width="40px"/>

This is a language learning application where conversations start with the assistant's speech. The assistant's speech is played back in a synthesized voice. To speak, press the Enter key to start speech input, and press Enter again to stop speech input. The assistant's response will include linguistic advice in addition to the usual content. The language advice is presented only as text and not as text-to-speech.

Recipe file: [language_practice_plus_app.rb](https://github.com/yohasebe/monadic-chat/blob/main/docker/services/ruby/apps/language_practice_plus/language_practice_plus_app.rb)

## Novel Writer

<img src="./assets/icons/novel.png" width="40px"/>

This is an application for collaboratively writing a novel with an assistant. Craft a novel with engaging characters, vivid descriptions, and compelling plots. Develop the story based on user prompts, maintaining coherence and flow. 

Recipe file: [novel_writer_app.rb](https://github.com/yohasebe/monadic-chat/blob/main/docker/services/ruby/apps/novel_writer/novel_writer_app.rb)

## PDF Navigator

<img src="./assets/icons/pdf-navigator.png" width="40px"/> This is an application that reads a PDF file, and the assistant answers the user's questions based on its content. First, click on the "Upload PDF" button and specify the file. The content of the file will be divided into segments of approximately max_tokens length, and the text embedding will be calculated for each segment. When input is received from the user, the text segment that is closest to the text embedding value of the input text is given to GPT along with the user's input value, and an answer is generated based on that content.

Recipe file: [pdf_navigator_app.rb](https://github.com/yohasebe/monadic-chat/blob/main/docker/services/ruby/apps/pdf_navigator/pdf_navigator_app.rb)

<img src="./assets/images/rag.png" width="600px"/>

## Cohere Command R (Chat/Code Interpreter)

<img src="./assets/icons/c.png" width="40px"/>

This app accesses the Cohere Command R API, instead of the OpenAI's API. Please set your API token in `~/monadic/data/.env`.

Example:

```
COHERE_API_KEY=api_key
```

Recipe file: [talk_to_cohere_app.rb](https://github.com/yohasebe/monadic-chat/blob/main/docker/services/ruby/apps/talk_to_cohere/talk_to_cohere_app.rb)

## Anthropic Claude (Chat/Code Interpreter)

<img src="./assets/icons/a.png" width="40px"/>

This app accesses the Anthropic Claude API, instead of the OpenAI's API. Please set your API token in `~/monadic/data/.env`.

Example:

```
ANTHROPIC_API_KEY=api_key
```

Recipe file: [talk_to_claude_app.rb](https://github.com/yohasebe/monadic-chat/blob/main/docker/services/ruby/apps/talk_to_claude/talk_to_claude_app.rb)

## Google Gemini (Chat)

<img src="./assets/icons/google.png" width="40px"/>

This app accesses the Google Gemini API, instead of the OpenAI's API. Please set your API token in `~/monadic/data/.env`.

Example:

```
GEMINI_API_KEY=api_key
```

Recipe file: [talk_to_gemini_app.rb](https://github.com/yohasebe/monadic-chat/blob/main/docker/services/ruby/apps/talk_to_gemini/talk_to_gemini_app.rb)

## Mistral AI (Chat)

<img src="./assets/icons/m.png" width="40px"/>

This app accesses the Mistral AI API, instead of the OpenAI's API. Please set your API token in `~/monadic/data/.env`.

Example:

```
MISTRAL_API_KEY=api_key
```

Recipe file: [talk_to_mistral_app.rb](https://github.com/yohasebe/monadic-chat/blob/main/docker/services/ruby/apps/talk_to_mistral/talk_to_mistral_app.rb)

## Translate

<img src="./assets/icons/translate.png" width="40px"/>

The assistant will translate the user's input text into another language. First, the assistant will ask for the target language. Then, the input text will be translated into the target language. If you want the assistant to use a specific translation, please put parentheses after the relevant part of the input text and specify the translation in the parentheses.

Recipe file: [translate_app.rb](https://github.com/yohasebe/monadic-chat/blob/main/docker/services/ruby/apps/translate/translate_app.rb)

## Voice Chat

<img src="./assets/icons/voice-chat.png" width="40px"/>

This app enables users to chat using voice through OpenAI's Whisper API and the browser's text-to-speech API. The initial prompt is the same as the one for the Chat app. Please note that a web browser with the latter API, such as Google Chrome or Microsoft Edge, is required.

Recipe file: [voice_chat_app.rb](https://github.com/yohasebe/monadic-chat/blob/main/docker/services/ruby/apps/voice_chat/voice_chat_app.rb)

## Voice Interpreter

<img src="./assets/icons/voice-chat.png" width="40px"/>

The assistant will translate the user's input text into another language and speak it using text-to-speech voice synthesis. First, the assistant will ask for the target language. Then, the input text will be translated into the target language.

Recipe file: [voice_interpreter_app.rb](https://github.com/yohasebe/monadic-chat/blob/main/docker/services/ruby/apps/voice_interpreter/voice_interpreter_app.rb)

## Wikipedia

<img src="./assets/icons/wikipedia.png" width="40px"/>

This is essentially the same as Chat, but for questions that GPT cannot answer, such as questions about events that occurred after the language model cutoff time, it searches Wikipedia to answer them. If the query is in a non-English language, the Wikipedia search is performed in English, and the results are translated into the original language.

Recipe file: [wikipedia_app.rb](https://github.com/yohasebe/monadic-chat/blob/main/docker/services/ruby/apps/wikipedia/wikipedia_app.rb)

## Math Tutor

<img src="./assets/icons/math.png" width="40px"/>

This is an application that allows an AI chatbot to respond using MathJax mathematical notation. Please note that while this app can display mathematical notations, the math calculation ability is based on OpenAI's GPT models, which are known to occasionally produce errors. Therefore, please use this app with caution when accuracy in calculations is required.

Recipe file: [math_tutor_app.rb](https://github.com/yohasebe/monadic-chat/blob/main/docker/services/ruby/apps/math_tutor/math_tutor_app.rb)

## Image Generator

<img src="./assets/icons/image-generator.png" width="40px"/> This is an app that generates images based on a description. If the prompt is not concrete enough or if it is written in a language other than English, the app will return an improved prompt and asks if the user wants to proceed with the improved prompt. It uses the Dall-E 3 API. The generated images are saved in the `Shared Folder` and displayed in the chat.

The generated images are saved in the `Shared Folder` and displayed in the chat.

Recipe file: [image_generator_app.rb](https://github.com/yohasebe/monadic-chat/blob/main/docker/services/ruby/apps/image_generator/image_generator_app.rb)

## Mail Composer

<img src="./assets/icons/mail-composer.png" width="40px"/>

This is an application for writing draft novels of email messages in collaboration with an assistant. The assistant writes the email draft according to the user's requests and specifications.

Recipe file: [mail_composer_app.rb](https://github.com/yohasebe/monadic-chat/blob/main/docker/services/ruby/apps/mail_composer/mail_composer_app.rb)


## Flowchart Grapher

<img src="./assets/icons/diagram-draft.png" width="40px"/> This application hep you visualize data leveraging mermaid.js. Give any data you have or a description of the data,
and the agent will provide the mermaid code for a flow chart and display the chart.

Recipe file: [flowchart_grapher_app.rb](https://github.com/yohasebe/monadic-chat/blob/main/docker/services/ruby/apps/flowchart_grapher/flowchart_grapher_app.rb)

## Music Composer

<img src="./assets/icons/music.png" width="40px"/>

This is an app that writes a simple sheet music using the ABC notation. The assistant will ask for the instrument, the genre, and the style of music. Then, the assistant will display the sheet music and you can play it using the embedded MIDI player.

Recipe file: [music_composer_app.rb](https://github.com/yohasebe/monadic-chat/blob/main/docker/services/ruby/apps/music_composer/music_composer_app.rb)

## Content Reader

<img src="./assets/icons/document-reader.png" width="40px"/>

This application features an AI chatbot designed to examine and elucidate the contents of any imported file or web URL. The explanations are presented in an accessible and beginner-friendly manner. Users have the flexibility to upload files or URLs encompassing a wide array of text data, including programming code. When URLs are mentioned in your prompt messages, the app automatically retrieves the content, seamlessly integrating it into the conversation with GPT.

To specify a file you want the AI to read, save the file in the `Shared Folder` and provide the file name in your User message. If the AI cannot find the file, check the file name and confirm in your message that it is available from the current code execution environment.

The following file formats are supported:

- PDF
- Microsoft Word (docx)
- Microsoft PowerPoint (pptx)
- Microsoft Excel (xlsx)
- CSV
- Text (txt)

It is also possible to read the contents of an image file (PNG, JPEG, etc.) and have the AI recognize and explain the content. Additionally, you can read the contents of an audio file (MP3, etc.) and output the content as text.

Recipe file: [content_reader_app.rb](https://github.com/yohasebe/monadic-chat/blob/main/docker/services/ruby/apps/content_reader/content_reader_app.rb)

## Code Interpreter

<img src="./assets/icons/code-interpreter.png" width="40px"/>

This is an application that allows AI to create and execute program code. The execution of the program uses a Python environment within a Docker container. The text data and images obtained as execution results are saved in the `Shared Folder` and also displayed in the chat. 

If you have files (such as Python code or CSV data) that you want the AI to read, save the files in the `Shared Folder` and specify the file name in the User message. If the AI cannot find the file, please check the file name and ensure that it is available from the current code execution environment.

Recipe file: [code_interpreter_app.rb](https://github.com/yohasebe/monadic-chat/blob/main/docker/services/ruby/apps/code_interpreter/code_interpreter_app.rb)

## Jupyter Notebook

<img src="./assets/icons/jupyter-notebook.png" width="40px"/>

This is an application that allows AI to create a Jupyter notebook, add cells to it, and execute the code in the cells. The execution of the code uses a Python environment within a Docker container and the results will be overwritten in the Jupyter notebook. The Jupyter notebook file is saved in the `Shared Folder`.

Recipe file: [jupyter_notebook_app.rb](https://github.com/yohasebe/monadic-chat/blob/main/docker/services/ruby/apps/jupyter_notebook/jupyter_notebook_app.rb)

## Coding Assistant

<img src="./assets/icons/coding-assistant.png" width="40px"/>

This is an application for writing computer programming code. possible. You can interact with a friendly but professional software engineer who answers various questions, writes computer program code, makes decent suggestions, and gives helpful advice in response to your prompts.

Recipe file: [coding_assistant_app.rb](https://github.com/yohasebe/monadic-chat/blob/main/docker/services/ruby/apps/coding_assistant/coding_assistant_app.rb)

## Video Describer

<img src="./assets/icons/video.png" width="40px"/>

This is an application that analyzes video content and provides a description of the video. The AI analyzes the video content and provides a detailed explanation of what is happening. Internally, the app extracts frames from the video and converts them into PNG images in base64 format. Additionally, it extracts audio data from the video and saves it as an MP3 file. Based on these, the AI provides a comprehensive description of the visual and audio information contained in the video file.

To use this application, the user needs to place the video file in the `Shared Folder` and provide the file name. Additionally, the user must specify the frames per second (fps) for frame extraction. If the total frames exceed 50, only 50 frames will be extracted proportionally from the video.

Recipe file: [video_describer_app.rb](https://github.com/yohasebe/monadic-chat/blob/main/docker/services/ruby/apps/video_describer/video_describer_app.rb)

<!--
## Discourse Analysis

<img src="./assets/icons/discourse-analysis.png" width="40px"/>

This is an application for analyzing and summarizing the user's discourse. The AI generates a summary of the user's messages, identifies the main topics, classifies the sentence types, and determines the sentiment of the messages. This app uses the monadic feature of the Monadic Chat framework. It accumulates and summarizes the past discourse contents and passes them over to the following conversation turns.

Recipe file: [discourse_analysis_app.rb](https://github.com/yohasebe/monadic-chat/blob/main/docker/services/ruby/apps/discourse_analysis/discourse_analysis_app.rb)
-->

## Speech Draft Helper

<img src="./assets/icons/speech-draft-helper.png" width="40px"/>

This app allows the user to submit a speech draft in the form of just a text string, a Word file, or a PDF file. The app will then analyze it and return a revised version. The app will also provide suggestions for improvement and tips on how to make the speech more engaging and effective if the user needs them. if the user needs them Besides, it can also provide an mp3 file of the speech.

Recipe file: [speech_draft_helper_app.rb](https://github.com/yohasebe/monadic-chat/blob/main/docker/services/ruby/apps/speech_draft_helper/speech_draft_helper_app.rb)

<script src="https://cdn.jsdelivr.net/npm/jquery@3.5.0/dist/jquery.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/lightbox2@2.11.3/src/js/lightbox.js"></script>

---

<script>
  function copyToClipBoard(id){
    var copyText =  document.getElementById(id).innerText;
    document.addEventListener('copy', function(e) {
        e.clipboardData.setData('text/plain', copyText);
        e.preventDefault();
      }, true);
    document.execCommand('copy');
    alert('copied');
  }
</script>
