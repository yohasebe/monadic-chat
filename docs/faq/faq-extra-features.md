# FAQ: Adding New Features

##### Q: I downloaded a model with Ollama, but it is not reflected in the web interface. What should I do? :id=ollama-model-not-showing

**A**: Choose an Ollama app again: the model list is read from Ollama each time an Ollama app is chosen. If the model still does not appear, run `ollama list` in your terminal to check that the model is installed.

---

##### Q: How can I add new programs or libraries to the Python container? :id=adding-python-libraries

**A**: You can create a `pysetup.sh` script in the config folder (`~/monadic/config/`) to install libraries during the Monadic Chat environment setup. See [Adding libraries with pysetup.sh](../docker-integration/python-container.md#adding-libraries-with-pysetupsh) for more information.

---

##### Q: How can I customize text-to-speech pronunciations for specific words or phrases? :id=tts-pronunciation-customization

**A**: Monadic Chat supports a TTS dictionary feature that allows you to customize pronunciations. Set the path to a dictionary file in **Settings → Voice & Audio → TTS Dictionary File Path**. The dictionary is a CSV file of word-pronunciation pairs, which helps the TTS engine pronounce technical terms or abbreviations correctly.

---

##### Q: Can I use web search capabilities in my conversations? :id=web-search-capabilities

**A**: Yes, many of the apps in Monadic Chat support web search functionality:

- **Native Web Search**: OpenAI, Claude, Gemini, and Grok use their built-in web search
- **Tavily Search**: Mistral, Cohere, DeepSeek, and Ollama use the Tavily API when `TAVILY_API_KEY` is configured in `~/monadic/config/env`
- **URL Content Extraction**: With every provider, **Open URL** at the top of the work screen opens a web page on the work screen or reads its text into the message box (using Selenium)

Web search is on unless you turn it off in Settings (**General › Sources the AI can use**). The AI searches when you ask for it or current information is needed, in every built-in app but Monadic Help, Wikipedia and Voice Interpreter; with Mistral, Cohere, DeepSeek and Ollama it needs `TAVILY_API_KEY`.

---

##### Q: How do I update Monadic Chat to the latest version? :id=updating-monadic-chat

**A**: Monadic Chat automatically checks for updates when it starts. If an update is available, a notification will appear in the main window. You can also check by choosing **File → Check for Updates**. When an update is available, click **Download & Install**: the update is downloaded in the background, and then you are asked to restart.

---

##### Q: What is MCP and how do I use it with external AI assistants? :id=mcp-integration

**A**: MCP (Model Context Protocol) allows external AI assistants to access Monadic Chat functionality via JSON-RPC 2.0. See [MCP Integration](/advanced-topics/mcp-integration.md) for setup instructions and detailed documentation.

---

##### Q: What can I access through MCP? :id=mcp-tools

**A**: The MCP server (Monadic Conduit) exposes a small, stable set of capability tools in the `monadic_*` namespace rather than every individual app tool. These cover model queries, a local Library, audio/image/video analysis, code generation, audio/image/video/music generation, and a bounded agent, plus background-job control for long-running work. Tools that call a provider are gated by a token budget. See [MCP Integration](/advanced-topics/mcp-integration.md) for the full list.
