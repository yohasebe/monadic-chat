# FAQ: Adding New Features

##### Q: I installed the Ollama plugin and downloaded a model, but it is not reflected in the web interface. What should I do? :id=ollama-model-not-showing

**A**: It may take some time for the model downloaded to the Ollama container to be loaded and become available. Wait a while and then reload the web interface. If the downloaded model still does not appear, access the Ollama container from the terminal and run the `ollama list` command to check if the downloaded model is displayed in the list. If the model is listed but not appearing in the web interface, try restarting the Ollama container or the entire Monadic Chat application.

---

##### Q: How can I add new programs or libraries to the Python container? :id=adding-python-libraries

**A**: There are several ways to do this, but it is convenient to add an installation script to the `pysetup.sh` in the shared folder to install libraries during the Monadic Chat environment setup. See [Adding Programs and Libraries](../docker-integration/python-container.md#adding-programs-and-libraries) and [Usage of pysetup.sh](../docker-integration/python-container.md#usage-of-pysetupsh) for more information.

---

##### Q: How can I customize text-to-speech pronunciations for specific words or phrases? :id=tts-pronunciation-customization

**A**: Monadic Chat supports a TTS dictionary feature that allows you to customize pronunciations. This can be configured in your environment settings by adding a `TTS_DICT` entry with word-pronunciation pairs. For example, to make the TTS engine pronounce technical terms or abbreviations correctly, you can add entries in your configuration file.

---

##### Q: Can I use web search capabilities in my conversations? :id=web-search-capabilities

**A**: Yes, many of the apps in Monadic Chat support web search functionality through the `websearch` setting. In Chat apps, this feature is disabled by default to give users control over costs and privacy - you can enable it manually when you need current information. The web search functionality is now reliable and well-tested. Several providers offer native web search capabilities (OpenAI, Claude, Gemini, Grok, and Perplexity), while others (Mistral, Cohere, DeepSeek, Ollama) require the `TAVILY_API_KEY` to be configured to use Tavily's search API. The availability of native search may depend on specific models and settings. Note that reasoning models that don't support function calling will automatically switch to a search-capable model when web search is enabled.

---

##### Q: How do I update Monadic Chat to the latest version? :id=updating-monadic-chat

**A**: Monadic Chat automatically checks for updates when it starts. If an update is available, a notification will appear in the main window. You can also manually check for updates by selecting "Check for Updates" from the application menu (File → Check for Updates). When an update is available, the application will provide a download link. Note that the update process is not fully automatic - you need to manually download the new version from the provided link and install it yourself.

---

##### Q: What is MCP and how do I use it with external AI assistants? :id=mcp-integration

**A**: MCP (Model Context Protocol) is a standard protocol that allows external AI assistants and other clients to access Monadic Chat functionality via JSON-RPC 2.0. To enable it, add `MCP_SERVER_ENABLED=true` to your `~/monadic/config/env` file and restart Monadic Chat. The server automatically discovers and exposes all available tools from your apps. See [MCP Integration](/advanced-topics/mcp-integration.md) for detailed documentation.

---

##### Q: Can I access all Monadic Chat tools through MCP? :id=mcp-tools

**A**: Yes, the MCP server automatically exposes all tools from all enabled apps. This includes image generation (DALL-E, Gemini), diagram creation (Mermaid, Syntax Tree), code execution, PDF search, and more. Tools are named using the convention `AppName__tool_name`. For example, `ImageGeneratorOpenAI__generate_image_with_dalle` or `SyntaxTreeOpenAI__render_syntax_tree`. No additional configuration is needed - new apps and tools are automatically discovered.
