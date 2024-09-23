# Monadic Chat

![Monadic Chat Architecture](../assets/images/monadic-chat-architecture.svg ':width=800')

## Overview

**Monadic Chat** is a web application framework designed to create and utilize intelligent chatbots. By providing a Linux environment on Docker to GPT-4 and other LLMs, it allows the execution of advanced tasks that require external tools. It also supports voice interaction, image and video recognition and generation, and AI-to-AI chat, making it useful not only for using AI but also for developing and researching various applications.

## What is "Grounding"?

Monadic Chat is an AI framework grounded in the real world. The term **grounding** here has two meanings.

Typically, discourse involves context and purpose, which are referenced and updated as the conversation progresses. Just as in human-to-human conversations, **maintaining and referencing context** is useful, or even essential, in conversations with AI agents. By defining the format and structure of meta-information in advance, it is expected that conversations with AI agents will become more purposeful. The process of users and AI agents advancing discourse while sharing a foundational background is the first meaning of "grounding."

Human users can use various tools to achieve their goals. However, in many cases, AI agents cannot do this. Monadic Chat enables AI agents to execute tasks using external tools by providing them with a **freely accessible Linux environment**. This allows AI agents to more effectively support users in achieving their goals. Since it is an environment on Docker containers, it does not affect the host system. This is the second meaning of "grounding."

## Features

### Basic Structure

- 🤖 Chat functionality using OpenAI's Chat API (**GPT-4**)
- 👩‍💻 Installable as a GUI application on Mac and Windows using **Electron**
- 🌐 Usable as a **web application** in browsers
- 👩💬 🤖💬 Supports both **human↔️AI chat** and **AI↔️AI chat**

### AI + Linux Environment

- 🐧 Provides a **Linux environment** (Ubuntu) freely accessible by AI
- 🐳 Tools available to LLMs via **Docker containers**
  - Python (+ pip) for tool/function calls
  - Ruby (+ gem) for tool/function calls
  - PGVector (+ PostgreSQL) for DAG using vector representation
  - Selenium (+ Chrome/Chromium) for web scraping
- 📦 Each container can be managed via **SSH**
- 📓 Integration with **Jupyter Notebook**

### Data Management

- 💾 **Export/import** conversation data
- 💬 Specify the number of messages (**active messages**) sent to the API as context data
- 🔢 Generate **text embeddings** from data in **PDF files**

### Voice Interaction

- 🎙️ **Microphone input recognition** using Whisper API
- 🔈 **Text-to-speech** for AI assistant responses
- 🗺️ **Automatic language detection** for text-to-speech
- 🗣️ Choose the **language and voice** for text-to-speech
- 😊 **Interactive conversation** with AI agents using speech recognition and text-to-speech
- 🎧 Save AI assistant's spoken responses as **MP3 audio** files

### Image and Video Recognition and Generation

- 🖼️ **Image generation** using DALL·E 3 API
- 👀 Recognition and description of **uploaded images**
- 📚 Upload and recognition of **multiple images**
- 🎥 Recognition and description of **uploaded video content and audio**

### Configuration and Extension

- 💡 Customize AI agent settings and behavior by specifying **API parameters** and **system prompts**
- 💎 Extend functionality using the **Ruby** programming language
- 🐍 Extend functionality using the **Python** programming language
- 🌎 Perform **web scraping** using Selenium

### Message Editing

- 📝 **Re-edit** past messages
- 🗑️ **Delete** specific messages
- 📜 Set **roles** (user, assistant, system) for new messages

### Support for Multiple LLM APIs

- 👥 Supports the following LLM APIs
  - OpenAI GPT-4
  - Google Gemini
  - Anthropic Claude
  - Cohere Command R
  - Mistral AI
- 🤖💬🤖 AI↔️AI Chat is available with the following combinations

   | AI-Assistant     | | AI-User               |
   |:-----------------|-|:----------------------| 
   | OpenAI GPT-4     |↔️| OpenAI GPT-4 or GPT4o |
   | Google Gemini    |↔️| OpenAI GPT-4 or GPT4o |
   | Anthropic Claude |↔️| OpenAI GPT-4 or GPT4o |
   | Cohere Command R |↔️| OpenAI GPT-4 or GPT4o |
   | Mistral AI       |↔️| OpenAI GPT-4 or GPT4o |

### Managing Conversations as Monads

- ♻️ In addition to the main response from the AI assistant, it is possible to manage the (invisible) **state of the conversation** by obtaining additional responses and updating values within a predefined JSON object

## Author

Yoichiro HASEBE<br />
[yohasebe@gmail.com](yohasebe@gmail.com)

## License

This software is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
