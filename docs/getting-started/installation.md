# Installation

## Basic Steps :id=basic-steps

<!-- tabs:start -->

### **macOS**

For macOS, follow these steps to install Monadic Chat.

1. Install Docker Desktop for Mac.
2. Download and install the Monadic Chat installer:

- 📦 [Installer package for macOS ARM64 (Apple Silicon)](https://github.com/yohasebe/monadic-chat/releases/download/v1.0.0-beta.2/Monadic.Chat-1.0.0-beta-2-arm64.dmg)
- 📦 [Installer package for macOS x64 (Intel)](https://github.com/yohasebe/monadic-chat/releases/download/v1.0.0-beta.2/Monadic.Chat-1.0.0-beta-2-x64.dmg)


### **Windows**

For Windows, follow these steps to install Monadic Chat.

1. Install WSL2.
2. Install Docker Desktop for Windows.
3. Download and install the Monadic Chat installer:

- 📦 [Installer package for Windows](https://github.com/yohasebe/monadic-chat/releases/download/v1.0.0-beta.2/Monadic.Chat.Setup.1.0.0-beta-2.exe)


### **Linux**

For Linux (Ubuntu/Debian), follow these steps to install Monadic Chat.

1. Install Docker Desktop for Linux.

Refer to: [Install Docker Desktop on Linux](https://docs.docker.jp/desktop/install/linux-install.html)

2. Download the Monadic Chat installer:

- 📦 [Installer package for Linux (Ubuntu/Debian) x64](https://github.com/yohasebe/monadic-chat/releases/download/v1.0.0-beta.2/monadic-chat_1.0.0-beta-2_amd64.deb)
- 📦 [Installer package for Linux (Ubuntu/Debian) arm64](https://github.com/yohasebe/monadic-chat/releases/download/v1.0.0-beta.2/monadic-chat_1.0.0-beta-2_arm64.deb)


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