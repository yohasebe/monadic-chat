<div align="center">

<img src="https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docs/assets/images/monadic-chat-logo.png" width="700px" alt="Monadic Chat Logo">

<a href="https://github.com/yohasebe/monadic-chat/releases"><img src="https://img.shields.io/github/v/release/yohasebe/monadic-chat?include_prereleases&style=for-the-badge&cacheSeconds=3600" alt="Release"></a>
<a href="LICENSE"><img src="https://img.shields.io/github/license/yohasebe/monadic-chat?style=for-the-badge&cacheSeconds=3600" alt="License"></a>
<a href="https://yohasebe.github.io/monadic-chat/#/developer/testing_guide"><img src="https://img.shields.io/badge/tests-passing-success?style=for-the-badge" alt="Tests"></a>

  ---

**🎯 Features** · [Multimodal](https://yohasebe.github.io/monadic-chat/#/basic-usage/basic-apps#multimodal-capabilities) · [PDF Knowledge Base](https://yohasebe.github.io/monadic-chat/#/basic-usage/pdf_storage) · [Web Search](https://yohasebe.github.io/monadic-chat/#/basic-usage/basic-apps#web-search-integration) · [Code Execution](https://yohasebe.github.io/monadic-chat/#/basic-usage/basic-apps#code-interpreter) · [Voice Chat](https://yohasebe.github.io/monadic-chat/#/basic-usage/basic-apps#voice-chat) · [Privacy Filter](https://yohasebe.github.io/monadic-chat/#/advanced-topics/privacy-filter)

  **🤖 Providers** · OpenAI · Claude · Gemini · Mistral · Cohere · xAI · DeepSeek · Ollama

  **🛠 Built with** · Ruby · Electron · Docker · Qdrant · WebSocket

  ---

  <img src="https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docs/assets/images/basic-architecture.png" width="800px" alt="Monadic Chat Architecture">

</div>

## Overview

**Monadic Chat** is a locally hosted web application for creating and utilizing intelligent chatbots. By providing AI models with a real Linux environment through Docker, it enables advanced tasks requiring external tools. With support for voice interaction, image/video processing, and AI-to-AI conversations, Monadic Chat serves both as an AI application platform and a framework for developing AI-powered applications.

**Contextual Conversations**: Like monads in functional programming that wrap values with context, conversations in Monadic Chat can carry structured metadata (reasoning, topics, notes).

**Conversations as Data**: Your conversations are persistent, portable data you own—not ephemeral sessions locked in a web service. Edit, delete, export, and import your conversation history freely.

**Available for Mac, Windows, and Linux**

📖 **[Documentation](https://yohasebe.github.io/monadic-chat)** (English/Japanese) · 📋 **[Changelog](https://yohasebe.github.io/monadic-chat/#/changelog)**

## Getting Started

### Installation

1. **Download** the installer for your platform from [Releases](https://github.com/yohasebe/monadic-chat/releases)
   - macOS: `.dmg` file (Apple Silicon)
   - Windows: `.exe` installer
   - Linux: `.deb` package (Debian/Ubuntu)

2. **Install** and launch the application

3. **Configure API keys** in Settings

4. **Start using** built-in applications or create your own

📖 **Detailed installation guide**: [Installation](https://yohasebe.github.io/monadic-chat/#/getting-started/installation)

### Quick Start

After installation:

1. Click **Start** to launch the Docker environment
2. Select an app from the sidebar (start with **Chat** or **Voice Chat**)
3. Choose your AI provider (OpenAI, Claude, Gemini, etc.)
4. Start chatting!

For offline use, install [Ollama](https://ollama.com/) and select it as your provider.

> ⚠️ **Upgrading from 1.0.0-beta.14 or earlier?** Version 1.0.0-beta.15 replaces the OpenAI embeddings + PGVector stack with a fully local pipeline (Qdrant + `multilingual-e5-base`). Help search no longer requires an OpenAI API key. **Existing local PDF data is not migrated automatically — re-upload your PDFs after upgrading.** See the [Changelog](https://yohasebe.github.io/monadic-chat/#/changelog) and [PDF Storage docs](https://yohasebe.github.io/monadic-chat/#/basic-usage/pdf_storage) for details.

## Why Monadic Chat?

Unlike web-based AI services or IDE-integrated assistants, Monadic Chat is a **locally-run AI platform** that gives you:

1. **Use Your Preferred Tools**: Access real Docker containers to run code, install packages, and persist files.

2. **Local Data Storage**: Store conversations, code, and files on your local machine, not in cloud services. Work offline with Ollama.

3. **Extensible Platform**: Not just a chatbot—a framework for building custom AI applications with Monadic DSL.

4. **Provider Independence**: Switch between 9 AI providers. Choose the best model for each task.

**Perfect for**: Developers building AI tools, researchers needing reproducible environments, privacy-conscious teams, and anyone wanting full control over their AI infrastructure.

## Features

### Key Highlights

- **🤖 Multi-Provider Support**: OpenAI, Claude, Gemini, Mistral, Cohere, xAI, DeepSeek, and Ollama
- **🐧 Real Linux Environment**: AI agents can execute code, install packages, persist files, and maintain continuous context across turns in actual Docker containers.
- **💬 Advanced Conversation Management**: Edit, export/import, and track conversation history with structured context
- **🎙️ Voice Interaction**: Text-to-speech and speech-to-text with multiple providers and speaker diarization
- **🖼️ Image & Video**: Generate, edit, and analyze images and videos using latest AI models, with intelligent session-based continuity for effortless iterative editing and remixing of generated content.
- **📄 PDF Knowledge Base**: Store and query documents locally with Qdrant + on-device embeddings — no API key required
- **🌐 Web Search Integration**: Native search in OpenAI, Claude, Gemini, and Grok
- **🔒 Privacy Filter** (opt-in): Mask PII locally before sending to AI providers; restore in the response. Supports 9 languages via Microsoft Presidio + spaCy. See [Privacy Filter](https://yohasebe.github.io/monadic-chat/#/advanced-topics/privacy-filter).
- **🔄 Automatic Updates**: In-app notifications and seamless update downloads

### Featured Applications

Chat · Chat Plus · Code Interpreter · Coding Assistant · Research Assistant · Voice Chat · Jupyter Notebook · Auto Forge · Concept Visualizer · Syntax Tree · Video Generator · Math Tutor · PDF Navigator · Image Generator · Music Generator · Language Practice

📖 **Full list and details**: [Basic Apps](https://yohasebe.github.io/monadic-chat/#/basic-usage/basic-apps) (30+ apps)

### Extensibility

- **Monadic DSL**: Create custom applications with declarative syntax
- **Docker Integration**: Add your own containers and tools
- **Ruby & Python**: Extend functionality with familiar languages
- **MCP Server**: Integrate external tools and services via JSON-RPC 2.0

📖 **Development guide**: [Advanced Topics](https://yohasebe.github.io/monadic-chat/#/advanced-topics/)

## Documentation

- 📖 **[Documentation](https://yohasebe.github.io/monadic-chat)** (English/Japanese)
- 🚀 **[Getting Started](https://yohasebe.github.io/monadic-chat/#/getting-started/installation)**
- 📚 **[Basic Usage](https://yohasebe.github.io/monadic-chat/#/basic-usage/basic-apps)**
- 🐳 **[Docker Integration](https://yohasebe.github.io/monadic-chat/#/docker-integration/basic-architecture)**
- 💡 **[Advanced Topics](https://yohasebe.github.io/monadic-chat/#/advanced-topics/)**
- 📖 **[Reference](https://yohasebe.github.io/monadic-chat/#/reference/configuration)**
- ❓ **[Frequently Asked Questions](https://yohasebe.github.io/monadic-chat/#/faq)**
- 📝 **[Related blog posts](https://yohasebe.com/tags/monadic-chat/)**

## Developer

Yoichiro HASEBE
[yohasebe@gmail.com](mailto:yohasebe@gmail.com)

## License

This software is available as open source under the terms of the [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0).
