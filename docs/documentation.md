---
title: Monadic Chat
layout: default
---

# Documentation
{:.no_toc}

[English](https://yohasebe.github.io/monadic-chat/documentation) |
[日本語](https://yohasebe.github.io/monadic-chat/documentation_ja)

### Installation (MacOS)

#### Homebrew

First, install [Homebrew](https://brew.sh), which is a package management system for MacOS.

Open the terminal. The location of the terminal on Mac is `Application -> Utilities -> Terminal.app`. Once you have opened the terminal, execute the following command (the first `$` represents the command line prompt).

```shell
$ /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
```

#### Git

Next, let's make sure you can use the git command, which is a version control system for source code.

```shell
$ brew install git
```

#### Docker Desktop

Next, install Docker Desktop, which is software for creating container-based virtual environments.

Use a different package depending on your Mac's CPU. You can check the type of CPU on the terminal with the following command:

```shell
$ sysctl -n machdep.cpu.brand_string
```

Download Docker Desktop from [Install Docker Desktop on Mac](https://hub.docker.com/editions/community/docker-ce-desktop-mac), but for Intel, download `Docker Desktop Installer.dmg`, and for Apple Silicon, download `Docker Desktop Installer Apple Silicon.dmg`.

Double-click the downloaded dmg file to start the installation. Once the installation is complete, start Docker Desktop. When you start Docker Desktop, the Docker icon will appear in the menu bar.

#### Download the Monadic Chat source code

Open the terminal and move to the location where you want to copy the Monadic Chat source code. Here, we will copy the source code to the home directory. Normally, when you open the terminal, that is the home directory, but just in case, let's move to the home directory with the following command:

```shell
$ cd ~
```

If you execute the following command here, a directory called `monadic-chat` will be created in the home directory, and the source code will be downloaded into it.

```shell
$ git clone https://github.com/yohasebe/monadic-chat.git
```

#### Build Monadic Chat

Move to the directory of the source code you downloaded earlier.

```shell
$ cd ~/monadic-chat
```

If you execute the following command here, Monadic Chat will be built and started.

```shell
$ ./docker/monadic.sh start
```

The first time it may take some time to build, but from the second time on, it will start immediately.

#### Start Monadic Chat

If the build is complete, you can start Monadic Chat with the following command. If Docker Desktop is not running, it will start automatically with this command.

```shell
$ cd ~/monadic-chat
$ ./docker/monadic.sh start
```

On Mac, when Monadic Chat starts up, the home screen will open in the system's default browser. If the screen does not open, please open `http://localhost:4567` in your browser (or reload the page).

#### Stop Monadic Chat

To stop Monadic Chat, execute the following command:

```shell
$ cd ~/monadic-chat
$ ./docker/monadic.sh stop
```

#### Update Monadic Chat

To update Monadic Chat, execute the following command:

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
