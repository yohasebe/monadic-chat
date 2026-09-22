# Monadic Chat Console Panel

## Console Button Items

<!-- SCREENSHOT: Console panel main window showing Start, Stop, Restart, Open Browser, Shared Folder, and Quit buttons with status display area -->

The console panel is the main control interface for Monadic Chat. It displays the current status (Stopped, Starting, Running, etc.) and provides quick access buttons for common operations.

**Start** <br />
Launch Monadic Chat. The initial startup may take some time due to environment setup on Docker.

**Stop** <br />
Stop Monadic Chat.

**Restart** <br />
Restart Monadic Chat.

**Browser** <br />
Open Monadic Chat in a web browser.
Access URL: [http://localhost:4567](http://localhost:4567)

**Shared Folder** <br />
Open the folder shared between the host and Docker containers. It can be used for importing and exporting files, and when installing additional apps. See [Shared Folder](../docker-integration/shared-folder.md) for the folder layout and the role of each subfolder (`apps`, `helpers`, `scripts`).

**Settings** <br />
Open the settings panel described in [Settings Panel](#settings-panel) below.

**Quit** <br />
Exit the Monadic Chat Console.

## Console Menu Items

<!-- SCREENSHOT: Console menu bar showing File, Actions, Open menu items -->

The console has a menu bar at the top with several dropdown menus for additional functionality.

### Actions Menu

<!-- SCREENSHOT: Actions menu dropdown showing Install Options, Start, Stop, Restart, Build options, JupyterLab controls, and Document DB import/export options -->

**Install Options** <br />
Open the Install Options panel of the settings window, where you can select optional packages (LaTeX, Python libraries, Privacy Filter languages, etc.) to be installed in the service containers.

**Start** <br />
Launch Monadic Chat. The initial startup may take some time due to environment setup on Docker.

**Stop** <br />
Stop Monadic Chat.

**Restart** <br />
Restart Monadic Chat.

**Build All** <br />
Build all Docker images and containers for Monadic Chat.

?> **Note:** Build commands triggered from the menu always run with Docker's `--no-cache` flag so that newly released Dockerfile changes and dependencies are applied immediately.

**Build Ruby Container** <br />
Build the Docker image and container (`monadic-chat-ruby-container`) that powers Monadic Chat.

**Build Python Container** <br />
Build the Docker image and container (`monadic-chat-python-container`) used by the AI agents.

**Build User Containers** <br />
Build the Docker images and containers defined by the user. Note that user-defined containers are not automatically built when starting Monadic Chat - you must use this menu option to build them manually after adding or modifying user container definitions.

**Build Privacy Container** <br />
Build the Docker image and container (`monadic-chat-privacy-container`) used by the Privacy Filter feature.

**Build Extractor Container** <br />
Build the Docker image and container (`monadic-chat-extractor-container`) used for extracting text from document files.

**Start JupyterLab** <br />
Launch JupyterLab at [http://localhost:8889](http://localhost:8889). See [JupyterLab Integration](../docker-integration/jupyterlab.md) for details.

**Stop JupyterLab** <br />
Stop JupyterLab.

**Import Document DB** <br />
Import the entire Document DB (saved conversations, PDFs, and Knowledge Base entries) from a previously exported tarball in the shared folder. A confirmation dialog warns that importing OVERWRITES the current database. The accepted filenames are `monadic-qdrant.tar.gz` (plain) or `monadic-qdrant.tar.gz.enc` (encrypted, prompts for the passphrase used at export time).

**Export Document DB** <br />
Export the entire Document DB to the shared folder. A confirmation dialog offers two choices: **Encrypt and Export** (default — prompts for a passphrase and writes `monadic-qdrant.tar.gz.enc`) or **Export Plain** (writes `monadic-qdrant.tar.gz` unencrypted, with a strong warning that every saved conversation and PDF travels in cleartext). Use the encrypted form for any export that may leave your machine. For the encryption format and import/decryption behavior, see [Privacy Filter](../advanced-topics/privacy-filter.md#document-db-export-import).

### Open Menu

<!-- SCREENSHOT: Open menu dropdown showing Open Browser, Open noVNC, Open Shared Folder, Open Config Folder, Open Log Folder, Open Console, and Settings options -->

**Open Browser** <br />
Open the default browser to access Monadic Chat at [http://localhost:4567](http://localhost:4567)

**Open noVNC** <br />
Open a noVNC viewer window that shows the screen of the browser running inside the Selenium container. This lets you watch (and interact with) web automation in real time. Available while Monadic Chat is running.

**Open Shared Folder** <br />
Open the folder shared between the host and Docker containers. It can be used for importing and exporting files, and when installing additional apps. See [Shared Folder](../docker-integration/shared-folder.md) for the folder layout and the role of each subfolder (`apps`, `helpers`, `scripts`).

**Open Config Folder** <br />
Open the `~/monadic/config` folder. This folder contains configuration files for Monadic Chat. The following files are included:

- `env`: Configuration file (can be configured through GUI).
- `pysetup.sh`: Script for setting up the Python environment (optional, user-created).
- `rbsetup.sh`: Script for setting up the Ruby environment (optional, user-created).
- `compose.yml`: Docker Compose configuration file (auto-generated when user containers are present).

**Open Log Folder** <br />
Open the `~/monadic/log` folder. This folder contains log files for Monadic Chat. The following files are included:

- `docker_build.log`: Log file for Docker build.
- `docker_startup.log`: Log file for Docker startup.
- `server.log`: Log file for the Monadic Chat server.
- `command.log`: Log file for command execution and code execution.
- `jupyter.log`: Log file for cells added to jupyter notebook.

When `Extra Logging` is enabled in the settings panel, an additional `extra.log` records each chat as streaming JSON objects, from the start of Monadic Chat until it exits. It is intended for debugging.

**Open Console** <br />
Open the Monadic Chat console.

**Settings** <br />
Open the Monadic Chat settings panel. Note that this is different from the System Settings panel within the web interface.

### File Menu

**About Monadic Chat** <br />
Shows information about the application version.

**Check for Updates** <br />
Checks for and downloads application updates. When an update is available, you'll see a dialog with the option to download it. After downloading, you'll be prompted to restart the application to apply the update.

**Remove Images/Containers/Data** <br />
Removes all Docker images, containers, and stored data (including PDF vector embeddings) for Monadic Chat.

**How to Uninstall** <br />
Opens the online documentation with complete uninstallation instructions for your operating system.

**Quit Monadic Chat** <br />
Exits the application.

## Settings Panel

Settings configured in the settings panel are automatically saved. The settings panel is organized into the following sections, accessible from the sidebar: **General**, **System**, **API Keys**, **Voice & Audio**, **Services**, **Install Options**, **Actions**, and **About**.

### General

**UI Language** <br />
Select the display language of the console and settings window.

**Browser Mode** <br />
Select the browser to use when opening Monadic Chat from the console. "Internal Browser" opens the built-in Electron browser window, while "External Browser" opens your system's default web browser. The default is "Internal Browser".

**Syntax Highlighting Theme** <br />
Select the theme for code syntax highlighting. The default is `github-light`.

### System

**Launch at Login** <br />
Start Monadic Chat automatically when you log in to your computer.

**Menu Bar Mode** <br />
Keep Monadic Chat running in the menu bar (system tray) instead of showing a console window.

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

`TAVILY_API_KEY` is the one key not tied to a single provider: it backs the "From URL" feature as an alternative to Selenium, and web search in apps whose provider has no native search — see the [Provider Capabilities table](../basic-usage/basic-apps.md#provider-capabilities).

<!-- SCREENSHOT: Settings panel showing Voice & Audio section with TTS Dictionary File Path input field and Auto TTS Max Bytes input -->

### Voice & Audio

**TTS Dictionary File Path** <br />
Enter the path to the text-to-speech dictionary file. The dictionary file is in CSV format and contains comma-separated entries of strings to be replaced and the strings to be used for speech synthesis (no header row is required). When using text-to-speech, the strings to be replaced in the text are replaced with the strings for speech synthesis.

**Auto TTS Max Bytes** <br />
Set the maximum text size (in bytes) for automatic text-to-speech playback in post-completion mode. Text exceeding this limit is partially played or skipped.

?> The speech-to-text model is selected in the web UI's Speech Settings panel, not in this settings window. See [Speech Settings Panel](./web-interface.md#speech-settings-panel).

### Services

**Application Mode** <br />
Select the application mode. "Standalone" mode runs the application for a single device while "Server" mode allows multiple devices in the local network to connect to the Monadic Chat server. The default is "Standalone".

**Enable MCP Server** <br />
Enable the Model Context Protocol (MCP) server, which exposes Monadic Chat's tools to external AI assistants. See [MCP Integration](../advanced-topics/mcp-integration.md).

**MCP Server Port** <br />
The network port for the MCP server (default: `3100`). Change it only if the port conflicts with another service.

### Install Options

Select optional packages to be installed in the service containers: LaTeX, Python libraries (NLTK, spaCy, etc.), music analysis libraries, and system tools. Saving records the choice but does not rebuild anything — the next Start offers **Rebuild and Start**, or you can rebuild straight away with **Actions → Build Python Container**.

The additional Privacy Filter languages in the same panel work differently: every language model is already in the Privacy container, so a change there takes effect on save with no rebuild.

### Actions

Provides the same container lifecycle operations as the Actions menu: Start, Stop, and Restart, plus the container build commands. Containers must be stopped before building.

### About

Shows the application version and related information.
