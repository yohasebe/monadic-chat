# インストール

## 基本的な手順

<!-- tabs:start -->

### **macOS**

macOSの場合、以下の手順でMonadic Chatをインストールします。

1. Docker Desktop for Macをインストールします。
2. Monadic Chatのインストーラーをダウンロードしてインストールします：

- 📦 [macOS ARM64 (Apple Silicon) 用インストーラー](https://github.com/yohasebe/monadic-chat/releases/download/v0.9.982/Monadic.Chat-0.9.982-arm64.dmg)
- 📦 [macOS x64 (Intel) 用インストーラー](https://github.com/yohasebe/monadic-chat/releases/download/v0.9.982/Monadic.Chat-0.9.982-x64.dmg)


### **Windows**

Windowsの場合、以下の手順でMonadic Chatをインストールします。

1. WSL2をインストールします。
2. Docker Desktop for Windowsをインストールします。
3. Monadic Chatのインストーラーをダウンロードしてインストールします：

- 📦 [Windows用インストーラー](https://github.com/yohasebe/monadic-chat/releases/download/v0.9.982/Monadic.Chat.Setup.0.9.982.exe)


### **Linux**

Linux（Ubuntu/Debian）の場合、以下の手順でMonadic Chatをインストールします。

1. Docker Desktop for Linuxをインストールします。

参照：[Install Docker Desktop on Linux](https://docs.docker.jp/desktop/install/linux-install.html)

2. Monadic Chatのインストーラーをダウンロードします：

- 📦 [Linux (Ubuntu/Debian) x64用インストーラー](https://github.com/yohasebe/monadic-chat/releases/download/v0.9.982/monadic-chat_0.9.982_amd64.deb)
- 📦 [Linux (Ubuntu/Debian) arm64用インストーラー](https://github.com/yohasebe/monadic-chat/releases/download/v0.9.982/monadic-chat_0.9.982_arm64.deb)


3. ターミナルで以下のコマンドを実行してダウンロードしたパッケージをインストールします：

```shell
$ sudo apt install ./monadic-chat-*.deb
```

<!-- tabs:end -->

## 準備

<!-- tabs:start -->

### **macOS**

macOSの場合、Docker Desktopをインストールするために以下の手順に従ってください。

まず、Docker Desktopをインストールします。Docker Desktopはコンテナを使用して仮想環境を作成するソフトウェアです。

MacのCPUによって異なるパッケージを使用します。CPUの種類は、ターミナルで以下のコマンドで確認できます。

```shell
$ sysctl -n machdep.cpu.brand_string
```

[Install Docker Desktop on Mac](https://hub.docker.com/editions/community/docker-ce-desktop-mac)からDocker Desktopをダウンロードしてインストールします。Intelの場合は`Docker Desktop Installer.dmg`を、Apple Siliconの場合は`Docker Desktop Installer Apple Silicon.dmg`をダウンロードします。

![](../assets/images/mac-docker-download.png ':size=800')

ダウンロードしたdmgファイルをダブルクリックしてウィンドウを表示し、Dockerアイコンをアプリケーションフォルダにドラッグします。インストールが完了したら、Docker Desktopを起動します。サービス契約に同意するかどうか（同意する）、推奨設定を使用するかどうか（特別な好みがない限り、推奨設定を使用する）、osascriptの内部使用のためにMacのユーザー名とパスワードを入力するよう求められます。

Docker Desktopが起動すると、タスクバーにDockerアイコンが表示されます。この時点でDocker Desktopのダッシュボードウィンドウを閉じることができます。

### **Windows**

Windows 11でMonadic Chatを使用するには、Windows Subsystem for Linux 2（WSL2）とDocker Desktopをインストールする必要があります。以下はWindows 11 HomeにMonadic Chatをインストールする方法です。同じ方法をWindows 11 ProやWindows 11 Educationでも使用できます。

#### WSL2のインストール

まず、[WSL2](https://brew.sh)をインストールします。これはWindows上でLinux環境を実現するメカニズムです。

管理者モードでPowerShellを開きます。Windowsの検索ボックスでPowerShellを検索し、「管理者として実行する」を選択してpowershell.exeを起動します。

![](../assets/images/win-powershell.png ':size=800')

次に、PowerShellで以下のコマンドを実行します（先頭の`>`はコマンドラインプロンプトを表します）。

```shell
> wsl --install -d Ubuntu 
```

![](../assets/images/win-wsl-install.png ':size=800')

その後、コンピュータを再起動します。再起動後、WSL2とUbuntuがインストールされます。このプロセスでは、Linux環境のユーザー名とパスワードを入力するよう求められます。任意のユーザー名とパスワードを入力してください。このユーザー名とパスワードは後で使用するために覚えておく必要があります。

これでWSL2のインストールは完了です。UbuntuがWindowsで利用可能になりました。Windowsの検索ボックスで「Ubuntu」を検索し、Ubuntuターミナルを開きます。

![](../assets/images/win-ubuntu.png ':size=800')

#### Docker Desktopのインストール

次に、コンテナを使用して仮想環境を作成するソフトウェアであるDocker Desktopをインストールします。

[Install Docker Desktop on Windows](https://hub.docker.com/editions/community/docker-ce-desktop-windows)からDocker Desktopをダウンロードします。

![](../assets/images/win-docker-download.png ':size=800')

ダウンロードしたexeファイルをダブルクリックしてインストールを開始します。インストールが完了したら、Docker Desktopを起動します。Docker Desktopを初めて起動すると、サービス契約に同意する（同意する）かどうかと、設定を選択する（推奨設定を使用する）かどうかを尋ねられます。

これらが完了すると、Docker Desktopアイコンが画面右下のタスクトレイに表示されます。Docker Desktopが起動すると、Docker Desktopダッシュボードウィンドウを閉じることができます。

### **Linux**

Linux（Ubuntu/Debian）の場合、Docker Desktopをインストールするには以下のページを参照してください。

- [For Debian](https://docs.docker.jp/desktop/install/debian.html)
- [For Ubuntu](https://docs.docker.jp/desktop/install/ubuntu.html)

<!-- tabs:end -->

## サーバーモードの設定

デフォルトでは、Monadic Chatは単一のマシン上ですべてのコンポーネントを実行するスタンドアロンモードで動作します。サーバーモードを有効にするには：

1. アプリケーションの歯車アイコンをクリックして設定パネルを開きます
2. 「サーバーモード」を選択します
3. 「保存」をクリックして変更を適用します
4. アプリケーションを再起動します

サーバーモードでは：
- サーバーがすべてのDockerコンテナとWebサービスをホストします
- 複数のクライアントがWebブラウザを介してサーバーに接続できます
- ネットワークURL（Jupyterノートブックなど）はサーバーの外部IPアドレスを使用します
- クライアントはサーバー上でホストされているリソースにアクセスできます

詳細については[サーバーモードとスタンドアロンモード](../docker-integration/basic-architecture.md#サーバーモードとスタンドアロンモード)のドキュメントを参照してください。

## 更新

![](../assets/images/monadic-chat-menu.png ':size=240')

Monadic Chatは起動時に自動的に更新をチェックします。新しいバージョンが利用可能な場合、メインコンソールウィンドウに通知が表示されます。

更新プロセスは以下の手順に従います：

1. アプリケーションが起動すると、バックグラウンドで自動的に更新をチェックします
2. 更新が利用可能な場合、メインコンソールウィンドウにメッセージが表示されます
3. 更新をダウンロードするには、`File`→`Check for Updates`に移動します
4. バージョン情報を表示するダイアログが表示され、以下のオプションが表示されます：
   - **Download Now**：お使いのプラットフォーム用のアップデートファイルを直接ダウンロード
   - **View All Releases**：GitHubのリリースページを開く
   - **Cancel**：ダイアログを閉じる
5. 「Download Now」を選択すると、ブラウザが自動的にあなたのシステムに適したインストーラーのダウンロードを開始します
6. ダウンロードが完了したら、Monadic Chatを終了し、新しいインストーラーを実行します
7. 新しいバージョンが既存のインストールを置き換えます

システムは自動的にプラットフォーム（macOS、Windows、Linux）とアーキテクチャ（ARM64またはx64）を検出し、適切なダウンロードリンクを提供します。

[GitHub Releasesページ](https://github.com/yohasebe/monadic-chat/releases/latest)から手動で最新バージョンをダウンロードすることもできます。