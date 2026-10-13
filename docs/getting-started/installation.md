# Installation

## System Requirements :id=system-requirements

- **Docker**: Docker Desktop (a recent version), or Docker Engine on Linux
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

📦 [Download Monadic Chat 1.0.0-beta.43 for macOS](https://github.com/yohasebe/monadic-chat/releases/download/v1.0.0-beta.43/Monadic.Chat-1.0.0-beta.43-arm64.dmg)

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

📦 [Download Monadic Chat 1.0.0-beta.43 for Windows](https://github.com/yohasebe/monadic-chat/releases/download/v1.0.0-beta.43/Monadic.Chat.Setup.1.0.0-beta.43.exe)

### **Linux**

1. **Install Docker**

Install either Docker Desktop for Linux or Docker Engine:
- Docker Desktop: [for Debian](https://docs.docker.com/desktop/setup/install/linux/debian/), [for Ubuntu](https://docs.docker.com/desktop/setup/install/linux/ubuntu/)
- Docker Engine: [installation guide](https://docs.docker.com/engine/install/)

With Docker Engine, your user must be able to run `docker` without `sudo`. Add it to the `docker` group, then log out and back in:

```shell
$ sudo usermod -aG docker $USER
```

On Omarchy, run `omarchy-setup-security-sudoless-docker` instead. Membership in the `docker` group gives root-equivalent access to the machine. When your user cannot use Docker, Monadic Chat shows this command.

2. **Download Monadic Chat**

📦 [Download Monadic Chat 1.0.0-beta.43 for Linux (x86_64)](https://github.com/yohasebe/monadic-chat/releases/download/v1.0.0-beta.43/monadic-chat_1.0.0-beta.43_x86_64.AppImage) — [arm64](https://github.com/yohasebe/monadic-chat/releases/download/v1.0.0-beta.43/monadic-chat_1.0.0-beta.43_arm64.AppImage)

3. **Make it executable and run it**

An AppImage needs no installation. Mark it executable and launch it:

```shell
$ chmod +x monadic-chat_*.AppImage
$ ./monadic-chat_*.AppImage
```

The AppImage mounts itself through FUSE. FUSE 3, which current distributions include, is enough; `libfuse2` is not required. Where FUSE is not available, run the AppImage with `--appimage-extract-and-run`.

<!-- tabs:end -->

## Initial Setup :id=initial-setup

After installation:

1. Click **Settings** in the console, open **API Keys**, enter the keys for the AI services you want to use, and click **Save**
2. Click **Start**. The first start downloads the prebuilt images and builds the Ruby and Python images, which takes 10–30 minutes depending on your internet connection and computer. Later starts reuse them
3. When everything is ready, the **System** status in the console shows **Started** in green, and **Open Browser** becomes available

For detailed usage instructions, see the [Web Interface](../basic-usage/web-interface.md) section.

## Updating Monadic Chat :id=update

<!-- SCREENSHOT: Monadic Chat menu showing File menu with Check for Updates option -->

Monadic Chat checks for updates when it starts (when it is online).

1. When a newer version is available, a **Download & Install** button appears in the console. To check yourself, choose **Check for Updates** in the File menu (on macOS, the Monadic Chat menu)
2. Click **Download & Install**. The update downloads in the background, with its progress shown in the console
3. When the download completes, choose **Restart Now** to install it, or **Later**

You can also download it yourself from the [release page for 1.0.0-beta.43](https://github.com/yohasebe/monadic-chat/releases/tag/v1.0.0-beta.43), or browse [all releases](https://github.com/yohasebe/monadic-chat/releases).

## Advanced Configuration :id=advanced-configuration

For advanced configuration options including:
- Install Options (LaTeX, Python libraries, etc.)
- Rebuild procedures
- Environment variables

See [Advanced Configuration](../advanced-topics/advanced-configuration.md).

## Troubleshooting :id=troubleshooting

If you encounter issues, refer to these FAQ sections:
- [Setup and Settings FAQ](../faq/faq-settings.md)
- [Basic Applications FAQ](../faq/faq-basic-apps.md)
- [User Interface FAQ](../faq/faq-user-interface.md)
