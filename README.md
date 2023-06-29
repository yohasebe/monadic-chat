<p>&nbsp;</p>

<div align="center"> <img src="./assets/images/monadic-chat-logo.png" width="600px"/></div>

<div align="center" style="color: #777777 "><b>A highly configurable Ruby framework for creating intelligent chatbots </b></div>

<p>&nbsp;</p>

## About

🌟 **Monadic Chat** is a highly configurable web application framework for creating and using intelligent chatbots, leveraging the power of OpenAI's Chat and Whisper APIs and the Ruby programming language.

- [Monadic Chat (English)](https://yohasebe.github.io/monadic-chat-web/overview)
- [Monadic Chat (日本語)](https://yohasebe.github.io/monadic-chat-web/overview_ja)

⚠️  **Important Notice**

This software is currently under active development and is subject to frequent changes. Some features may still be unstable at this moment. Please exercise caution when using it.

📢 **Call for Contributions**

I welcome contributions that can help refine this software, such as code improvements, adding tests, and documentation. Your support would be greatly appreciated.

🔄 **Project Restructuring**

The command-line program “Monadic Chat” has undergone some changes. It has been renamed to “Monadic Chat CLI” and moved to a separate repository. Moving forward, Monadic Chat will be developed as a web-based application in this repository.
 
- [Monadic Chat](https://github.com/yohasebe/monadic-chat) (this repository)
- [Monadic Chat CLI](https://github.com/yohasebe/monadic-chat-cli)

<p>&nbsp;</p>
<div align="center"><img src="./assets/images/screenshot-01.png" width="800px"/></div>
<p>&nbsp;</p>

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

## Author

Yoichiro HASEBE

[yohasebe@gmail.com](yohasebe@gmail.com)

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
