# FAQ: Setup and Settings

##### Q: Do I need an OpenAI API token to use Monadic Chat? :id=openai-api-token-requirement

**A**: An OpenAI API token is not necessarily required if you do not use functions such as speech recognition, speech synthesis, and text embedding. You can also use APIs such as Anthropic Claude, Google Gemini, Cohere, Mistral AI, Perplexity, DeepSeek, and xAI Grok.

If you do not want to use commercial APIs, you can use the Ollama container to run local language models:
1. Build the Ollama container via Actions → Build Ollama Container
2. Install models using an `olsetup.sh` script or let it download the default model (llama3.2)
3. Use the Chat app with Ollama provider selected

For detailed information on using Ollama with Monadic Chat, see [Using Ollama](/advanced-topics/ollama.md).

---

##### Q: Rebuilding Monadic Chat (rebuilding the containers) fails. What should I do? :id=container-rebuild-failures

**A**: Check the contents of the log files in the log folder.

If you are developing additional apps or modifying existing apps, check the contents of `server.log` in the log folder. If an error message is displayed, correct the app code based on the error message.

If you are adding libraries to the Python container using `pysetup.sh`, error messages may be displayed in `docker_build.log`. Check the error message and correct the installation script.

---

##### Q: What is the difference between UI Language and Conversation Language? :id=ui-vs-conversation-language

**A**: Monadic Chat has two separate language settings:

- **UI Language**: Controls the interface language of the Electron app (menus, buttons, dialogs). This is set in the Electron Settings panel and affects only the application interface.

- **Conversation Language**: Controls the language used for AI responses and speech recognition/synthesis. This is set in the Web UI and affects:
  - AI response language
  - Speech-to-Text (STT) language detection
  - Text-to-Speech (TTS) language
  - Text direction (RTL for Arabic, Hebrew, Persian, Urdu)

These settings are independent, allowing you to use the app interface in one language while conversing with AI in another.

