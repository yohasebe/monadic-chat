# インストール

## システム要件 :id=system-requirements

- **Docker**: Docker Desktop（新しい版）、または Linux では Docker Engine
- **メモリ**: 最低8GB RAM（16GB推奨）
- **ストレージ**: Dockerイメージとユーザーデータ用の十分な空き容量
- **macOS**: Apple Silicon（M1以降）上の macOS 13（Ventura）以降が必要です。Intel Macはサポートされていません。

## 基本的な手順 :id=basic-steps

<!-- tabs:start -->

### **macOS**

> **注意**: macOSはApple Silicon（M1以降）上の macOS 13（Ventura）以降が必要です。Intel Macはサポートされていません。

1. **Docker Desktop for Macのインストール**

[Docker Desktop](https://docs.docker.com/desktop/)からダウンロード：
- `Docker Desktop Installer Apple Silicon.dmg` をダウンロード

Dockerアイコンをアプリケーションフォルダにドラッグして起動。サービス契約に同意し、推奨設定を使用してください。

2. **Monadic Chatのダウンロードとインストール**

📦 [Monadic Chat 1.0.0-beta.43 をダウンロード（macOS）](https://github.com/yohasebe/monadic-chat/releases/download/v1.0.0-beta.43/Monadic.Chat-1.0.0-beta.43-arm64.dmg)

### **Windows**

1. **WSL2のインストール**

PowerShellを管理者として開き、以下を実行：
```shell
> wsl --install -d Ubuntu
```

<!-- SCREENSHOT: PowerShellでのWSLインストール画面 - wsl --install -d Ubuntuコマンドの実行中とインストール進行状況が表示されている様子 -->

コンピューターを再起動。プロンプトが表示されたらUbuntuのユーザー名とパスワードを設定してください。

2. **Docker Desktopのインストール**

[Docker Desktop](https://docs.docker.com/desktop/)からダウンロードしてインストール。

<!-- SCREENSHOT: Docker Desktopダウンロードページ - Windows用のDocker Desktop Installer.exeのダウンロードボタンが表示されている様子 -->

サービス契約に同意し、推奨設定を使用してください。

3. **Monadic Chatのダウンロードとインストール**

📦 [Monadic Chat 1.0.0-beta.43 をダウンロード（Windows）](https://github.com/yohasebe/monadic-chat/releases/download/v1.0.0-beta.43/Monadic.Chat.Setup.1.0.0-beta.43.exe)

### **Linux**

1. **Dockerのインストール**

Docker Desktop for Linux か Docker Engine のどちらかをインストールします：
- Docker Desktop：[Debian用](https://docs.docker.com/desktop/setup/install/linux/debian/)、[Ubuntu用](https://docs.docker.com/desktop/setup/install/linux/ubuntu/)
- Docker Engine：[インストールガイド](https://docs.docker.com/engine/install/)

Docker Engine を使う場合は、`sudo` なしで `docker` を実行できる必要があります。ユーザーを `docker` グループに追加し、ログインし直してください：

```shell
$ sudo usermod -aG docker $USER
```

Omarchy では、代わりに `omarchy-setup-security-sudoless-docker` を実行します。`docker` グループに入ると、そのコンピューターに対して root 相当の権限を持つことになります。ユーザーが Docker を使えないとき、Monadic Chat はこのコマンドを表示します。

2. **Monadic Chatのダウンロード**

📦 [Monadic Chat 1.0.0-beta.43 をダウンロード（Linux x86_64）](https://github.com/yohasebe/monadic-chat/releases/download/v1.0.0-beta.43/monadic-chat_1.0.0-beta.43_x86_64.AppImage) — [arm64](https://github.com/yohasebe/monadic-chat/releases/download/v1.0.0-beta.43/monadic-chat_1.0.0-beta.43_arm64.AppImage)

3. **実行権限を付けて起動**

AppImage はインストール不要です。実行権限を付けて起動してください：

```shell
$ chmod +x monadic-chat_*.AppImage
$ ./monadic-chat_*.AppImage
```

AppImage は FUSE を使って自身をマウントします。現在のディストリビューションに入っている FUSE 3 で足り、`libfuse2` は不要です。FUSE が使えない環境では、`--appimage-extract-and-run` を付けて起動してください。

<!-- tabs:end -->

## 初期設定 :id=initial-setup

インストール後：

1. コンソールの **Settings** をクリックし、**API Keys** を開いて、使う AI サービスの API キーを入力し、**Save** をクリックします
2. **Start** をクリックします。初回は、ビルド済みのイメージをダウンロードし、Ruby と Python のイメージをビルドするため、インターネット接続とコンピューターによって 10〜30 分ほどかかります。2 回目からは、それらを再利用します
3. 準備が整うと、コンソールの **System** の欄に緑で **Started** と表示され、**Open Browser** が使えるようになります

詳細な使用方法については、[Webインターフェース](../basic-usage/web-interface.md)セクションを参照してください。

## Monadic Chatの更新 :id=update

<!-- SCREENSHOT: Monadic Chatメニュー - FileメニューにCheck for Updatesがある様子 -->

Monadic Chat は、起動時（オンラインのとき）に更新を確認します。

1. 新しい版があると、コンソールに **Download & Install** ボタンが表示されます。自分で確認するときは、File メニュー（macOS では Monadic Chat メニュー）の **Check for Updates** を選びます
2. **Download & Install** をクリックすると、更新がバックグラウンドでダウンロードされ、進捗がコンソールに表示されます
3. ダウンロードが終わったら、**Restart Now** でインストールするか、**Later** を選びます

[1.0.0-beta.43 のリリースページ](https://github.com/yohasebe/monadic-chat/releases/tag/v1.0.0-beta.43)から手動でダウンロードすることも、[すべてのリリース](https://github.com/yohasebe/monadic-chat/releases)を見ることもできます。

## 高度な設定 :id=advanced-configuration

以下を含む高度な設定オプション：
- Install Options（LaTeX、Pythonライブラリなど）
- 再ビルド手順
- 環境変数

詳細は[高度な設定](../advanced-topics/advanced-configuration.md)を参照してください。

## トラブルシューティング :id=troubleshooting

問題が発生した場合は、以下のFAQセクションを参照してください：
- [セットアップと設定FAQ](../faq/faq-settings.md)
- [基本アプリケーションFAQ](../faq/faq-basic-apps.md)
- [ユーザーインターフェースFAQ](../faq/faq-user-interface.md)
