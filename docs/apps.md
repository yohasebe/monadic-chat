---
title: Monadic Chat
layout: default
---

# Base Apps
{:.no_toc}

[English](/monadic-chat-web/base_apps) |
[日本語](/monadic-chat-web/base_apps_ja)

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

<img src="./assets/icons/language-practice-plus.png" width="40px"/> This is a language learning application where conversations start with the assistant’s speech. The assistant’s speech is played back in a synthesized voice. To speak, press the Enter key to start speech input, and press Enter again to stop speech input. The assistant’s response will include linguistic advice in addition to the usual content. The language advice is presented only as text and not as text-to-speech.

## Novel

<img src="./assets/icons/novel.png" width="40px"/> This is an application for collaboratively writing a novel with an assistant. The assistant writes a paragraph summarizing the theme, topic, or event presented in the prompt. Always use the same language as the assistant in your response.

## PDF Navigator

<img src="./assets/icons/pdf-navigator.png" width="40px"/> This is an application that reads a PDF file, and the assistant answers the user's questions based on its content. First, click on the "Upload PDF" button and specify the file. The content of the file will be divided into segments of approximately max_tokens length, and the text embedding will be calculated for each segment. When input is received from the user, the text segment that is closest to the text embedding value of the input text is given to GPT along with the user's input value, and an answer is generated based on that content.

## Translate

<img src="./assets/icons/translate.png" width="40px"/> The assistant will translate the user's input text into another language. First, the assistant will ask for the target language. Then, the input text will be translated into the target language. If you want the assistant to use a specific translation, please put parentheses after the relevant part of the input text and specify the translation in the parentheses.

## Voice Chat

<img src="./assets/icons/voice-chat.png" width="40px"/> This app enables users to chat using voice through OpenAI’s Whisper API and the browser’s text-to-speech API. The initial prompt is the same as the one for the Chat app. Please note that a web browser with the latter API, such as Google Chrome or Microsoft Edge, is required.

## Wikipedia

<img src="./assets/icons/wikipedia.png" width="40px"/> This is essentially the same as Chat, but for questions that GPT cannot answer, such as questions about events that occurred after the language model cutoff time, it searches Wikipedia to answer them. If the query is in a non-English language, the Wikipedia search is performed in English, and the results are translated into the original language.

## Linguistic Analysis

<img src="./assets/icons/linguistic-analysis.png" width="40px"/> This app utilizes Monadic Chat’s feature that allows for updating a pre-specified JSON object with multiple properties while providing a regular response. As the main response to the user’s query, it returns a syntactic structure of the input sentence. In the process, the app updates the values of the JSON object with the properties of `topic`, `sentence_type`, and `sentiment`.

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
