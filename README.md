<p>&nbsp;</p>

<div align="center"> <img src="./assets/images/monadic-chat-logo.png" width="600px"/></div>

<div align="center" style="color: #777777 "><b>Grounding AI Chatbots with Full Linux Environment on Docker </b></div>

<p>&nbsp;</p>

## Overview

🌟 **Monadic Chat** is a versatile web application framework designed to create and utilize intelligent chatbots. By providing a full-fledged Linux environment on Docker to GPT-4 and other LLMs, it allows the chatbots to perform advanced tasks that require external tools for searching, coding, testing, visualization, and more.

- Documentation
  - [English](https://yohasebe.github.io/monadic-chat/overview)
  - [日本語](https://yohasebe.github.io/monadic-chat/overview_ja)

- Download Installer
  - [MacOS (Apple Silicon/Intel)](https://yohasebe.github.io/monadic-chat/installation#macos)
  - [Windows](https://yohasebe.github.io/monadic-chat/installation#windows)

<p>&nbsp;</p>
<div align="center"><img src="./assets/images/screenshot-01.png" width="700px"/></div>

<div align="center"><img src="./assets/images/screenshot-02.png" width="500px"/></div>

<div align="center"><img src="./assets/images/monadic-chat-architecture.png" width="800px"/></div>

<p>&nbsp;</p>

> There are two types of Monadic Chat: one is a web browser-based app provided in this repository, which is installed using Docker. The other is a command line application, which is provided as a RubyGem.

- [Monadic Chat](https://github.com/yohasebe/monadic-chat) (this repo) 
- [Monadic Chat CLI](https://github.com/yohasebe/monadic-chat-cli)

## Features

### Basic Structure

- 🤖 Powered by **GPT-4** via OpenAI's Chat API, with unlimited conversation turns
- 👩‍💻 Multi-OS support using **Docker** for Mac, Windows, or Linux

### Data Management

- 💾 **Export/import** messages and settings
- 💬 Specify the number of recent messages (**active messages**) to send to the API, while storing and exporting older messages (**inactive messages**)
- 🔢 Generate **text embeddings** from data in multiple **PDF files** and query their content using OpenAI's text embedding API

<div align="center"><img src="./assets/images/rag.png" width="600px"/></div>

### Voice Interaction

- 🎙️ Automatic transcription of **microphone input** using OpenAI's Whisper API
- 🔈 Natural **text-to-speech** voices for AI assistant responses
- 🗺️ **Automatic language detection** for appropriate text-to-speech playback
- 😊 **Voice chat** with the AI agent using speech recognition and text-to-speech

### Image Generation

- 🖼️ **Generate images** from text prompt using OpenAI's DALL·E 3 API

### Image Understanding

- 👀 **Local images** can be uploaded and let AI assistant analyze what are in them

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

Yoichiro HASEBE<br />
[yohasebe@gmail.com](yohasebe@gmail.com)

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
