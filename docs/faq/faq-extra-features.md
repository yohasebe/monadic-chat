# FAQ: Adding New Features

**Q**: I installed the Ollama plugin and downloaded a model, but it is not reflected in the web interface. What should I do?

**A**: It may take some time for the model downloaded to the Ollama container to be loaded and become available. Wait a while and then reload the web interface. If the downloaded model still does not appear, access the Ollama container from the terminal and run the `ollama list` command to check if the downloaded model is displayed in the list. If the model is listed but not appearing in the web interface, try restarting the Ollama container or the entire Monadic Chat application.

---

**Q**: How can I add new programs or libraries to the Python container?

**A**: There are several ways to do this, but it is convenient to add an installation script to the `pysetup.sh` in the shared folder to install libraries during the Monadic Chat environment setup. See [Adding Programs and Libraries](../docker-integration/python-container.md#adding-programs-and-libraries) and [Usage of pysetup.sh](../docker-integration/python-container.md#usage-of-pysetupsh) for more information.

---

**Q**: How can I customize text-to-speech pronunciations for specific words or phrases?

**A**: Monadic Chat supports a TTS dictionary feature that allows you to customize pronunciations. This can be configured in your environment settings by adding a `TTS_DICT` entry with word-pronunciation pairs. For example, to make the TTS engine pronounce technical terms or abbreviations correctly, you can add entries in your configuration file.

---

**Q**: Can I use web search capabilities in my conversations?

**A**: Yes, many of the apps in Monadic Chat support web search functionality through the `websearch` setting. When enabled (set to `true`), this allows the AI to search the web for current information to provide more accurate responses. Several providers offer native web search capabilities (OpenAI, Claude, Grok, and Perplexity), while others (Gemini, Mistral, Cohere, DeepSeek) require the `TAVILY_API_KEY` to be configured to use Tavily's search API. The availability of native search may depend on specific models and settings. Note that reasoning models that don't support function calling will automatically switch to a search-capable model when web search is enabled.

---

**Q**: How do I update Monadic Chat to the latest version?

**A**: Monadic Chat automatically checks for updates when it starts. If an update is available, a notification will appear in the main window. You can also manually check for updates by selecting "Check for Updates" from the application menu (File → Check for Updates). When an update is available, the application will provide a download link. Note that the update process is not fully automatic - you need to manually download the new version from the provided link and install it yourself.
