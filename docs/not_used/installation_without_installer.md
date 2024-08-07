---
title: Monadic Chat
layout: default
---

# Installation
{:.no_toc}

[English](/monadic-chat/installation_without_installer) |
[日本語](/monadic-chat/installation_without_installer_ja)

## Table of Contents
{:.no_toc}

1. toc
{:toc}

## macOS

### Install Homebrew and Git

First, install [Homebrew](https://brew.sh), which is a package management system for macOS.

Open the terminal. The location of the terminal on Mac is `Application -> Utilities -> Terminal.app`.

<img src="./assets/images/mac-terminal.png" width="800px"/>

Once you have opened the terminal, execute the following command (the first `$` represents the command line prompt).

```shell
$ /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" 
```

<img src="./assets/images/mac-homebrew-01.png" width="800px"/>

If you are asked for your password, enter your Mac's password. The password will not be displayed on the screen, so enter it carefully.

You will be asked to press the Enter key to continue. Press the Enter key to continue.

<img src="./assets/images/mac-homebrew-02.png" width="800px"/>

After a while, the installation will be completed. If "Run these two commands in your terminal to add Homebrew to your PATH" is displayed as in the screenshot above, copy the commands and execute them in the terminal.

Next, let's make sure you can use the git command, which is a version control system for source code.

```shell
$ brew install git
```

### Install Docker Desktop

Next, install Docker Desktop, which is software for creating container-based virtual environments.

Choose on of the two different packages depending on your Mac's CPU. You can check the type of CPU on the terminal with the following command:

```shell
$ sysctl -n machdep.cpu.brand_string
```

Download Docker Desktop from [Install Docker Desktop on Mac](https://hub.docker.com/editions/community/docker-ce-desktop-mac), but for Intel, download `Docker Desktop Installer.dmg`, and for Apple Silicon, download `Docker Desktop Installer Apple Silicon.dmg`.

<img src="./assets/images/mac-docker-download.png" width="800px"/>

Double-click the downloaded dmg file. Then drag and drop the docker icon to the Applications folder to install it. Once the installation is complete, start Docker Desktop. When you start Docker Desktop first time, you will be asked to accept the service agreement (→ press accept), choose settings (→ use recommended settings), and allow privileged access to apply configuration (→ enter your Mac username and password).

Once everything has been set up, the Docker Desktop icon will appear in the menu bar at the top right of the screen. After Docker Desktop has started, you may close the Docker Desktop Dashboard window if it is open.

### Download and build Monadic Chat

Open the terminal once again and move to the location where you want to copy the Monadic Chat source code. If you use your home directory, execute the following command to go to the home directory:

```shell
$ cd ~
```

Now let us clone the Monadic Chat source code package in the home directory. The following command will download the source code from Github and copy it to the `~/monadic-chat` directory.

```shell
$ git clone https://github.com/yohasebe/monadic-chat.git
```

Then move inside this directory and execute the `start` command as below:

```shell
$ cd ~/monadic-chat
$ ./monadic.sh start
```

The first time you run the `start` command, it may take some time for the build process to finish, but from the second time on, the app will start immediately.

<img src="./assets/images/mac-build-source.png" width="800px"/>

Once the build is complete, the following message will be displayed:

```text
✔️ Container monadic-chat-db-1  Started
✔️ Container monadic-chat-web-1 Started
```

Now you can access Monadic Chat from your browser at `http://localhost:4567`. 

<img src="./assets/images/mac-browser.png" width="800px"/>

### Start/Stop/Restart Monadic Chat

To start/stop/restart Monadic Chat, run one of the following commands:

**`start`**

```shell
$ cd ~/monadic-chat
$ ./monadic.sh start
```

**`stop`**

```shell
$ cd ~/monadic-chat
$ ./monadic.sh stop
```

**`restart`**

```shell
$ cd ~/monadic-chat
$ ./monadic.sh restart
```

### Update Monadic Chat

To update Monadic Chat, execute the following command:

**`update`**

```shell
$ cd ~/monadic-chat
$ ./monadic.sh update
```

The above command downloads the latest source code from Github and rebuilds Monadic Chat.

## Windows

Below, the method to install Monadic Chat on Windows 11 Home will be explained. The same method can be used for Windows 11 Pro and Windows 11 Education as well.

### Install WSL2

First, install [WSL2](https://brew.sh), which is a Linux environment for Windows.

Open PowerShell in the administrator mode. To do this, search PowerShell (`Start -> Windows PowerShell`) and select "Run as administrator".

<img src="./assets/images/win-powershell.png" width="800px"/>

Then execute the following command (the first `>` represents the command line prompt):

```shell
> wsl --install
```

<img src="./assets/images/win-wsl-install.png" width="800px"/>

Then reboot your computer. After rebooting, WSL2 and its default Linux distribution Ubuntu will be installed. During this process, you will be asked to enter a username and password for the Linux environment. Enter any username and password you like. You will need to remember this username and password later.

Now you have completed the installation of WSL2. You can start the Linux environment by searching for "Ubuntu" in the Windows search box and open the Ubuntu terminal. 

<img src="./assets/images/win-ubuntu.png" width="800px"/>

### Docker Desktop

Next, install Docker Desktop, which is software for creating container-based virtual environments.

Download Docker Desktop from [Install Docker Desktop on Windows](https://hub.docker.com/editions/community/docker-ce-desktop-windows).

<img src="./assets/images/win-docker-download.png" width="800px"/>

Double-click the downloaded exe file. Once the installation is complete, start Docker Desktop. When you start Docker Desktop first time, you may be asked to accept the service agreement (→ press accept) and choose settings (→ use recommended settings).

Once everything has been set up, the Docker Desktop icon will appear in the task tray at the bottom right of the screen. After Docker Desktop has started, you may close the Docker Desktop Dashboard window if it is open.

### Download and build Monadic Chat

Open the Ubuntu terminal once again and move to the location where you want to copy the Monadic Chat source code. If you use your home directory, execute the following command to go to the home directory:

```shell
$ cd ~
```

Now let us clone the Monadic Chat source code package in the home directory. The following command will download the source code from Github and copy it to the `~/monadic-chat` directory.

```shell
$ git clone https://github.com/yohasebe/monadic-chat.git
```

Then move inside this directory and execute the `start` command as below:

```shell
$ cd ~/monadic-chat
$ ./monadic.sh start
```

The first time you run the `start` command, it may take some time for the build process to finish, but from the second time on, the app will start immediately.

<img src="./assets/images/win-build-source.png" width="800px"/>

Once the build is complete, the following message will be displayed:

```text
✔️ Container monadic-chat-db-1  Started
✔️ Container monadic-chat-web-1 Started
```

Now you can access Monadic Chat from your browser at `http://localhost:4567`. 

<img src="./assets/images/screenshot-01.png" width="800px"/>

### Start/Stop/Restart Monadic Chat

To start/stop/restart Monadic Chat, run one of the following commands:

**`start`**

```shell
$ cd ~/monadic-chat
$ ./monadic.sh start
```

**`stop`**

```shell
$ cd ~/monadic-chat
$ ./monadic.sh stop
```

**`restart`**

```shell
$ cd ~/monadic-chat
$ ./monadic.sh restart
```

### Update Monadic Chat

To update Monadic Chat, execute the following command:

**`update`**

```shell
$ cd ~/monadic-chat
$ ./monadic.sh update
```

The above command downloads the latest source code from Github and rebuilds Monadic Chat.

<script src="https://cdn.jsdelivr.net/npm/jquery@3.5.0/dist/jquery.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/lightbox2@2.11.3/src/js/lightbox.js"></script>

---

<script>
  function copyToClipBoard(id){
    var copyText =  document.getElementById(id).innerText;
    document.addEventListener('copy', function(e) {
        e.clipboardData.setData('text/plain', copyText);
        e.preventDefault();
      }, true);
    document.execCommand('copy');
    alert('copied');
  }
</script>
