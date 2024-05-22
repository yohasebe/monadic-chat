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

## 基本的な手順

### MacOS

1. Docker Desktop for Macをインストールします（[詳細](#install-docker-macos)）。
2. Monadic Chat のインストーラーをダウンロードしてインストールします。

- [📦 Installer package for MacOS ARM64 (Apple Silicon)](https://yohasebe.com/assets/apps/monadic-chat-0.5.0-arm64.dmg) (0.5.0)
- [📦 Installer package for MacOS x64 (Intel)](https://yohasebe.com/assets/apps/monadic-chat-0.5.0.dmg) (0.5.0)

### Windows

1. WSL2をインストールします（[詳細](#install-wsl2-win)）。
2. Docker Desktop for Windowsをインストールします（[詳細](#install-docker-win)）。
3. Monadic Chat のインストーラーをダウンロードしてインストールします。

- [📦 Installer package for Windows](https://yohasebe.com/assets/apps/monadic-chat%20Setup%200.5.0.exe) (0.5.0)

## 依存ソフトウェアのインストール

### MacOS

<b id="install-docker-macos">Docker Desktopのインストール</b>

次にDocker Desktopをインストールします。Docker Desktopはコンテナ型の仮想環境を作成するためのソフトウェアです。

ご自身のMacのCPUに応じて異なるパッケージを用います。CPUの種類はターミナル上で以下のコマンドで確認できます。

```shell
$ sysctl -n machdep.cpu.brand_string
```

[Install Docker Desktop on Mac](https://hub.docker.com/editions/community/docker-ce-desktop-mac)からDocker Desktopをダウンロードしてインストールしますが、その際、Intelの場合は`Docker Desktop Installer.dmg`を、Apple Siliconの場合は`Docker Desktop Installer Apple Silicon.dmg`をダウンロードしてください。

<img src="./assets/images/mac-docker-download.png" width="800px"/>

ダウンロードしたdmgファイルをダブルクリックするとウィンドウが表示されるので、DockerのアイコンをApplicationsフォルダーにドラッグしてください。インストールが完了したら、Docker Desktopを起動しましょう。その際、service agreementへの同意が求められます（acceptしてください）。また、推奨設定を使用するかどうかを確認されます（特にこだわりがなければ推奨設定を用いてください）。また、内部でosascriptを使用するため、Macのユーザ名とパスワードの入力が求められます。

Docker Desktopの起動が完了すると、メニューバーにDockerのアイコンが表示されます。ここでDocker Desktopのダッシュボード・ウィンドウは閉じてしまって構いません。

### Windows

以下ではWindows 11 HomeにMonadic Chatをインストールする方法を説明します。Windows 11 ProやWindows 11 Educationの場合でも基本的に同様の方法でインストール可能です。

<b id="install-wsl2-win">WSL2のインストール</b>

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

<b id="install-docker-win">Docker Desktopのインストール</b>

次に、コンテナを使った仮想環境を作成するためのソフトウェアであるDocker Desktopをインストールします。

[Install Docker Desktop on Windows](https://hub.docker.com/editions/community/docker-ce-desktop-windows)からDocker Desktopをダウンロードします。

<img src="./assets/images/win-docker-download.png" width="800px"/>

ダウンロードしたexeファイルをダブルクリックしてインストールを開始します。インストールが完了したら、Docker Desktopを起動します。Docker Desktopを初めて起動するとき、サービス契約に同意するかどうか（→同意する）、設定を選択するかどうか（→推奨設定を使用する）を求められます。

これらが完了すると、画面右下のタスクトレイにDocker Desktopのアイコンが表示されます。Docker Desktopが起動したら、Docker Desktop Dashboardウィンドウを閉じて構いません。

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
