<div align="center">

<img src="https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docs/assets/images/monadic-chat-logo.png" width="700px" alt="Monadic Chat Logo">

<a href="https://github.com/yohasebe/monadic-chat/releases"><img src="https://img.shields.io/github/v/release/yohasebe/monadic-chat?style=for-the-badge" alt="Release"></a>
<a href="LICENSE"><img src="https://img.shields.io/github/license/yohasebe/monadic-chat?style=for-the-badge" alt="License"></a>
<a href="https://yohasebe.github.io/monadic-chat/#/developer/testing_guide"><img src="https://img.shields.io/badge/tests-1253_passing-success?style=for-the-badge" alt="Tests"></a>
  
  ---
  
  **🎯 Features** · [Multimodal](https://yohasebe.github.io/monadic-chat/#/basic-usage/basic-apps#multimodal-capabilities) · [Web Search](https://yohasebe.github.io/monadic-chat/#/basic-usage/basic-apps#web-search-integration) · [Code Execution](https://yohasebe.github.io/monadic-chat/#/basic-usage/basic-apps#code-interpreter) · [Voice Chat](https://yohasebe.github.io/monadic-chat/#/basic-usage/basic-apps#voice-chat)
  
  **🤖 Providers** · OpenAI · Claude · Gemini · Mistral · Cohere · Perplexity · xAI · DeepSeek · Ollama
  
  **🛠 Built with** · Ruby · Electron · Docker · PostgreSQL · WebSocket
  
  ---
  
  <img src="https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docs/assets/images/basic-architecture.png" width="800px" alt="Monadic Chat Architecture">
  
</div>

## Overview

**Monadic Chat** is a locally hosted web application designed to create and utilize intelligent chatbots. By providing a Linux environment on Docker to GPT and other LLMs, it allows the execution of advanced tasks that require external tools. It supports voice interaction, image and video recognition and generation, and AI-to-AI chat, making it useful not only for various AI applications but also for developing and researching AI-powered applications.

Available for **Mac**, **Windows**, and **Linux** (Debian/Ubuntu) with easy-to-use installers.

[Changelog](https://yohasebe.github.io/monadic-chat/#/changelog)

## Getting Started

- [**Documentation**](https://yohasebe.github.io/monadic-chat) (English/Japanese)
- [**Installation**](https://yohasebe.github.io/monadic-chat/#/getting-started/installation)

> [!IMPORTANT]
> **Breaking Changes**: Version 1.0.0 includes significant changes to configuration management and APIs. See the [Breaking Changes Guide](https://yohasebe.github.io/monadic-chat/#/developer/breaking-changes) for migration instructions.

## What is Grounding?

Monadic Chat is an AI framework grounded in the real world. The term **grounding** here has two meanings.

Typically, discourse involves context and purpose, which are referenced and updated as the conversation progresses. Just as in human-to-human conversations, **maintaining and referencing context** is useful, or even essential, in conversations with AI agents. By defining the format and structure of meta-information in advance, it is expected that conversations with AI agents will become more purposeful. The process of users and AI agents advancing discourse while sharing a foundational background is the first meaning of "grounding."

Human users can use various tools to achieve their goals. However, in many cases, AI agents cannot do this. Monadic Chat enables AI agents to execute tasks using external tools by providing them with a **freely accessible Linux environment**. This allows AI agents to more effectively support users in achieving their goals. The system includes error pattern detection that prevents infinite retry loops, ensuring stable operation. Since it is an environment on Docker containers, it does not affect the host system. Providing an environment for AI agents to not only provide language responses but also to lead to actual actions - this is the second meaning of "grounding."

## Features

### Basic Structure

- 🤖 Use of **AI assistants** via various web and local APIs
- ⚛️ Easy Docker environment setup using a GUI app with **Electron**
- 📁 **Shared folder** for syncing local files with files inside Docker containers
- 📦 User-added **apps** and **containers** functionality
- 💬 Support for both **Human/AI chat** and **AI/AI chat**
- ✨ Chat functionality utilizing **multiple AI models**
- 🔄 **Automatic updates** with in-app notifications and download management
- 🌐 **Server mode** for multiple clients to connect to a single server
- 🔍 **Built-in browser** for viewing the web interface within the application
- ❓ **Help function**: Built-in assistance and documentation with AI agent explanations

### AI + Linux Environment

- 🐧 Provision of a **Linux environment** to AI agents
- 🐳 Tools available to LLMs via **Docker containers**
  - Linux (+ apt)
  - Ruby (+ gem)
  - Python (+ pip, Flask API server)
  - PGVector (+ PostgreSQL)
  - Selenium (+ Chrome/Chromium)
  - Ollama (optional, for local LLM models)
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
- 📋 **Extract content** from URLs and various file formats (PDF, DOCX, PPTX, XLSX, etc.)

### Voice Interaction

- 🔈 **Text-to-speech** for AI assistant responses (OpenAI, Elevenlabs, Google Gemini, or Web Speech API)
- 🎙️ **Speech recognition** using the Speech-to-Text API (whisper-1, gpt-4o-transcribe, gpt-4o-mini-transcribe)
- 🗺️ **Automatic language detection** for text-to-speech
- 🗣️ Choose the **language and voice** for text-to-speech
- 😊 **Interactive conversation** with AI agents using speech recognition and text-to-speech
- 🎧 Save AI assistant's spoken responses as **MP3/WAV audio** files

### Image/Video Recognition and Generation

- 🖼️ **Image generation and editing** using OpenAI's gpt-image-1, Google Imagen 3 & Gemini 2.0 Flash, and xAI Grok
- ✏️ **Image editing** with OpenAI's gpt-image-1 model for modifying existing images
- 🎭 **Mask editor** for precise control over which areas of an image to edit
- 👀 Recognition and description of **uploaded images**
- 📚 Upload and recognition of **multiple images**
- 🎥 Recognition and description of **uploaded video content and audio**
- 🎬 **Video generation** using Google's Veo model for text-to-video and image-to-video creation

### Core Applications

- 💬 **Chat** - Basic conversational AI with web search capabilities (All providers)
- 💬 **Chat Plus** - Enhanced chat with monadic context management (All providers)
- 🔧 **Code Interpreter** - Execute code and perform data analysis (All providers)
- 👨‍💻 **Coding Assistant** - Programming help with code generation and debugging (All providers)
- 📖 **Content Reader** - Extract and analyze content from files and URLs (All providers)
- 🔍 **Research Assistant** - Web search and research with comprehensive analysis (All providers)
- 🎙️ **Voice Chat** - Interactive voice conversations with TTS/STT (All providers)
- 📓 **Jupyter Notebook** - Interactive notebook environment with error auto-correction (OpenAI, Claude, Gemini, Grok)

### Specialized Applications

- 🌳 **Syntax Tree** - Generate linguistic syntax trees for text analysis with automatic error recovery (OpenAI, Claude)
- 🎨 **Concept Visualizer** - Create various diagrams using LaTeX/TikZ including 3D visualizations (OpenAI, Claude)
- 🎥 **Video Generator** - Create videos from text or images using Google's Veo model (Gemini)
- 🌐 **Visual Web Explorer** - Capture web pages as screenshots or extract text content (OpenAI, Claude, Gemini, Grok)
- 🗣️ **Voice Interpreter** - Real-time voice conversation with language translation (OpenAI)
- 📊 **DrawIO Grapher** - Create professional diagrams in DrawIO format (OpenAI, Claude)
- 🧮 **Math Tutor** - Interactive mathematics tutoring with MathJax rendering (OpenAI, Claude, Gemini, Grok)
- 💬 **Second Opinion** - Get verification from different AI providers for accuracy (All providers)
- 📄 **PDF Navigator** - Navigate and analyze PDF documents using vector database (OpenAI)
- 📊 **Mermaid Grapher** - Create flowcharts and diagrams using Mermaid syntax (All providers)
- 🖼️ **Image Generator** - Generate images using DALL-E, Imagen 3, and Grok (OpenAI, Gemini, Grok)
- 🎥 **Video Describer** - Analyze and describe video content (OpenAI)
- 📧 **Mail Composer** - Compose professional emails with AI assistance (All providers)
- 🌐 **Translate** - Language translation with context awareness (All providers)
- 📖 **Language Practice** - Interactive language learning conversations (All providers)
- 📖 **Language Practice Plus** - Advanced language learning with monadic context (All providers)
- ✍️ **Novel Writer** - Creative writing assistant for stories and novels (All providers)
- 🎤 **Speech Draft Helper** - Create speech drafts and presentations (All providers)
- 📚 **Wikipedia** - Search and retrieve Wikipedia articles
- ❓ **Monadic Help** - Built-in help system with AI explanations (OpenAI)

### Configuration and Extension

- 💡 Specify and edit **API parameters** and **system prompts**
- 🧩 Create custom applications with **Monadic DSL** (Domain Specific Language)
- 📊 Create diagrams with **DrawIO Grapher** and **Mermaid Grapher** apps with real-time validation
- 💎 Extend functionality using the **Ruby** programming language
- 🐍 Extend functionality using the **Python** programming language
- 🔍 **Web search** capabilities using native search features in OpenAI, Claude, Gemini, xAI Grok, and Perplexity, with [Tavily](https://tavily.com/) API for other providers
- 🌎 Perform **web scraping** using Selenium
- 📦 Add custom **Docker containers**
- 📝 **Declarative DSL** for simplified app development with error pattern detection
- 🔧 Optional setup scripts (`rbsetup.sh`, `pysetup.sh`, `olsetup.sh`) for custom environment configuration
- 🔌 **MCP Server** integration for external tool access via JSON-RPC 2.0 protocol

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
  - Various open source LLM models
  - New models can be added anytime
- 🤖💬🤖 **AI-to-AI** chat functionality

### Conversations as Monads

- ♻️ **Monadic mode** enables structured conversations with JSON-based context management
- 📊 **All providers** now support monadic mode: OpenAI, Claude, Gemini, Mistral, Cohere, DeepSeek, Perplexity, Grok, and Ollama
- 🔄 Context includes reasoning process, topics discussed, people mentioned, and important notes
- 🎯 **Chat Plus** apps demonstrate monadic capabilities across all providers

## Developer

Yoichiro HASEBE<br />
[yohasebe@gmail.com](yohasebe@gmail.com)

## License

This software is available as open source under the terms of the [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0).
