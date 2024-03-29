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

<img src="./assets/icons/chat.png" width="40px"/> This is the standard application for monadic chat. It can be used in basically the same way as ChatGPT.

## Language Practice

<img src="./assets/icons/language-practice.png" width="40px"/> This is a language learning application where conversations begin with the assistant's speech. The assistant's speech is played back in a synthesized voice. To speak, press the Enter key to start speech input, and press Enter again to stop speech input.

## Language Practice Plus

<img src="./assets/icons/language-practice-plus.png" width="40px"/> This is a language learning application where conversations start with the assistant's speech. The assistant's speech is played back in a synthesized voice. To speak, press the Enter key to start speech input, and press Enter again to stop speech input. The assistant's response will include linguistic advice in addition to the usual content. The language advice is presented only as text and not as text-to-speech.

## Novel Writer

<img src="./assets/icons/novel.png" width="40px"/> This is an application for collaboratively writing a novel with an assistant. The assistant writes a paragraph summarizing the theme, topic, or event presented in the prompt. Always use the same language as the assistant in your response.

## PDF Navigator

<img src="./assets/icons/pdf-navigator.png" width="40px"/> This is an application that reads a PDF file, and the assistant answers the user's questions based on its content. First, click on the "Upload PDF" button and specify the file. The content of the file will be divided into segments of approximately max_tokens length, and the text embedding will be calculated for each segment. When input is received from the user, the text segment that is closest to the text embedding value of the input text is given to GPT along with the user's input value, and an answer is generated based on that content.

<img src="./assets/images/rag.png" width="600px"/>

## Translate

<img src="./assets/icons/translate.png" width="40px"/> The assistant will translate the user's input text into another language. First, the assistant will ask for the target language. Then, the input text will be translated into the target language. If you want the assistant to use a specific translation, please put parentheses after the relevant part of the input text and specify the translation in the parentheses.

## Voice Chat

<img src="./assets/icons/voice-chat.png" width="40px"/> This app enables users to chat using voice through OpenAI's Whisper API and the browser's text-to-speech API. The initial prompt is the same as the one for the Chat app. Please note that a web browser with the latter API, such as Google Chrome or Microsoft Edge, is required.

## Wikipedia

<img src="./assets/icons/wikipedia.png" width="40px"/> This is essentially the same as Chat, but for questions that GPT cannot answer, such as questions about events that occurred after the language model cutoff time, it searches Wikipedia to answer them. If the query is in a non-English language, the Wikipedia search is performed in English, and the results are translated into the original language.

## Linguistic Analysis

<img src="./assets/icons/linguistic-analysis.png" width="40px"/> This app utilizes Monadic Chat's feature that allows for updating a pre-specified JSON object with multiple properties while providing a regular response. As the main response to the user's query, it returns a syntactic structure of the input sentence. In the process, the app updates the values of the JSON object with the properties of `topic`, `sentence_type`, and `sentiment`.

## Math Tutor

<img src="./assets/icons/math.png" width="40px"/> This is an application that allows an AI chatbot to respond using MathJax mathematical notation. Please note that while this app can display mathematical notations, the math calculation ability is based on OpenAI's GPT models, which are known to occasionally produce errors. Therefore, please use this app with caution when accuracy in calculations is required.

## Image Generator

<img src="./assets/icons/image-generator.png" width="40px"/> This is an application for image generation. When an initial prompt is entered, the image is generated using OpenAI's DALL-E API (`dall-e-3`). If you specify GPT 4.0 as the model for the conversation, you can gradually improve the prompt through interaction with the AI chatbot to get the desired image.

## Mail Composer

<img src="./assets/icons/mail-composer.png" width="40px"/> This is an application for writing draft novels of email messages in collaboration with an assistant. The assistant writes the email draft according to the user's requests and specifications.

## Document Reader

<img src="./assets/icons/document-reader.png" width="40px"/> This is an application for reading a document. The assistant will read the document and explain its content from the beginning to the end splitting the content into segments of small size. The user can ask questions about the content of the document, and the assistant will answer them based on the content of the document.

## Diagram Draft

<img src="./assets/icons/diagram-draft.png" width="40px"/> This is an application for drafting diagrams. The assistant will create a diagram using the Mermaid library based on the user's input. The user can ask the assistant to create a diagram by specifying the type of diagram and the content of the diagram.

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
