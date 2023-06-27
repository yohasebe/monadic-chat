---
title: Monadic Chat
layout: default
---

# ドキュメンテーション

[English](https://yohasebe.github.io/monadic-chat-web/documentation) |
[日本語](https://yohasebe.github.io/monadic-chat-web/documentation_ja)

### インストール (MacOS）

#### Homebrew

まずは[Homebrew](https://brew.sh/index_ja)をインストールします。HomebrewはMacOSのパッケージ管理システムです。

ターミナルを開いてください。Macのターミナルの場所は、`Application -> ユーティリティー -> ターミナル.app`です。ターミナルを開いたら、以下のコマンドを実行してください（最初の`$`はコマンドラインのプロンプトを表しています）。

```shell
$ /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" 
```

#### Git

次にgitコマンドを使えるようにしましょう。gitはソースコードのバージョン管理システムです。

```shell
$ brew install git
```

#### Docker Desktop

次にDocker Desktopをインストールします。Docker Desktopはコンテナ型の仮想環境を作成するためのソフトウェアです。


ご自身のMacのCPUに応じて異なるパッケージを用います。CPUの種類はターミナル上で以下のコマンドで確認できます。

```shell
$ sysctl -n machdep.cpu.brand_string
```

[Install Docker Desktop on Mac](https://hub.docker.com/editions/community/docker-ce-desktop-mac)からDocker Desktopをダウンロードしてインストールしますが、その際、Intelの場合は`Docker Desktop Installer.dmg`を、Apple Siliconの場合は`Docker Desktop Installer Apple Silicon.dmg`をダウンロードしてください。

ダウンロードしたdmgファイルをダブルクリックするとインストールが始まります。インストールが完了したら、Docker Desktopを起動してください。Docker Desktopを起動すると、メニューバーにDockerのアイコンが表示されます。

#### Monadic Chat ソースコードのダウンロード

ターミナルを開いて、Monadic Chatのソースコードをコピーする場所に移動します。ここでは、ホームディレクトリににソースコードをコピーすることにします。通常はターミナルを開くとそこがホームディレクトリですが、念のため次のコマンドでホームディレクトリに移動しましょう。

```shell
$ cd ~
```

ここで以下のコマンドを実行すると、ホームディレクトリに`monadic-chat`というディレクトリが作成され、その中にソースコードがダウンロードされます。

```shell
$ git clone https://github.com/yohasebe/monadic-chat.git
```

#### Monadic Chatのビルド

先ほどダウンロードしたソースコードのディレクトリに移動しましょう。

```shell
$ cd ~/monadic-chat
```

ここで以下のコマンドを実行すると、Monadic Chatのビルドと起動が行われます。

```shell
$ ./docker/monadic.sh start
```

初回はビルドに時間がかかりますが、2回目以降はすぐに起動できます。

#### Monadic Chatの起動

ビルドが済んでいる場合は、以下のコマンドでMonadic Chatを起動できます。Docker Desktopが起動していない場合は、このコマンドにより自動で起動します。

```shell
$ cd ~/monadic-chat
$ ./docker/monadic.sh start
```

MacではMonadic Chatの起動が完了すると、システムのデフォルト・ブラウザ上でホーム画面が開きます。もし、画面が開かない場合は、ブラウザで`http://localhost:4567`を開いてください（または再読み込みしてください）。

#### Monadic Chatの停止

Monadic Chatを停止するには、以下のコマンドを実行します。

```shell
$ cd ~/monadic-chat
$ ./docker/monadic.sh stop
```

#### Monadic Chatのアップデート

Monadic Chatのアップデートは、以下のコマンドを実行します。

```shell
$ cd ~/monadic-chat
$ ./docker/monadic.sh update
```

上記のコマンドにより、Githubから最新のソースコードがダウンロードされ、Monadic Chatが再ビルドされます。

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
