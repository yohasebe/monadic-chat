# Installation

## Basic Steps :id=basic-steps

<!-- tabs:start -->

### **macOS**

For macOS, follow these steps to install Monadic Chat.

1. Install Docker Desktop for Mac.
2. Download and install the Monadic Chat installer:

- 📦 [Download the latest release for macOS](https://github.com/yohasebe/monadic-chat/releases/latest)


### **Windows**

For Windows, follow these steps to install Monadic Chat.

1. Install WSL2.
2. Install Docker Desktop for Windows.
3. Download and install the Monadic Chat installer:

- 📦 [Download the latest release for Windows](https://github.com/yohasebe/monadic-chat/releases/latest)


### **Linux**

For Linux (Ubuntu/Debian), follow these steps to install Monadic Chat.

1. Install Docker Desktop for Linux.

Refer to: [Install Docker Desktop on Linux](https://docs.docker.jp/desktop/install/linux-install.html)

2. Download the Monadic Chat installer:

- 📦 [Download the latest release for Linux](https://github.com/yohasebe/monadic-chat/releases/latest)


3. Run the following command in the terminal to install the downloaded package:

```shell
$ sudo apt install ./monadic-chat-*.deb
```

<!-- tabs:end -->

## Initial Setup :id=initial-setup

After installation, when you first launch Monadic Chat:

1. The application will start building Docker containers automatically
2. **Initial setup time**: This process can take significant time (varies greatly based on internet connection and system performance). The initial build downloads and builds multiple containers totaling approximately 12GB.
3. **Subsequent startups**: After the initial build, starting Monadic Chat is much faster as existing containers are reused. Container rebuilds are only needed when updating to newer versions of Monadic Chat.
4. You'll need to configure API keys in the Settings panel for the AI services you want to use
5. Once the containers are ready, the status indicator will turn green

For detailed setup instructions, see the [Web Interface](../basic-usage/web-interface.md) section.

## Install Options & Rebuild :id=install-options

From the app menu “Actions → Install Options…”, choose optional components for the Python container.

- LaTeX (with TeX Live + CJK): Enables Concept Visualizer / Syntax Tree with built-in Japanese/Chinese/Korean support (requires OpenAI or Anthropic key)
- Python libraries (CPU): `nltk`, `spacy (3.7.5)`, `scikit-learn`, `gensim`, `librosa`, `transformers`
- Tools: ImageMagick (`convert`/`mogrify`)

Panel behavior:
- The Install Options window is modal and matches the Settings panel size.
- Save does not close the window; a green check briefly confirms success.
- If you click Close with unsaved changes, a confirmation dialog offers “Save and Close” or “Cancel”.
- All labels, descriptions, and dialogs follow your UI language (EN/JA/ZH/KO/ES/DE/FR).

Saving does not trigger a rebuild automatically. When ready, run Rebuild from the main console to update the Python image. The update is atomic (build → verify → promote on success) and progress/logs appear in the main console. A per-run summary and health check are written alongside the logs.

Start behavior: When you click Start, the system runs an orchestration health check. If needed, the Ruby control-plane is automatically refreshed once (cache-friendly) and the startup proceeds. This is presented as informational prompts; finally a green “Ready” indicates success.

Probe tuning (optional) in `~/monadic/config/env`:

```
START_HEALTH_TRIES=20
START_HEALTH_INTERVAL=2
```

Dependency-aware Ruby rebuild
- Ruby is rebuilt only when the Gem dependency fingerprint (SHA256 of `Gemfile` + `monadic.gemspec`) changes. The image carries this value as `com.monadic.gems_hash`; when it differs from your working copy, a refresh is performed using Docker cache so the bundle layer is reused whenever possible.
- To force a clean rebuild for troubleshooting, set:

```
FORCE_RUBY_REBUILD_NO_CACHE=true
```

Logs (overwritten each run):

- Python build: `~/monadic/log/docker_build_python.log`, `~/monadic/log/post_install_python.log`, `~/monadic/log/python_health.json`, `~/monadic/log/python_meta.json`
- Ruby/User/Ollama build: `~/monadic/log/docker_build.log`

NLTK and spaCy behavior

- Enabling `nltk` installs the library only (no datasets/corpora are downloaded automatically).
- Enabling `spacy` installs `spacy==3.7.5` only (no language models downloaded).
- Recommended: add a `~/monadic/config/pysetup.sh` to fetch what you need during post-setup. Example:

```sh
#!/usr/bin/env bash
set -euo pipefail

python - <<'PY'
import nltk
for pkg in ["punkt","stopwords","averaged_perceptron_tagger","wordnet","omw-1.4","vader_lexicon"]:
    nltk.download(pkg, raise_on_error=True)
PY

python -m spacy download en_core_web_sm
python -m spacy download en_core_web_lg
```

For Japanese and additional corpora

```sh
#!/usr/bin/env bash
set -euo pipefail

# spaCy Japanese models (pick one)
python -m spacy download ja_core_news_sm
# or: ja_core_news_md / ja_core_news_lg

# NLTK extra corpora frequently used in examples
python - <<'PY'
import nltk
for pkg in ["brown","reuters","movie_reviews","conll2000","wordnet_ic"]:
    nltk.download(pkg, raise_on_error=True)
PY
```

Full NLTK download (all datasets)

```sh
#!/usr/bin/env bash
set -euo pipefail

export NLTK_DATA=/monadic/data/nltk_data
mkdir -p "$NLTK_DATA"

python - <<'PY'
import nltk, os
nltk.download('all', download_dir=os.environ.get('NLTK_DATA','/monadic/data/nltk_data'))
PY
```
Note: Downloading “all” is large (GBs) and may take considerable time.

## Preparation :id=preparation

### System Requirements :id=system-requirements

- **Docker Desktop**: Version 4.20 or later (tested with 4.20+; older versions may work but are not guaranteed)
- **Memory**: At least 8GB RAM (16GB recommended for optimal performance)
- **Storage**: Minimum 15GB free disk space (approximately 12GB for Docker images plus additional space for user data and logs)

<!-- tabs:start -->

### **macOS**

For macOS, follow these steps to install Docker Desktop. Docker Desktop is software for creating containerized virtual environments.

Use different packages depending on your Mac's CPU. You can check the type of CPU with the following command in the terminal.

```shell
$ sysctl -n machdep.cpu.brand_string
```

Download and install Docker Desktop from [Docker Desktop](https://docs.docker.com/desktop/). For Intel, download `Docker Desktop Installer.dmg`, and for Apple Silicon, download `Docker Desktop Installer Apple Silicon.dmg`.

![](../assets/images/mac-docker-download.png ':size=800')

Double-click the downloaded dmg file to display a window, then drag the Docker icon to the Applications folder. Once the installation is complete, launch Docker Desktop. You will be asked to agree to the service agreement (accept it). You will also be asked whether to use the recommended settings (use the recommended settings unless you have specific preferences). You will also be prompted to enter your Mac username and password for internal use of osascript.

Once Docker Desktop is launched, the Docker icon will appear in the taskbar. You can close the Docker Desktop dashboard window at this point.

### **Windows**

To use Monadic Chat on Windows 11, you need to install Windows Subsystem for Linux 2 (WSL2) and Docker Desktop. Below is the method to install Monadic Chat on Windows 11 Home. The same method can be used for Windows 11 Pro and Windows 11 Education.

#### Installing WSL2

First, install [WSL2](https://docs.microsoft.com/en-us/windows/wsl/install), which is a mechanism to realize a Linux environment on Windows.

Open PowerShell in administrator mode. Search for PowerShell in the Windows search box and select "Run as administrator" to launch powershell.exe.

![](../assets/images/win-powershell.png ':size=800')

Next, execute the following command in PowerShell (the initial `>` represents the command line prompt).

```shell
> wsl --install -d Ubuntu 
```

![](../assets/images/win-wsl-install.png ':size=800')

Then restart your computer. After restarting, WSL2 and Ubuntu will be installed. During this process, you will be prompted to enter a username and password for the Linux environment. Enter any username and password. You will need to remember this username and password for later use.

This completes the installation of WSL2. Ubuntu is now available on Windows. Search for "Ubuntu" in the Windows search box and open the Ubuntu terminal.

![](../assets/images/win-ubuntu.png ':size=800')

#### Installing Docker Desktop

Next, install Docker Desktop, software for creating virtual environments using containers.

Download Docker Desktop from [Docker Desktop](https://docs.docker.com/desktop/).

![](../assets/images/win-docker-download.png ':size=800')

Double-click the downloaded exe file to start the installation. Once the installation is complete, launch Docker Desktop. When you first launch Docker Desktop, you will be asked to agree to the service agreement (agree) and whether to select settings (use recommended settings).

Once these are complete, the Docker Desktop icon will appear in the task tray at the bottom right of the screen. Once Docker Desktop is launched, you can close the Docker Desktop Dashboard window.

### **Linux**

For Linux (Ubuntu/Debian), refer to the following pages to install Docker Desktop.

- [For Debian](https://docs.docker.jp/desktop/install/debian.html)
- [For Ubuntu](https://docs.docker.jp/desktop/install/ubuntu.html)

<!-- tabs:end -->

## Server Mode Configuration :id=server-mode-configuration

?> **Note: Monadic Chat is designed primarily for standalone mode, where all components run on a single machine. Server mode should only be used when you need to share the service with multiple users on a local network.**

By default, Monadic Chat runs in standalone mode with all components on a single machine. To enable server mode:

1. Open the Settings panel by clicking the gear icon in the application
2. In the "Application Mode" dropdown, select "Server Mode"
3. Click "Save" to apply the changes
4. Restart the application

In server mode:
- The server hosts all Docker containers and web services
- Multiple clients can connect to the server via their web browsers
- Network URLs (like Jupyter notebooks) will use the server's external IP address
- Clients can access resources hosted on the server

See the [Server Mode Architecture](../docker-integration/basic-architecture.md#server-mode) documentation for more details.

## Updating Monadic Chat :id=update

![](../assets/images/monadic-chat-menu.png ':size=240')

Monadic Chat automatically checks for updates when it starts. If a new version is available, a notification will be displayed in the main console window.

The update process follows these steps:

1. When the application starts, it automatically checks for updates in the background
2. If an update is available, a message appears in the main console window
3. To download the update, go to `File` → `Check for Updates`
4. A dialog will appear showing the version information with options to:
   - **Download Now**: Downloads the update file directly for your platform
   - **View All Releases**: Opens the GitHub releases page
   - **Cancel**: Closes the dialog
5. If you choose "Download Now", your browser will start downloading the appropriate installer for your system
6. Once downloaded, quit Monadic Chat and run the new installer
7. The new version will replace the existing installation

The system automatically detects your platform (macOS, Windows, or Linux) and architecture (ARM64 or x64) to provide the correct download link.

You can also manually download the latest version from the [GitHub Releases page](https://github.com/yohasebe/monadic-chat/releases/latest).

## Troubleshooting :id=troubleshooting

If you encounter any issues during installation, please refer to the FAQ sections for common problems and solutions:
- [Setup and Settings FAQ](../faq/faq-settings.md)
- [Basic Applications FAQ](../faq/faq-basic-apps.md)
- [User Interface FAQ](../faq/faq-user-interface.md)
