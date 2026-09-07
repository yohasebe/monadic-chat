# Installation

## System Requirements :id=system-requirements

- **Docker Desktop**: Recent version recommended
- **Memory**: At least 8GB RAM (16GB recommended)
- **Storage**: Sufficient free disk space for Docker images and user data
- **macOS**: macOS 13 (Ventura) or later on Apple Silicon (M1 or later). Intel Macs are not supported.

## Basic Steps :id=basic-steps

<!-- tabs:start -->

### **macOS**

> **Note**: macOS requires version 13 (Ventura) or later on Apple Silicon (M1 or later). Intel Macs are not supported.

1. **Install Docker Desktop for Mac**

Download from [Docker Desktop](https://docs.docker.com/desktop/):
- Download `Docker Desktop Installer Apple Silicon.dmg`

Drag the Docker icon to Applications folder and launch. Accept the service agreement and use recommended settings.

2. **Download and install Monadic Chat**

📦 [Download Monadic Chat 1.0.0-beta.33 for macOS](https://github.com/yohasebe/monadic-chat/releases/download/v1.0.0-beta.33/Monadic.Chat-1.0.0-beta.33-arm64.dmg)

### **Windows**

1. **Install WSL2**

Open PowerShell as administrator and run:
```shell
> wsl --install -d Ubuntu
```

<!-- SCREENSHOT: PowerShell window showing WSL installation progress with Ubuntu being installed -->

Restart your computer. Set up Ubuntu username and password when prompted.

2. **Install Docker Desktop**

Download from [Docker Desktop](https://docs.docker.com/desktop/) and install.

<!-- SCREENSHOT: Docker Desktop for Windows download page showing Windows installer download button -->

Accept the service agreement and use recommended settings.

3. **Download and install Monadic Chat**

📦 [Download Monadic Chat 1.0.0-beta.33 for Windows](https://github.com/yohasebe/monadic-chat/releases/download/v1.0.0-beta.33/Monadic.Chat.Setup.1.0.0-beta.33.exe)

### **Linux**

1. **Install Docker Desktop for Linux**

Refer to Docker documentation:
- [For Debian](https://docs.docker.jp/desktop/install/debian.html)
- [For Ubuntu](https://docs.docker.jp/desktop/install/ubuntu.html)

2. **Download Monadic Chat**

📦 [Download Monadic Chat 1.0.0-beta.33 for Linux (x86_64)](https://github.com/yohasebe/monadic-chat/releases/download/v1.0.0-beta.33/monadic-chat_1.0.0-beta.33_x86_64.AppImage) — [arm64](https://github.com/yohasebe/monadic-chat/releases/download/v1.0.0-beta.33/monadic-chat_1.0.0-beta.33_arm64.AppImage)

3. **Make it executable and run it**

An AppImage needs no installation. Mark it executable and launch it:

```shell
$ chmod +x monadic-chat_*.AppImage
$ ./monadic-chat_*.AppImage
```

If your distribution does not ship FUSE 2, either install it (`sudo apt install libfuse2`) or run the AppImage with `--appimage-extract-and-run`.

<!-- tabs:end -->

## Initial Setup :id=initial-setup

After installation, when you first launch Monadic Chat:

1. The application will start building Docker containers automatically
2. **Initial setup time**: This can take significant time (varies based on internet connection and system performance)
3. **Subsequent startups**: Much faster as existing containers are reused
4. Configure API keys in Settings for the AI services you want to use
5. Once ready, the status indicator will turn green

For detailed usage instructions, see the [Web Interface](../basic-usage/web-interface.md) section.

## Updating Monadic Chat :id=update

<!-- SCREENSHOT: Monadic Chat menu showing File menu with Check for Updates option -->

Monadic Chat automatically checks for updates on startup.

**Update process:**

1. If an update is available, a notification with a **Download & Install** button appears in the main console (you can also check manually via `File` → `Check for Updates`)
2. Click **Download & Install** — the update downloads in the background, with progress shown in the console
3. When the download completes, you are prompted to restart Monadic Chat to apply the update

You can also download it yourself from the [release page for 1.0.0-beta.33](https://github.com/yohasebe/monadic-chat/releases/tag/v1.0.0-beta.33), or browse [all releases](https://github.com/yohasebe/monadic-chat/releases).

## Advanced Configuration :id=advanced-configuration

For advanced configuration options including:
- Install Options (LaTeX, Python libraries, etc.)
- Server Mode setup
- Rebuild procedures
- Environment variables

See [Advanced Configuration](../advanced-topics/advanced-configuration.md).

## Troubleshooting :id=troubleshooting

If you encounter issues, refer to these FAQ sections:
- [Setup and Settings FAQ](../faq/faq-settings.md)
- [Basic Applications FAQ](../faq/faq-basic-apps.md)
- [User Interface FAQ](../faq/faq-user-interface.md)
