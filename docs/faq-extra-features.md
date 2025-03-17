# FAQ: Adding New Features

**Q**: I installed the Ollama plugin and downloaded a model, but it is not reflected in the web interface. What should I do?

**A**: It may take some time for the model downloaded to the Ollama container to be loaded and become available. Wait a while and then reload the web interface. If the downloaded model still does not appear, access the Ollama container from the terminal and run the `ollama list` command to check if the downloaded model is displayed in the list. If it is not displayed, run the `ollama reload` command to reload the Ollama plugin.

**Q**: How can I add new programs or libraries to the Python container?

**A**: There are several ways to do this, but it is convenient to add an installation script to the `pysetup.sh` in the shared folder to install libraries during the Monadic Chat environment setup. See [Adding Libraries](./python-container?id=adding-programs-and-libraries) and [Using pysetup.sh](./python-container?id=usage-of-pysetupsh) for more information.

**Q**: How can I customize text-to-speech pronunciations for specific words or phrases?

**A**: Monadic Chat supports a TTS dictionary feature that allows you to customize pronunciations. This can be configured in your environment settings by adding a `TTS_DICT` entry with word-pronunciation pairs. For example, to make the TTS engine pronounce technical terms or abbreviations correctly, you can add entries in your configuration file.

**Q**: Can I use web search capabilities in my conversations?

**A**: Yes, many of the apps in Monadic Chat support web search functionality through the `websearch` setting. When enabled (set to `true`), this allows the AI to search the web for current information to provide more accurate responses. If both `OPENAI_API_KEY` and `TAVILY_API_KEY` are configured, web searches in apps using OpenAI's API will be performed using OpenAI's built-in search capabilities. For web searches in other contexts, the Tavily API will be used.

