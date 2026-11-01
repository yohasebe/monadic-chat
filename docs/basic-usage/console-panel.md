# Monadic Chat Console Panel

## Console Button Items

<!-- SCREENSHOT: Console panel main window showing Start, Stop, Restart, Open Browser, Shared Folder, and Quit buttons with status display area -->

The console panel is the main control interface for Monadic Chat. It displays the current status (Stopped, Starting, Started, etc.) and provides quick access buttons for common operations.

**Start** <br />
Launch Monadic Chat. The initial startup may take some time due to environment setup on Docker.

**Stop** <br />
Stop Monadic Chat.

**Restart** <br />
Restart Monadic Chat.

**Open Browser** <br />
Open Monadic Chat in a web browser.
Access URL: [http://localhost:4567](http://localhost:4567)

**Shared Folder** <br />
Open the folder shared between the host and Docker containers. It can be used for importing and exporting files, and when installing additional apps. See [Shared Folder](../docker-integration/shared-folder.md) for the folder layout and the role of each subfolder (`apps`, `helpers`, `scripts`).

**Settings** <br />
Open the settings panel described in [Settings Panel](#settings-panel) below.

**Quit** <br />
Exit Monadic Chat.

## Console Menu Items

<!-- SCREENSHOT: Console menu bar showing File, Edit, Actions, Open, Help and Window menus -->

The console has a menu bar with the menus File, Edit, Actions, Open, Help and Window. On macOS, the File menu is shown under the name Monadic Chat. Edit has the usual editing commands, Help opens the documentation, and Window has Minimize, Close and Reload.

### Actions Menu

<!-- SCREENSHOT: Actions menu dropdown showing Install Options, Start, Stop, Restart, Build options, JupyterLab controls, and Document DB import/export options -->

The build commands are available while Monadic Chat is stopped, the JupyterLab commands while it is running, and the Document DB commands while it is stopped.

**Install Options** <br />
Open the Install Options panel of the settings window, where you can select optional packages (LaTeX, Python libraries, Privacy Filter languages, etc.) to be installed in the service containers.

**Start** <br />
Launch Monadic Chat. The initial startup may take some time due to environment setup on Docker.

**Stop** <br />
Stop Monadic Chat.

**Restart** <br />
Restart Monadic Chat.

**Build All** <br />
Build the Ruby and Python images without the build cache, download the other prebuilt images, and build your own containers.

**Build Ruby Container** <br />
Build the image and container (`monadic-chat-ruby-container`) that runs Monadic Chat, without the build cache.

**Build Python Container** <br />
Build the image and container (`monadic-chat-python-container`) used by the AI agents, without the build cache.

**Build User Containers** <br />
Build the containers you defined (see [Adding Docker Containers](../advanced-topics/adding-containers.md)), without the build cache. A normal Start does not build them; use this command after adding or changing a definition.

**Build Privacy Container** <br />
Download the image of the container (`monadic-chat-privacy-container`) used by the Privacy Filter. Available when the Privacy Filter is enabled.

**Build Extractor Container** <br />
Download the image of the container (`monadic-chat-extractor-container`) used by the Knowledge Base Quality Pack. Available when the Quality Pack is installed.

**Start JupyterLab** <br />
Launch JupyterLab at [http://localhost:8889](http://localhost:8889). See [JupyterLab Integration](../docker-integration/jupyterlab.md) for details.

**Stop JupyterLab** <br />
Stop JupyterLab.

**Import Document DB** <br />
Import the entire Document DB (saved conversations, PDFs, and Knowledge Base entries) from a previously exported file in the shared folder. A confirmation dialog warns that importing replaces the current database (**Replace and Import**). The accepted filenames are `monadic-qdrant.tar.gz` (plain) or `monadic-qdrant.tar.gz.enc` (encrypted, prompts for the passphrase used at export time).

**Export Document DB** <br />
Export the entire Document DB to the shared folder. A confirmation dialog offers two choices: **Encrypt and Export** (default — prompts for a passphrase and writes `monadic-qdrant.tar.gz.enc`) or **Export Plain** (writes `monadic-qdrant.tar.gz` unencrypted, with a strong warning that every saved conversation and PDF travels in cleartext). Use the encrypted form for any export that may leave your machine. For the encryption format and import/decryption behavior, see [Privacy Filter](../advanced-topics/privacy-filter.md#document-db-export-import).

### Open Menu

<!-- SCREENSHOT: Open menu dropdown showing Open Console, Open Browser, Open noVNC, Open Shared Folder, Open Config Folder, Open Log Folder, and Settings options -->

**Open Console** <br />
Open the Monadic Chat console.

**Open Browser** <br />
Open the default browser to access Monadic Chat at [http://localhost:4567](http://localhost:4567)

**Open noVNC** <br />
Open a noVNC viewer window (at `http://localhost:7900`) that shows the screen of the browser running inside the Selenium container. This lets you watch (and interact with) web automation in real time. Available while Monadic Chat is running.

**Open Shared Folder** <br />
Open the folder shared between the host and Docker containers. It can be used for importing and exporting files, and when installing additional apps. See [Shared Folder](../docker-integration/shared-folder.md) for the folder layout and the role of each subfolder (`apps`, `helpers`, `scripts`).

**Open Config Folder** <br />
Open the `~/monadic/config` folder. This folder contains configuration files for Monadic Chat. The following files are included:

- `env`: Configuration file (set through the settings window).
- `pysetup.sh`: Script for setting up the Python environment (optional, user-created).
- `rbsetup.sh`: Script for setting up the Ruby environment (optional, user-created).
- `models.json`: Model overrides (optional, user-created). See [Configuration](../reference/configuration.md).
- `TTS_DICT.csv`: The text-to-speech dictionary, copied here when you set one in the settings window.
- `compose.yml`: Docker Compose configuration file (generated when user containers are present).

**Open Log Folder** <br />
Open the `~/monadic/log` folder. This folder contains log files for Monadic Chat. The following files are included:

- `docker_build.log`: Log file for Docker builds (`docker_build_python.log` for the Python container).
- `docker_startup.log`: Log file for Docker startup.
- `server.log`: Log file for the Monadic Chat server.
- `command.log`: Log file for command execution and code execution.
- `jupyter.log`: Log file for cells added to jupyter notebook.

When `Extra Logging` is enabled in the settings panel, an additional `extra.log` records each chat as streaming JSON objects, from the start of Monadic Chat until it exits. It is intended for debugging.

**Settings** <br />
Open the Monadic Chat settings window. It is different from the System Settings screen in the web interface.

### File Menu

**About Monadic Chat** <br />
Shows information about the application version.

**Check for Updates** <br />
Checks for application updates. When an update is available, a dialog offers **Download & Install**. When the download completes, choose **Restart Now** to install it, or **Later**.

**Remove Images/Containers/Data** <br />
Removes Monadic Chat's Docker images, containers and volumes (the Knowledge Base data). Your files in `~/monadic` are kept.

**How to Uninstall** <br />
Opens the online documentation with complete uninstallation instructions for your operating system.

**Quit** <br />
Exits the application.

## Settings Panel :id=settings-panel

Click **Save** at the bottom of the sidebar to save your changes (closing the window with unsaved changes asks whether to save them). The settings window is organized into the following sections, accessible from the sidebar: **General**, **System**, **API Keys**, **Voice & Audio**, **Services**, **Install Options**, **Actions**, and **About**.

### General

**UI Language** <br />
Select the display language of the console and settings window.

**Browser Mode** <br />
Select the browser to use when opening Monadic Chat from the console. "Internal Browser" opens the built-in Electron browser window, while "External Browser" opens your system's default web browser.

**Syntax Highlighting Theme** <br />
Select the theme for code syntax highlighting. The default is `github-light`.

### System

**Launch at Login** <br />
Start Monadic Chat automatically when you log in to your computer.

**Menu Bar Mode** <br />
Keep Monadic Chat running in the menu bar instead of showing a console window (macOS).

**Extra Logging** <br />
Select whether to enable additional logging. When enabled, API requests and responses are logged in detail. The log file is saved as `~/monadic/log/extra.log`.

<!-- SCREENSHOT: Settings panel showing API Keys section with input fields for OPENAI_API_KEY, ANTHROPIC_API_KEY, COHERE_API_KEY, GEMINI_API_KEY, MISTRAL_API_KEY, XAI_API_KEY, DEEPSEEK_API_KEY, ELEVENLABS_API_KEY, and TAVILY_API_KEY -->

### API Keys

Enter a key for each provider you want to use — configure only the ones you have an account with. OpenAI covers the most ground, since the same key serves its chat models, image generation, speech-to-text and text-to-speech, which makes it the most useful one to start with.

For what each key enables and which apps require it, see [Configuration](../reference/configuration.md#api-keys).

| Setting | Where to get the key |
| --- | --- |
| `OPENAI_API_KEY` | [platform.openai.com](https://platform.openai.com/docs/guides/authentication) |
| `ANTHROPIC_API_KEY` | [console.anthropic.com](https://console.anthropic.com) |
| `COHERE_API_KEY` | [dashboard.cohere.com](https://dashboard.cohere.com) |
| `GEMINI_API_KEY` | [ai.google.dev](https://ai.google.dev/) |
| `MISTRAL_API_KEY` | [console.mistral.ai](https://console.mistral.ai/) |
| `XAI_API_KEY` | [x.ai/api](https://x.ai/api) |
| `DEEPSEEK_API_KEY` | [platform.deepseek.com](https://platform.deepseek.com/) |
| `ELEVENLABS_API_KEY` | [elevenlabs.io/developers](https://elevenlabs.io/developers) |
| `TAVILY_API_KEY` | [tavily.com](https://tavily.com/) |

`TAVILY_API_KEY` is the one key not tied to a single provider: it backs the "Text from URL" feature as an alternative to Selenium, and web search in apps whose provider has no native search — see the [Provider Capabilities table](../basic-usage/basic-apps.md#provider-capabilities).

<!-- SCREENSHOT: Settings panel showing Voice & Audio section with TTS Dictionary File Path input field and Auto TTS Max Bytes input -->

### Voice & Audio

**TTS Dictionary File Path** <br />
Enter the path to the text-to-speech dictionary file. The dictionary file is in CSV format and contains comma-separated entries of strings to be replaced and the strings to be used for speech synthesis (no header row is required). When using text-to-speech, the strings to be replaced in the text are replaced with the strings for speech synthesis.

**Auto TTS Max Bytes** <br />
Set the maximum text size (in bytes) for automatic text-to-speech playback in post-completion mode (default: 500). Text exceeding this limit is partially played or skipped.

?> The speech-to-text model is selected in the web UI's Speech panel, not in this settings window. See [Speech Panel](./web-interface.md#speech-settings-panel).

### Services

**Enable MCP Server** <br />
Enable the Model Context Protocol (MCP) server, which exposes Monadic Chat's tools to external AI assistants. See [MCP Integration](../advanced-topics/mcp-integration.md).

**MCP Server Port** <br />
The network port for the MCP server (default: `3100`). Change it only if the port conflicts with another service.

### Install Options

Select optional packages to be installed in the Python container: LaTeX, Python libraries (NLTK, spaCy, gensim, MediaPipe, Transformers), music analysis (librosa, madmom), and system tools (ImageMagick). Saving records the choice but does not rebuild anything: the next Start offers **Rebuild and Start**, or you can rebuild straight away with **Actions → Build Python Container**.

The same panel holds two more groups:

- **Privacy Filter — Additional Languages**: languages detected by the Privacy Filter besides English (German, Spanish, French, Italian, Japanese, Dutch, Portuguese, Chinese). A change takes effect on save, without a rebuild.
- **Knowledge Base Quality Pack (Docling)**: install the extractor container for higher-quality document import, with its OCR languages (English, Japanese, Chinese, Korean). See [Knowledge Base](../apps/knowledge-base.md).

### Actions

Shows the Docker status and provides the operations of the Actions menu: Start, Stop and Restart; the container builds (containers must be stopped before building); Start and Stop JupyterLab; and Import and Export of the Document DB. Running an action saves your unsaved settings first.

### About

Shows the application version, **Check for Updates**, and links to the homepage and the source code.
