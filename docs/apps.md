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

## Talk to Cohere Command R

<img src="./assets/icons/c.png" width="40px"/>

This app accesses the Cohere Command R API to answer questions about a wide range of topics. Please set your API token and the model name in `~/monadic/data/.env`.

Example:

```
COHERE_API_KEY=api_key
COHERE_MODEL=command-r-plus
```

Recipe file: [talk_to_cohere_app.rb](https://github.com/yohasebe/monadic-chat/blob/main/docker/services/ruby/apps/talk_to_cohere/talk_to_cohere_app.rb)

## Talk to Anthropic Claude

<img src="./assets/icons/a.png" width="40px"/>

This app accesses the Anthropic Claude API to answer questions about a wide range of topics. Please set your API token and the model name in `~/monadic/data/.env`.

Example:

```
ANTHROPIC_API_KEY=api_key
ANTHROPIC_MODEL=claude-3-opus-20240229
```

Recipe file: [talk_to_claude_app.rb](https://github.com/yohasebe/monadic-chat/blob/main/docker/services/ruby/apps/talk_to_claude/talk_to_claude_app.rb)

## Talk to Google Gemini

<img src="./assets/icons/google.png" width="40px"/>

This app accesses the Google Gemini API to answer questions about a wide range of topics. Please set your API token and the model name (with `models/` prefix) in `~/monadic/data/.env`.

Example:

```
GEMINI_API_KEY=api_key
GEMINI_MODEL=models/gemini-1.5-pro-latest
```

Recipe file: [talk_to_gemini_app.rb](https://github.com/yohasebe/monadic-chat/blob/main/docker/services/ruby/apps/talk_to_gemini/talk_to_gemini_app.rb)

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
