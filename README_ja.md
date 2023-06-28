<p>&nbsp;</p>

<div align="center"> <img src="./assets/images/monadic-chat-logo.png" width="600px"/></div>

<div align="center" style="color: #777777 "><b>A highly configurable Ruby framework for creating intelligent chatbots </b></div>

<p>&nbsp;</p>


📢 **Important Notice**

> This software is currently under active development and is subject to frequent changes. Please exercise caution when using it.
>
> I appreciate any contributions that can help refine this software, such as code improvements, adding tests, and documentation. Your support would be greatly valued in shaping the future of this project.

&nbsp;

🔄 **Project Restructuring**

> The command-line program "Monadic Chat" has undergone some changes. It has been renamed to "Monadic Chat CLI" and moved to a separate repository. Moving forward, Monadic Chat will be developed as a web-based application on this repository.
>
> - Monadic Chat (this repository): [https://github.com/yohasebe/monadic-chat](https://github.com/yohasebe/monadic-chat)
> - Monadic Chat CLI: [https://github.com/yohasebe/monadic-chat-cli](https://github.com/yohasebe/monadic-chat-cli)

<p>&nbsp;</p>
<div align="center"><img src="./assets/images/screenshot-01.png" width="800px"/></div>
<p>&nbsp;</p>

## About

🌟 **Monadic Chat** is a highly configurable web application framework for creating and using intelligent chatbots, leveraging the power of OpenAI's Chat and Whisper APIs and the Ruby programming language.

## Features

### Basic Structure

- 🤖 Powered by **GPT-3.5** or **GPT-4** via OpenAI's Chat API, with unlimited conversation turns
- 👩‍💻 Easy installation using **Docker** for Mac, Windows, or Linux

### Data Management

- 💾 **Export/import** messages functionality
- 💬 Specify the number of recent messages (**active messages**) to send to the API, while storing and exporting older messages (**inactive messages**)
- 🔢 Generate **text embeddings** from data in multiple **PDF files** and query their content using OpenAI's text embedding API

### Voice Interaction

- 🎙️ Automatic transcription of **microphone input** using OpenAI's Whisper API
- 🔈 **Text-to-speech** functionality for AI assistant responses
- 🗣️ Choose the **language and voice** for text-to-speech (available on Google Chrome or Microsoft Edge)
- 🗺️ **Automatic language detection** for appropriate text-to-speech playback
- 😊 Enable **voice conversations** with the AI agent using speech recognition and text-to-speech

### Configuration and Extension

- 💡 Customize the AI agent's behavior by specifying **API parameters** and the **system prompt**
- 💎 Extend functionality using the **Ruby** programming language

### Message Editing

- 📝 **Edit** previous messages and retry when the desired AI agent response is not obtained
- 🗑️ **Delete** specific messages from previous conversations
- 📜 **Add** preceding messages with user, assistant, or system roles

### Advanced

- 🪄 Obtain additional information alongside the primary AI assistant response and store it as the **conversation state** in a predefined JSON object

## Installation

See [Setting up Monadic Chat](https://yohasebe.github.io/monadic-chat-web/setup)

## Settings and Options

### GPT Settings
<img src="./assets/images/gpt-settings.png" width="600px"/>

**API Token** <br />
ここにはOpenAIのAPI keyを入れます。有効なAPI keyが確認されると、Monadic Chatのルート・ディレクトリに`.env`というファイルが作成され、その中に`OPENAI_API_KEY`という変数が定義され、その後はこの変数の値が用いられます。

**Base App** <br />
Monadic Chatであらかじめ用意されたアプリの中から1つを選択します。各アプリでは異なるデフォルト・パラメター値が設定されており、固有の初期プロンプトが与えられています。各Base Appの特徴については [Base Apps](#base-apps)を参照してください。

**Select Model** <br />
OpenAIが提供するモデルの中から1つを選びます。各Base Appでデフォルトのモデルが指定されていますが、目的に応じて変更することができます。

**Max Tokens** <br />
Chat APIにパラメターとして送られる「トークンの最大値」を指定します。これにはプロンプトとして送られるテキストのトークン数と、レスポンスとして返ってくるテキストのトークン数が含まれます。OpenAIのAPIにおけるトークンのカウント方法については[What are tokens and how to count them](https://help.openai.com/en/articles/4936856-what-are-tokens-and-how-to-count-them)を参照してください。

**Context Size** <br />
現在進行中のチャットに含まれるやりとりの中で、アクティブなものとして保つ発話の最大数です。アクティブな発話のみがOpenAIのchat APIに文脈情報として送信されます。インアクティブな発話も画面上では参照可能であり、エクスポートの際にも保存対象となります。

**Temperature**<br />
**Top P** <br />
**Presence Penalty** <br />
**Frequency Penalty**

以上の要素はパラメターとしてAPIに送られます。各パラメターの詳細はChat APIの[Reference](https://platform.openai.com/docs/api-reference/chat)を参照してください。

**Initial Prompt**<br />
初期プロンプトとしてAPIに送られるテキストです。会話のキャラクター設定や、レスポンスの形式などを指定することができます。各Base Appの目的に応じたデフォルトのテキストが設定されていますが、自由に変更することが可能です。

**Initiate from the assistant**<br />

このオプションをオンにすると、会話を始める時にアシスタント側が最初の発話を行います。

**Start Session** <br />
このボタンをクリックすると、GPT Settiingsで指定したオプションやパラメターのもとにチャットが開始されます。

## Base Apps

Currently, the following base apps are available for use. By selecting one of them and changing the parameters or rewriting the initial prompt, you can adjust the behavior of the AI agent. You can export/import the adjusted settings to/from an external JSON file.

### Chat

<img src="./assets/icons/chat.png" width="40px"/> This is the standard application for monadic chat. It can be used in basically the same way as ChatGPT.

### Language Practice

<img src="./assets/icons/language-practice.png" width="40px"/> This is a language learning application where conversations begin with the assistant's speech. The assistant's speech is played back in a synthesized voice. To speak, press the Enter key to start speech input, and press Enter again to stop speech input.

### Language Practice Plus

<img src="./assets/icons/language-practice-plus.png" width="40px"/> This is a language learning application where conversations start with the assistant’s speech. The assistant’s speech is played back in a synthesized voice. To speak, press the Enter key to start speech input, and press Enter again to stop speech input. The assistant’s response will include linguistic advice in addition to the usual content. The language advice is presented only as text and not as text-to-speech.

### Novel

<img src="./assets/icons/novel.png" width="40px"/> This is an application for collaboratively writing a novel with an assistant. The assistant writes a paragraph summarizing the theme, topic, or event presented in the prompt. Always use the same language as the assistant in your response.

### PDF Navigator

<img src="./assets/icons/pdf-navigator.png" width="40px"/> This is an application that reads a PDF file, and the assistant answers the user's questions based on its content. First, click on the "Upload PDF" button and specify the file. The content of the file will be divided into segments of approximately max_tokens length, and the text embedding will be calculated for each segment. When input is received from the user, the text segment that is closest to the text embedding value of the input text is given to GPT along with the user's input value, and an answer is generated based on that content.

### Translate

<img src="./assets/icons/translate.png" width="40px"/> The assistant will translate the user's input text into another language. First, the assistant will ask for the target language. Then, the input text will be translated into the target language. If you want the assistant to use a specific translation, please put parentheses after the relevant part of the input text and specify the translation in the parentheses.

### Voice Chat

<img src="./assets/icons/voice-chat.png" width="40px"/> This app enables users to chat using voice through OpenAI’s Whisper API and the browser’s text-to-speech API. The initial prompt is the same as the one for the Chat app. Please note that a web browser with the latter API, such as Google Chrome or Microsoft Edge, is required.

### Wikipedia

<img src="./assets/icons/wikipedia.png" width="40px"/> This is essentially the same as Chat, but for questions that GPT cannot answer, such as questions about events that occurred after the language model cutoff time, it searches Wikipedia to answer them. If the query is in a non-English language, the Wikipedia search is performed in English, and the results are translated into the original language.

### Linguistic Analysis

<img src="./assets/icons/linguistic-analysis.png" width="40px"/> This app utilizes Monadic Chat’s feature that allows for updating a pre-specified JSON object with multiple properties while providing a regular response. As the main response to the user’s query, it returns a syntactic structure of the input sentence. In the process, the app updates the values of the JSON object with the properties of `topic`, `sentence_type`, and `sentiment`.

## Creating New Apps

UNDER CONSTRUCTION

## Author

Yoichiro HASEBE

[yohasebe@gmail.com](yohasebe@gmail.com)

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
