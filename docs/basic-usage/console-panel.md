# Monadic Chat Console Panel

## Console Button Items

![Monadic Chat Console](../assets/images/monadic-chat-console.png ':size=700')

**Start** Launch Monadic Chat. The initial startup may take some time due to environment setup on Docker.

<!-- > 📸 **Screenshot needed**: Console panel with Start button highlighted -->

**Stop** <br />
Stop Monadic Chat.

**Restart** <br />
Restart Monadic Chat.

**Open Browser** <br />
Open Monadic Chat in a web browser.
Access URL: [http://localhost:4567](http://localhost:4567)

**Shared Folder** <br />
Open the folder shared between the host and Docker containers. It can be used for importing and exporting files. It is also used when installing additional apps.


**Quit** <br />
Exit the Monadic Chat Console.

## Console Menu Items

![Console Menu](../assets/images/console-menu.png ':size=300')

### Actions Menu

![Action Menu](../assets/images/action-menu.png ':size=150')

**Start** <br />
Launch Monadic Chat. The initial startup may take some time due to environment setup on Docker.

**Stop** <br />
Stop Monadic Chat.

**Restart** <br />
Restart Monadic Chat.

**Build All** <br />
Build all Docker images and containers for Monadic Chat.

?> **Note:** Build commands triggered from the menu always run with Docker's `--no-cache` flag so that newly released Dockerfile changes and dependencies are applied immediately.

<!-- > 📸 **Screenshot needed**: Console output showing Docker build progress -->

**Build Ruby Container** <br />
Build the Docker image and container (`monadic-chat-ruby-container`) that powers Monadic Chat.

**Build Python Container** <br />
Build the Docker image and container (`monadic-chat-python-container`) used by the AI agents.

**Build User Containers** <br />
Build the Docker images and containers defined by the user. Note that user-defined containers are not automatically built when starting Monadic Chat - you must use this menu option to build them manually after adding or modifying user container definitions.

**Build Ollama Container** <br />
Build the Docker image and container (`monadic-chat-ollama-container`) for running local language models via Ollama. This container is not built automatically with "Build All" to save resources. You must explicitly choose this option to use Ollama features.

**Start JupyterLab** <br />
Launch JupyterLab. It can be accessed at [http://localhost:8889](http://localhost:8889)


**Stop JupyterLab** <br />
Stop JupyterLab.

**Stop Selenium Container** <br />
Disable the Selenium container from starting automatically on next launch of Monadic Chat. When Selenium is disabled, the system will use Tavily API as a fallback for web scraping features (if Tavily API key is configured). Note: This setting only takes effect after restarting Monadic Chat. Users attempting Selenium-backed tools while the container is disabled will see guidance indicating that the Selenium container is stopped and the feature cannot run until it is re-enabled.

**Import Document DB** <br />
Import PDF document data previously exported by Monadic Chat. When importing, place a file named `monadic.gz` in the shared folder.

**Export Document DB** <br />
Export PDF document data stored in Monadic Chat's vector database. The exported file will be saved as `monadic.gz` in the shared folder.

### Open Menu

![Open Menu](../assets/images/open-menu.png ':size=150')

**Open Browser** <br />
Open the default browser to access Monadic Chat at [http://localhost:4567](http://localhost:4567)

**Open Shared Folder** <br />
Open the folder shared between the host and Docker containers. It can be used for importing and exporting files. It is also used when installing additional apps. The following folders are included:

- `apps`: Folder for storing additional applications.
- `helpers`: Folder for storing helper files containing functions used by apps.
- `scripts`: Folder for storing executable scripts that can be run within containers.
- `plugins`: Folder for organizing Monadic Chat plugins.

**Open Config Folder** <br />
Open the `~/monadic/config` folder. This folder contains configuration files for Monadic Chat. The following files are included:

- `env`: Configuration file (can be configured through GUI).
- `pysetup.sh`: Script for setting up the Python environment (optional, user-created).
- `rbsetup.sh`: Script for setting up the Ruby environment (optional, user-created).
- `olsetup.sh`: Script for setting up Ollama models (optional, user-created).
- `compose.yml`: Docker Compose configuration file (auto-generated when user containers are present).


**Open Log Folder** <br />
Open the `~/monadic/log` folder. This folder contains log files for Monadic Chat. The following files are included:

- `docker-build.log`: Log file for Docker build.
- `docker-startup.log`: Log file for Docker startup.
- `server.log`: Log file for the Monadic Chat server.
- `command.log`: Log file for command execution and code execution.
- `jupyter.log`: Log file for cells added to jupyter notebook.

When `Extra Logging` is enabled in the settings panel, additional logs are saved as `extra.log`.

- `extra.log`: Log file for chat logs recorded as streaming JSON objects from the start to the end of Monadic Chat.

?> **Note:** The "Extra Logging" option enables detailed logging for debugging purposes. When enabled, additional log information is saved in the logs directory.

**Open Console** <br />
Open the Monadic Chat console.

**Settings** <br />
Open the Monadic Chat settings panel. Note that this is different from the System Settings panel within the web interface.

### File Menu

**About Monadic Chat** <br />
Shows information about the application version.

**Check for Updates** <br />
Checks for and downloads application updates. When an update is available, you'll see a dialog with the option to download it. After downloading, you'll be prompted to restart the application to apply the update.

**Uninstall Images and Containers** <br />
Removes all Docker images and containers for Monadic Chat.

**Quit Monadic Chat** <br />
Exits the application.

## Settings Panel

Settings configured in the settings panel are automatically saved.

![Settings Panel](../assets/images/settings-api_keys.png ':size=600')

**OPENAI_API_KEY** <br />
(Recommended) Enter your OpenAI API key. This key is used to access the Chat API, DALL-E image generation API, Speech-to-Text API, and Text-to-Speech API. While not strictly required, many core features depend on this key. It can be obtained from the [OpenAI API page](https://platform.openai.com/docs/guides/authentication).


**ANTHROPIC_API_KEY** <br />
Enter your Anthropic API key. This key is required to use the Anthropic Claude models. It can be obtained from [https://console.anthropic.com](https://console.anthropic.com).

**COHERE_API_KEY** <br />
Enter your Cohere API key. This key is required to use the Cohere models. It can be obtained from [https://dashboard.cohere.com](https://dashboard.cohere.com).

**GEMINI_API_KEY** <br />
Enter your Google Gemini API key. This key is required to use the Google Gemini models. It can be obtained from [https://ai.google.dev/](https://ai.google.dev/).

**MISTRAL_API_KEY** <br />
Enter your Mistral API key. This key is required to use the Mistral AI models. It can be obtained from [https://console.mistral.ai/](https://console.mistral.ai/).

**XAI_API_KEY** <br />
Enter your xAI API key. This key is required to use the xAI Grok models. It can be obtained from [https://x.ai/api](https://x.ai/api).

**PERPLEXITY_API_KEY** <br />
Enter your Perplexity API key. This key is required to use the Perplexity models. It can be obtained from [https://www.perplexity.ai/settings/api](https://www.perplexity.ai/settings/api).

**DEEPSEEK_API_KEY** <br />
Enter your DeepSeek API key. This key is required to use the DeepSeek models. It can be obtained from [https://platform.deepseek.com/](https://platform.deepseek.com/).

**ELEVENLABS_API_KEY** <br />
Enter your ElevenLabs API key. This key is required to use the ElevenLabs voice models. It can be obtained from [https://elevenlabs.io/developers](https://elevenlabs.io/developers).

**TAVILY_API_KEY** <br />
Enter your Tavily API key. This key is used for two purposes: 1) For "From URL" feature as an alternative to Selenium, and 2) For web search functionality in apps using providers without native search (Mistral, Cohere, DeepSeek, Ollama). It can be obtained from [https://tavily.com/](https://tavily.com/).

![Settings Panel](../assets/images/settings-model.png ':size=600')

**AI_USER_MAX_TOKENS** <br />
Select the maximum number of tokens for the AI user. This setting is used to limit the number of tokens that can be used in a single request. The default is `2000`.

![Settings Panel](../assets/images/settings-display.png ':size=600')

**Syntax Highlighting Theme** <br />
Select the theme for code syntax highlighting. The default is `pastie`.

![Settings Panel](../assets/images/settings-voice.png ':size=600')

**STT_MODEL** <br />
Select the model used for speech-to-text. The dropdown lists the STT models exposed by your configured providers (for example, OpenAI Whisper or transcribe models). Refer to the provider documentation for current options.

**TTS Dictionary File Path** <br />
Enter the path to the text-to-speech dictionary file. The dictionary file is in CSV format and contains comma-separated entries of strings to be replaced and the strings to be used for speech synthesis (no header row is required). When using text-to-speech, the strings to be replaced in the text are replaced with the strings for speech synthesis.

![Settings Panel](../assets/images/settings-system.png ':size=600')

**Application Mode** <br />
Select the application mode. "Standalone" mode runs the application for a single device while "Server" mode allows multiple devices in the local network to connect to the Monadic Chat server. The default is "Standalone".


**Browser Mode** <br />
Select the browser to use when opening Monadic Chat from the console. "Internal Browser" opens the built-in Electron browser window, while "External Browser" opens your system's default web browser. The default is "Internal Browser".


**Extra Logging** <br />
Select whether to enable additional logging. When enabled, API requests and responses are logged in detail. The log file is saved as `~/monadic/log/extra.log`.
