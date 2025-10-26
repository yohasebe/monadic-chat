# Installation

## System Requirements :id=system-requirements

- **Docker Desktop**: Recent version recommended
- **Memory**: At least 8GB RAM (16GB recommended)
- **Storage**: Sufficient free disk space for Docker images and user data

## Basic Steps :id=basic-steps

<!-- tabs:start -->

### **macOS**

1. **Install Docker Desktop for Mac**

Check your CPU type:
```shell
$ sysctl -n machdep.cpu.brand_string
```

Download from [Docker Desktop](https://docs.docker.com/desktop/):
- Intel Mac: `Docker Desktop Installer.dmg`
- Apple Silicon: `Docker Desktop Installer Apple Silicon.dmg`

![](../assets/images/mac-docker-download.png ':size=800')

Drag the Docker icon to Applications folder and launch. Accept the service agreement and use recommended settings.

2. **Download and install Monadic Chat**

📦 [Download the latest release for macOS](https://github.com/yohasebe/monadic-chat/releases/latest)

### **Windows**

1. **Install WSL2**

Open PowerShell as administrator and run:
```shell
> wsl --install -d Ubuntu
```

![](../assets/images/win-wsl-install.png ':size=800')

Restart your computer. Set up Ubuntu username and password when prompted.

2. **Install Docker Desktop**

Download from [Docker Desktop](https://docs.docker.com/desktop/) and install.

![](../assets/images/win-docker-download.png ':size=800')

Accept the service agreement and use recommended settings.

3. **Download and install Monadic Chat**

📦 [Download the latest release for Windows](https://github.com/yohasebe/monadic-chat/releases/latest)

### **Linux**

1. **Install Docker Desktop for Linux**

Refer to Docker documentation:
- [For Debian](https://docs.docker.jp/desktop/install/debian.html)
- [For Ubuntu](https://docs.docker.jp/desktop/install/ubuntu.html)

2. **Download Monadic Chat**

📦 [Download the latest release for Linux](https://github.com/yohasebe/monadic-chat/releases/latest)

3. **Install the package**

```shell
$ sudo apt install ./monadic-chat-*.deb
```

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

![](../assets/images/monadic-chat-menu.png ':size=240')

Monadic Chat automatically checks for updates on startup.

**Update process:**

1. If an update is available, a notification appears in the main console
2. Go to `File` → `Check for Updates`
3. Choose "Download Now" to get the installer for your platform
4. Quit Monadic Chat and run the new installer
5. The new version will replace the existing installation

You can also manually download from the [GitHub Releases page](https://github.com/yohasebe/monadic-chat/releases/latest).

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
