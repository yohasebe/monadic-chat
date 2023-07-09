---
title: Monadic Chat
layout: default
---

# インストール
{:.no_toc}

[English](/monadic-chat/installation) |
[日本語](/monadic-chat/installation_ja)

## もくじ
{:.no_toc}

1. toc
{:toc}

## MacOS

### HomebrewとGitのインストール

まずは[Homebrew](https://brew.sh/index_ja)をインストールします。HomebrewはMacOSのパッケージ管理システムです。

ターミナルを開いてください。Macのターミナルの場所は、`Application -> ユーティリティー -> ターミナル.app`です。

<img src="./assets/images/mac-terminal.png" width="800px"/>

ターミナルを開いたら、以下のコマンドを実行してください（最初の`$`はコマンドラインのプロンプトを表しています）。

```shell
$ /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" 
```

<img src="./assets/images/mac-homebrew-01.png" width="800px"/>

If you are asked for your password, enter your Mac's password. The password will not be displayed on the screen, so enter it carefully.

Homebrewのインストール時にEnterキーを押すように求められますので、Enterキーを押してください。

<img src="./assets/images/mac-homebrew-02.png" width="800px"/>

After a while, the installation will be completed. If "Run these two commands in your terminal to add Homebrew to your PATH" is displayed as in the screenshot above, copy the commands and execute them in the terminal.

しばらくするとインストールが完了します。"Run these two commands in your terminal to add Homebrew to your PATH"というメッセージが表示されたら、表示されている2つのコマンドをターミナル上で実行してください（`brew`コマンドのパスを通すためです）。

次に`git`コマンドが使えるようにします。Gitはソースコードのバージョン管理システムです。以下のコマンドを実行してください。

```shell
$ brew install git
```

### Docker Desktopのインストール

次にDocker Desktopをインストールします。Docker Desktopはコンテナ型の仮想環境を作成するためのソフトウェアです。

ご自身のMacのCPUに応じて異なるパッケージを用います。CPUの種類はターミナル上で以下のコマンドで確認できます。

```shell
$ sysctl -n machdep.cpu.brand_string
```

[Install Docker Desktop on Mac](https://hub.docker.com/editions/community/docker-ce-desktop-mac)からDocker Desktopをダウンロードしてインストールしますが、その際、Intelの場合は`Docker Desktop Installer.dmg`を、Apple Siliconの場合は`Docker Desktop Installer Apple Silicon.dmg`をダウンロードしてください。

<img src="./assets/images/mac-docker-download.png" width="800px"/>

ダウンロードしたdmgファイルをダブルクリックするとウィンドウが表示されるので、DockerのアイコンをApplicationsフォルダーにドラッグしてください。インストールが完了したら、Docker Desktopを起動しましょう。その際、service agreementへの同意が求められます（acceptしてください）。また、推奨設定を使用するかどうかを確認されます（特にこだわりがなければ推奨設定を用いてください）。また、内部でosascriptを使用するため、Macのユーザ名とパスワードの入力が求められます。

Docker Desktopの起動が完了すると、メニューバーにDockerのアイコンが表示されます。ここでDocker Desktopのダッシュボード・ウィンドウは閉じてしまって構いません。

### Monadic Chatのダウンロードとビルド

Open the terminal once again and move to the location where you want to copy the Monadic Chat source code. If you use your home directory, execute the following command to go to the home directory:

再びターミナルを開いて、Monadic Chatのソースコードをコピーしたい場所に移動します。ここでは、ホームディレクトリににソースコードをコピーすることにします。次のコマンドでホームディレクトリに移動できます。

```shell
$ cd ~
```

ここで以下のコマンドを実行すると、ホームディレクトリに`monadic-chat`というディレクトリが作成され、その中にソースコードがダウンロードされます。

```shell
$ git clone https://github.com/yohasebe/monadic-chat.git
```

ダウンロードが完了したら、下記のように、ソースコードのディレクトリ内に移動して、次に`start`コマンドを実行してください。

```shell
$ cd ~/monadic-chat
$ ./monadic.sh start
```

初回はビルドに時間がかかりますが、2回目以降はすぐに起動できます。

<img src="./assets/images/mac-build-source.png" width="800px"/>

ソースコードのビルドが成功し、Monadic Chatが無事に起動すると、以下のメッセージが表示されます。

```text
✔️ Container monadic-chat-db-1  Started
✔️ Container monadic-chat-web-1 Started
```

Macでは、デフォルト・ブラウザ上でホーム画面が開きます。もし画面が開かない場合は、ブラウザで`http://localhost:4567`を開いてください（または再読み込みしてください）。

<img src="./assets/images/mac-browser.png" width="800px"/>

### Monadic Chatの起動/停止/再起動

Monadic Chatを起動/停止/再起動するには、以下のコマンドを実行します。

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

### Monadic Chatのアップデート

Monadic Chatを最新版に更新するには、以下のコマンドを実行します。

**`update`**

```shell
$ cd ~/monadic-chat
$ ./monadic.sh update
```

これにより、Githubから最新のソースコードがダウンロードされ、Monadic Chatが再ビルドされます。

## Windows

以下ではWindows 11 HomeにMonadic Chatをインストールする方法を説明します。Windows 11 ProやWindows 11 Educationの場合でも基本的に同様の方法でインストール可能です。

### WSL2のインストール

まずはをインストールします。[WSL2](https://brew.sh)はWindows上でLinux環境を実現する仕組みです。

PowerShellを管理者モードで開きます。Windowsの検索ボックスでPowerShellを検索し、"管理者として実行"を選択してpowershell.exeを起動してください。

<img src="./assets/images/win-powershell.png" width="800px"/>

次にPowerShell上で次のコマンドを実行します（最初の`>`はコマンドラインのプロンプトを表します）。

```shell
> wsl --install
```

<img src="./assets/images/win-wsl-install.png" width="800px"/>

そしてコンピュータを再起動します。再起動後、WSL2とそのデフォルトのLinuxディストリビューションであるUbuntuがインストールされます。このプロセスの中で、Linux環境のユーザ名とパスワードを入力するよう求められます。任意のユーザ名とパスワードを入力してください。このユーザ名とパスワードは後で覚えておく必要があります。

これでWSL2のインストールは完了です。Windows上でUbuntuが使えるようになりました。Windowsの検索ボックスで"Ubuntu"を検索し、Ubuntuのターミナルを開いてみてください。

<img src="./assets/images/win-ubuntu.png" width="800px"/>

### Docker Desktopのインストール

次に、コンテナを使った仮想環境を作成するためのソフトウェアであるDocker Desktopをインストールします。

[Install Docker Desktop on Windows](https://hub.docker.com/editions/community/docker-ce-desktop-windows)からDocker Desktopをダウンロードします。

<img src="./assets/images/win-docker-download.png" width="800px"/>

ダウンロードしたexeファイルをダブルクリックしてインストールを開始します。インストールが完了したら、Docker Desktopを起動します。Docker Desktopを初めて起動するとき、サービス契約に同意するかどうか（→同意する）、設定を選択するかどうか（→推奨設定を使用する）を求められます。

これらが完了すると、画面右下のタスクトレイにDocker Desktopのアイコンが表示されます。Docker Desktopが起動したら、Docker Desktop Dashboardウィンドウを閉じて構いません。

### Monadic Chatのダウンロードとビルド

Ubuntuのターミナルを再度開き、Monadic Chatのソースコードをコピーしたい場所に移動します。ホームディレクトリを使う場合は、以下のコマンドを実行してホームディレクトリに移動してください。

```shell
$ cd ~
```

Now let us clone the Monadic Chat source code package in the home directory. The following command will download the source code from Github and copy it to the `~/monadic-chat` directory.

ここにMonadic Chatのソースコードをダウンロードします。以下のコマンドを実行すると、Githubからソースコードがダウンロードされ、すべての必要なファイルが`~/monadic-chat`ディレクトリの中にコピーされます。

```shell
$ git clone https://github.com/yohasebe/monadic-chat.git
```

Then move inside this directory and execute the `start` command as below:

このディレクトリの中に移動して、以下のように`start`コマンドを実行してください。

```shell
$ cd ~/monadic-chat
$ ./monadic.sh start
```

The first time you run the `start` command, it may take some time for the build process to finish, but from the second time on, the app will start immediately.

`start`コマンドを実行するのが初めての場合、ビルドに若干の時間がかかります。いったんビルドが完了すると、2回目以降はアプリがすぐに起動します。

<img src="./assets/images/win-build-source.png" width="800px"/>

ビルドが成功して、Monadic Chatが起動すると、以下のようなメッセージが表示されます。

```text
✔️ Container monadic-chat-db-1  Started
✔️ Container monadic-chat-web-1 Started
```

このメッセージが表示されたら、ブラウザで`http://localhost:4567`にアクセスしてMonadic Chatにアクセスできます。

<img src="./assets/images/win-browser.png" width="800px"/>

### Monadic Chatの起動/停止/再起動

Monadic Chatを起動/停止/再起動するには、以下のコマンドを実行します。

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

### Monadic Chatのアップデート

Monadic Chatを最新版に更新するには、以下のコマンドを実行します。


**`update`**

```shell
$ cd ~/monadic-chat
$ ./monadic.sh update
```

これにより、Githubから最新のソースコードがダウンロードされ、Monadic Chatが再ビルドされます。


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
