<div id="monadic-chat"><img src="https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docs/assets/images/monadic-chat-logo.png" width="600px"/></div>

<div><img src="https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docs/assets/images/basic-architecture.png" width="800px"/></div>

## Overview

**Monadic Chat** is a locally hosted web application designed to create and utilize intelligent chatbots. By providing a Linux environment on Docker to GPT and other LLMs, it allows the execution of advanced tasks that require external tools. It supports voice interaction, image and video recognition and generation, and AI-to-AI chat, making it useful not only for various AI applications but also for developing and researching AI-powered applications.

Available for **Mac**, **Windows**, and **Linux** (Debian/Ubuntu) with easy-to-use installers.

[Changelog](https://yohasebe.github.io/monadic-chat/#/changelog)

## Getting Started

- [**Documentation**](https://yohasebe.github.io/monadic-chat) (English/Japanese)
- [**Installation**](https://yohasebe.github.io/monadic-chat/#/getting-started/installation)

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
- 💬 Support for both **Human/AI chat** and **AI/AI chat**
- ✨ Chat functionality utilizing **multiple AI models**
- 🔄 **Automatic updates** with in-app notifications and download management
- 🌐 **Server mode** for multiple clients to connect to a single server
- 🔍 **Built-in browser** for viewing the web interface within the application

### AI + Linux Environment

- 🐧 Provision of a **Linux environment** to AI agents
- 🐳 Tools available to LLMs via **Docker containers**
  - Linux (+ apt)
  - Ruby (+ gem)
  - Python (+ pip)
  - PGVector (+ PostgreSQL)
  - Selenium (+ Chrome/Chromium)
- ⚡️ Use of LLMs via **online and local** APIs
- 📦 Each container can be managed via **SSH**
- 📓 Integration with **Jupyter Notebook**

### AI User & Conversation Management

- 🧠 **AI User feature** allowing the AI to generate responses as if coming from a human user
- 🎭 Maintains the user's **tone, style, and language** in AI-generated user messages
- 🌐 Works with **multiple AI providers** including OpenAI, Claude, Gemini, Mistral, and more
- 💾 **Export/import** chat data
- 📝 **Edit** chat data (add, delete, edit)
- 💬 Specify the number of messages to send to the API as **context size**
- 📜 Set **roles** for messages (user, assistant, system)
- 🔢 Generate and import/export **text embeddings** from PDFs
- 📼 **Logging** of code execution and tool/function use for debugging

### Voice Interaction

- 🔈 **Text-to-speech** for AI assistant responses (OpenAI or Elevenlabs)
- 🎙️ **Speech recognition** using the Speech-to-Text API (+ display of p-values)
- 🗺️ **Automatic language detection** for text-to-speech
- 🗣️ Choose the **language and voice** for text-to-speech
- 😊 **Interactive conversation** with AI agents using speech recognition and text-to-speech
- 🎧 Save AI assistant's spoken responses as **MP3 audio** files

### Image/Video Recognition and Generation

- 🖼️ **Image generation** using OpenAI's gpt-image-1 model, Google Imagen, and xAI Grok
- ✏️ **Image editing** with OpenAI's gpt-image-1 model for modifying existing images
- 🎭 **Mask editor** for precise control over which areas of an image to edit
- 👀 Recognition and description of **uploaded images**
- 📚 Upload and recognition of **multiple images**
- 🎥 Recognition and description of **uploaded video content and audio**

### Configuration and Extension

- 💡 Specify and edit **API parameters** and **system prompts**
- 🧩 Create custom applications with **Monadic DSL** (Domain Specific Language)
- 📊 Create diagrams with **DrawIO Grapher** and **Mermaid Grapher** apps
- 💎 Extend functionality using the **Ruby** programming language
- 🐍 Extend functionality using the **Python** programming language
- 🔍 **Web search** capabilities using the [Tavily](https://tavily.com/) API and OpenAI's built-in search feature
- 🌎 Perform **web scraping** using Selenium
- 📦 Add custom **Docker containers**

### Support for Multiple LLM APIs

- 👥 Web API
  - [OpenAI GPT](https://platform.openai.com/docs/overview)
  - [Google Gemini](https://ai.google.dev/gemini-api)
  - [Anthropic Claude](https://www.anthropic.com/api)
  - [Cohere](https://cohere.com/)
  - [Mistral AI](https://docs.mistral.ai/api/)
  - [xAI Grok](https://x.ai/api)
  - [Perplexity](https://docs.perplexity.ai/home)
  - [DeepSeek](https://www.deepseek.com/)
- 🦙 [Ollama](https://ollama.com/) in the local Docker environment
  - Llama
  - Phi
  - Mistral
  - Gemma
  - DeepSeek
- 🤖💬🤖 **AI-to-AI** chat functionality

### Conversations as Monads

- ♻️ In addition to the main response from the AI assistant, it is possible to manage the (invisible) **state** of the conversation by obtaining additional responses and updating values within a predefined JSON object

## Developer

Yoichiro HASEBE<br />
[yohasebe@gmail.com](yohasebe@gmail.com)

## License

This software is available as open source under the terms of the [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0).