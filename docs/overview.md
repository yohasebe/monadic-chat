---
title: Monadic Chat
layout: default
---

# Overview

[English](/monadic-chat/overview) |
[日本語](/monadic-chat/overview_ja)

<img src="./assets/images/screenshot-01.png" width="700px"/>

<img src="./assets/images/monadic-chat-console.png" width="500px"/>

<img src="./assets/images/monadic-chat-architecture.png" width="800px"/>

## Monadic Chat

**Monadic Chat** is a framework designed to create and use intelligent chatbots. By providing a full-fledged Linux environment on Docker to GPT-4 and other LLMs, it allows the chatbots to perform advanced tasks that require external tools for searching, coding, testing, analysis, visualization, and more. 

⚠️  **Important Notice**

This software is currently under active development and is subject to frequent changes. Some features may still be unstable at this moment. Please exercise caution when using it.

📢 **Call for Contributions**

We welcome contributions that can help refine this software, such as code improvements, adding tests, and documentation. Your support would be greatly appreciated.

## Key Features

### Basic Structure

- 🤖 Chat functionality powered by **GPT-4** via OpenAI's Chat API
- 👩‍💻 Installable as a GUI application on Mac and Windows using **Electron**
- 🌐 Usable as a **web application** in browsers

### AI + Linux Environment

- 🐧 Provides a Linux environment (Ubuntu) freely accessible by AI
- 🐳 Tools for LLMs via **Docker containers**
  - Python (+ pip) for tool/function calls
  - Ruby (+ gem) for tool/function calls
  - PGVector (+ PostgreSQL) for DAG using vector representation
  - Selenium (+ Chrome/Chromium) for web scraping
- 📦 Each container can be managed via SSH
- 📓 Python container can launch **Jupyter Notebook**

### Data Management

- 💾 **Export/import** conversation data
- 💬 Specify the number of recent messages (**active messages**) to send to the API
- 🔢 Generate **text embeddings** from data in **PDF files**
- 📂 Local data folders are synchronized with Docker containers for seamless interaction

### Voice Interaction

- 🎙️ Automatic transcription of **microphone input** using OpenAI's Whisper API
- 🔈 **Text-to-speech** functionality for AI assistant responses
- 🗺️ **Automatic language detection** for appropriate text-to-speech playback
- 🗣️ Choose the **language and voice** for text-to-speech
- 😊 Enable **interactive conversations** with the AI agent using speech recognition and text-to-speech

### Image and Video Recognition and Generation

- 🖼️ **Generate images** from text prompts using OpenAI's DALL·E 3 API
- 👀 Analyze and describe the content of **uploaded images**
- 🎥 Recognize and describe the content and audio of **uploaded videos**

### Configuration and Extension

- 💡 Customize the AI agent's behavior by specifying **API parameters** and the **system prompt**
- 💎 Extend functionality using the **Ruby** programming language
- 🐍 Extend functionality using the **Python** programming language
- 🌎 Perform **web scraping** using Selenium

### Message Editing

- 📝 **Edit** previous messages
- 🗑️ **Delete** specific messages
- 📜 **Set roles** (user, assistant, system) for new messages

### Support for Multiple LLM APIs

- 👥 In addition to OpenAI GPT-4 (default), basic functionality (chat + tool/function call) is also available for:
  - Google Gemini
  - Anthropic Claude
  - Cohere Command R

### Managing Conversations as Monads

- ♻️  Manage (invisible) **conversation state** by obtaining additional responses from LLM and updating values in a predefined JSON object

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
