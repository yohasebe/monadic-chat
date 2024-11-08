# Monadic Chat

![Monadic Chat Architecture](/assets/images/monadic-chat-architecture.svg ':size=800')

## Overview

**Monadic Chat** is a locally hosted web application designed to create and utilize intelligent chatbots. By providing a Linux environment on Docker to GPT-4 and other LLMs, it allows the execution of advanced tasks that require external tools. It supports voice interaction, image and video recognition and generation, and AI-to-AI chat, making it useful not only for various AI applications but also for developing and researching AI-powered applications.

## What is Grounding?

Monadic Chat is an AI framework grounded in the real world. The term **grounding** here has two meanings.

Typically, discourse involves context and purpose, which are referenced and updated as the conversation progresses. Just as in human-to-human conversations, **maintaining and referencing context** is useful, or even essential, in conversations with AI agents. By defining the format and structure of meta-information in advance, it is expected that conversations with AI agents will become more purposeful. The process of users and AI agents advancing discourse while sharing a foundational background is the first meaning of "grounding."

Human users can use various tools to achieve their goals. However, in many cases, AI agents cannot do this. Monadic Chat enables AI agents to execute tasks using external tools by providing them with a **freely accessible Linux environment**. This allows AI agents to more effectively support users in achieving their goals. Since it is an environment on Docker containers, it does not affect the host system. This is the second meaning of "grounding."

## Features

### Basic Structure

- 🤖 Use of **AI assistants** via various web and local APIs
- ⚛️ Easy Docker environment setup using a GUI app with **Electron**
- 📁 **Synchronized folder** for syncing local files with files inside Docker containers
- 📦 User-added **apps** and **containers** functionality
- 👩💬 Support for both **human↔️AI chat** and 🤖💬 **AI↔️AI chat**
- ✨ Chat functionality utilizing **multiple AI models**

### AI + Linux Environment

- 🐧 Provision of a **Linux environment** to AI agents
- 🐳 Tools available to LLMs via **Docker containers**
  - Linux (+ apt)
  - Ruby (+ gem)
  - Python (+ pip)
  - PGVector (+ PostgreSQL)
  - Selenium (+ Chrome/Chromium)
- ⚡️ Use of LLMs via online and local APIs
- 📦 Each container can be managed via **SSH**
- 📓 Integration with **Jupyter Notebook**

### Data Management

- 💾 **Export/import** chat data
- 📝 **Edit** chat data (add, delete, edit)
- 💬 Specify the number of messages to send to the API as **context size**
- 📜 Set **roles** for messages (user, assistant, system)
- 🔢 Generate and import/export **text embeddings** from PDFs

### Voice Interaction

- 🎙️ **Speech recognition** using the Whisper API (+ display of p-values)
- 🔈 **Text-to-speech** for AI assistant responses
- 🗺️ **Automatic language detection** for text-to-speech
- 🗣️ Choose the **language and voice** for text-to-speech
- 😊 **Interactive conversation** with AI agents using speech recognition and text-to-speech
- 🎧 Save AI assistant's spoken responses as **MP3 audio** files

### Image/Video Recognition and Generation

- 🖼️ **Image generation** using DALL·E 3 API
- 👀 Recognition and description of **uploaded images**
- 📚 Upload and recognition of **multiple images**
- 🎥 Recognition and description of **uploaded video content and audio**

### Configuration and Extension

- 💡 Specify and edit **API parameters** and **system prompts**
- 💎 Extend functionality using the **Ruby** programming language
- 🐍 Extend functionality using the **Python** programming language
- 🌎 Perform **web scraping** using Selenium
- 📦 Add custom **Docker containers**

### Support for Multiple LLM APIs

- 👥 Support for the following LLM **Web APIs**:
  - [OpenAI GPT-4](https://platform.openai.com/docs/overview)
  - [Google Gemini](https://ai.google.dev/gemini-api)
  - [Anthropic Claude](https://www.anthropic.com/api)
  - [Cohere Command R](https://cohere.com/)
  - [Mistral AI](https://docs.mistral.ai/api/)
- 🦙 Use of LLMs in a local environment on Docker using **[Ollama](https://ollama.com/)**
  - Llama
  - Phi
  - Mistral
  - Gemma
- 🤖💬🤖 **AI-to-AI** chat functionality

### Conversations as Monads

- ♻️ In addition to the main response from the AI assistant, it is possible to manage the (invisible) **state** of the conversation by obtaining additional responses and updating values within a predefined JSON object

## Developer

Yoichiro HASEBE<br />
[yohasebe@gmail.com](yohasebe@gmail.com)

## License

This software is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
