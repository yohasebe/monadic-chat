<div><img src="./docs/assets/images/monadic-chat-logo.png" width="600px"/></div>

<div><img src="./docs/assets/images/monadic-chat-architecture.svg" width="800px"/></div>

## Overview

🤖 + 🐳 + 🐧 [Monadic Chat](https://yohasebe.github.io/monadic-chat) is a locally hosted web application designed to create and utilize intelligent chatbots. By providing a Linux environment on Docker to GPT and other LLMs, it allows the execution of advanced tasks that require external tools. It also supports voice interaction, image and video recognition and generation, and AI-to-AI chat, making it useful not only for using AI but also for developing and researching various applications.

Available for **Mac**, **Windows**, and **Linux** (Debian/Ubuntu) with easy-to-use installers.

## Getting Started

- [Documentation](https://yohasebe.github.io/monadic-chat)
- [Installation](https://yohasebe.github.io/monadic-chat/#/installation)

## Latest Changes

- [Dec, 2024] 0.9.29
  - Code Interpreter app is available for OpenAI, Anthropic, Google, Cohere, and Mistral APIs
  - Math Tutor app supports visualizations
  - OpenAI's API token is not necessarily required when using other APIs (Anthropic, Google, Cohere, or Mistral)
  - Image generation feature improved
  - Image generation feature improved
  - Many UI and under-the-hood improvements
  - User container rebuild feature fixed
  - Role selection issue fixed
- [Nov, 2024] 0.9.22
  - Rebuilding specific containers feature added
  - `pysetup.sh` extra installation script supported
  - Jupyter Notebook apps (for GPT and Claude) improved
  - Streaming supported for OpenAI's o1 models
  - CJK font issue on code apps addressed
  - Syntax highlighting theme option added
  - App settings convention enhanced with "group" attribute
  - Check for updates when starting the app
  - [Predicted output](https://platform.openai.com/docs/guides/latency-optimization#use-predicted-outputs) feature added for OpenAI's models
  - [PDF recognition](https://docs.anthropic.com/en/docs/build-with-claude/pdf-support) feature added for Claude Sonnet models
  - AI user feature improved

- [Changelog](https://yohasebe.github.io/monadic-chat/#/changelog)

## Screenshots

**Web Interface**

<div><img src="./docs/assets/images/monadic-chat-web.png" width="800px"/></div><br />

**Chat Window**

<div><img src="./docs/assets/images/monadic-chat-chat-about-pdf.png" width="700px"/></div><br />

**Console Window**

<div><img src="./docs/assets/images/monadic-chat-console.png" width="700px"/></div><br />

## Contributing

Contributions are welcome! Here's how to help:

1. **Fork & Clone**: Fork the repository and clone it to your local machine.
2. **Create a Branch**: Use a descriptive name for your branch (e.g., `feature/new-feature`).
3. **Make Changes**: Implement changes and ensure they are well-tested.
4. **Commit**: Write clear, concise commit messages.
5. **Push & PR**: Push the branch and open a pull request.

Thank you for your interest in improving the project!
