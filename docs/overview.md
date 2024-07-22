---
title: Monadic Chat
layout: default
---

# Overview

[English](/monadic-chat/overview) |
[日本語](/monadic-chat/overview_ja)

<img src="./assets/images/monadic-chat-architecture.png" width="800px"/>

## tl;dr

**Monadic Chat** is a framework designed to create and use intelligent chatbots. By providing a full-fledged Linux environment on Docker to GPT-4 and other LLMs, it allows the chatbots to perform advanced tasks that require external tools. It also supports voice interaction, image and video recognition and generation, and AI-to-AI chat, suitable not only for using AI but also for developing and researching various applications.

[Full Change Log](https://github.com/yohasebe/monadic-chat/blob/main/CHANGELOG.md)

## Key Features

### Basic Structure

- 🤖 Chat functionality powered by **GPT-4** via OpenAI's Chat API
- 👩‍💻 Installable as a GUI application on Mac and Windows using **Electron**
- 🌐 Usable as a **web application** in browsers
- 👩💬 🤖💬 Both **human↔️AI chat** and **AI↔️AI chat** are supported

### AI + Linux Environment

- 🐧 Provides a **Linux** environment (Ubuntu) freely accessible by AI
- 🐳 Tools for LLMs via **Docker containers**
  - Python (+ pip) for tool/function calls
  - Ruby (+ gem) for tool/function calls
  - PGVector (+ PostgreSQL) for DAG using vector representation
  - Selenium (+ Chrome/Chromium) for web scraping
- 📦 Each container can be managed via **SSH**
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
- 🎧 Text data can be spoken by the AI agent and saved as an **MP3 audio** file

### Image and Video Recognition and Generation

- 🖼️ **Generate images** from text prompts using OpenAI's DALL·E 3 API
- 👀 Analyze and describe the content of **uploaded images**
- 📚 **Multiple images** can be uploaded for recognition
- 🎥 Recognize and describe the content and audio of **uploaded video**

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

- 👥 **Multiple LLM APIs** are supported:
  - OpenAI GPT-4
  - Google Gemini
  - Anthropic Claude
  - Cohere Command R
  - Mistral AI
- 🤖💬🤖 **AI↔️AI Chat** is available:

   | AI-Assistant     | | AI-User      |
   |:-----------------|-|:-------------| 
   | OpenAI GPT-4     |↔️| OpenAI GPT-4 |
   | Google Gemini    |↔️| OpenAI GPT-4 |
   | Anthropic Claude |↔️| OpenAI GPT-4 |
   | Cohere Command R |↔️| OpenAI GPT-4 |
   | Mistral AI         |↔️| OpenAI GPT-4 |

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
