---
title: Monadic Chat
layout: default
---

# Setting Up Monadic Chat on Windows 11 Home
{:.no_toc}

[English](/monadic-chat-web/setup_win) |
[日本語](/monadic-chat-web/setup_win_ja)


## Table of Contents
{:.no_toc}

1. toc
{:toc}

## 1. Install WSL2

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

## 2. Docker Desktop

Next, install Docker Desktop, which is software for creating container-based virtual environments.

Download Docker Desktop from [Install Docker Desktop on Windows](https://hub.docker.com/editions/community/docker-ce-desktop-windows).

<img src="./assets/images/win-docker-download.png" width="800px"/>

Double-click the downloaded exe file. Once the installation is complete, start Docker Desktop. When you start Docker Desktop first time, you may be asked to accept the service agreement (→ press accept) and choose settings (→ use recommended settings).

Once everything has been set up, the Docker Desktop icon will appear in the task tray at the bottom right of the screen. After Docker Desktop has started, you may close the Docker Desktop Dashboard window if it is open.

## 3. Download and build Monadic Chat

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
$ ./docker/monadic.sh start
```

The first time you run the `start` command, it may take some time for the build process to finish, but from the second time on, the app will start immediately.

<img src="./assets/images/win-build-source.png" width="800px"/>

Once the build is complete, the following message will be displayed:

```text
✔️ Container monadic-chat-db-1  Started
✔️ Container monadic-chat-web-1 Started
```

Now you can access Monadic Chat from your browser at `http://localhost:4567`. 

<img src="./assets/images/win-browser.png" width="800px"/>

## 4. Start/Stop/Restart Monadic Chat

To start/stop/restart Monadic Chat, run one of the following commands:

**`start`**

```shell
$ cd ~/monadic-chat
$ ./docker/monadic.sh start
```

**`stop`**

```shell
$ cd ~/monadic-chat
$ ./docker/monadic.sh stop
```

**`restart`**

```shell
$ cd ~/monadic-chat
$ ./docker/monadic.sh restart
```

## 5. Update Monadic Chat

To update Monadic Chat, execute the following command:

**`update`**

```shell
$ cd ~/monadic-chat
$ ./docker/monadic.sh update
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
