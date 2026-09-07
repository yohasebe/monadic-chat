# インストール

## システム要件 :id=system-requirements

- **Docker Desktop**: 最新版を推奨
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

📦 [Monadic Chat 1.0.0-beta.33 をダウンロード（macOS）](https://github.com/yohasebe/monadic-chat/releases/download/v1.0.0-beta.33/Monadic.Chat-1.0.0-beta.33-arm64.dmg)

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

📦 [Monadic Chat 1.0.0-beta.33 をダウンロード（Windows）](https://github.com/yohasebe/monadic-chat/releases/download/v1.0.0-beta.33/Monadic.Chat.Setup.1.0.0-beta.33.exe)

### **Linux**

1. **Docker Desktop for Linuxのインストール**

Dockerドキュメントを参照：
- [Debian用](https://docs.docker.jp/desktop/install/debian.html)
- [Ubuntu用](https://docs.docker.jp/desktop/install/ubuntu.html)

2. **Monadic Chatのダウンロード**

📦 [Monadic Chat 1.0.0-beta.33 をダウンロード（Linux x86_64）](https://github.com/yohasebe/monadic-chat/releases/download/v1.0.0-beta.33/monadic-chat_1.0.0-beta.33_x86_64.AppImage) — [arm64](https://github.com/yohasebe/monadic-chat/releases/download/v1.0.0-beta.33/monadic-chat_1.0.0-beta.33_arm64.AppImage)

3. **実行権限を付けて起動**

AppImage はインストール不要です。実行権限を付けて起動してください：

```shell
$ chmod +x monadic-chat_*.AppImage
$ ./monadic-chat_*.AppImage
```

FUSE 2 が入っていないディストリビューションでは、`sudo apt install libfuse2` で導入するか、`--appimage-extract-and-run` を付けて起動してください。

<!-- tabs:end -->

## 初期設定 :id=initial-setup

インストール後、Monadic Chatを初めて起動すると：

1. アプリケーションが自動的にDockerコンテナのビルドを開始します
2. **初回セットアップ時間**: インターネット接続とシステム性能に依存してかなりの時間がかかる場合があります
3. **以降の起動**: 既存のコンテナが再利用されるため、格段に速くなります
4. 使用したいAIサービスのAPIキーを設定で構成してください
5. 準備が完了すると、ステータスインジケータが緑色になります

詳細な使用方法については、[Webインターフェース](../basic-usage/web-interface.md)セクションを参照してください。

## Monadic Chatの更新 :id=update

<!-- SCREENSHOT: Monadic Chatメニュー - File、View、Actions、Helpの各メニュー項目が表示され、Fileメニューに「アップデートを確認」オプションがある様子 -->

Monadic Chatは起動時に自動的に更新をチェックします。

**更新手順:**

1. 更新がある場合、メインコンソールに **Download & Install** ボタン付きの通知が表示されます（`File` → `Check for Updates` から手動で確認することもできます）
2. **Download & Install** をクリックすると、更新がバックグラウンドでダウンロードされ、進捗がコンソールに表示されます
3. ダウンロードが完了すると、更新を適用するためにMonadic Chatの再起動を促すダイアログが表示されます

[1.0.0-beta.33 のリリースページ](https://github.com/yohasebe/monadic-chat/releases/tag/v1.0.0-beta.33)から手動でダウンロードすることも、[すべてのリリース](https://github.com/yohasebe/monadic-chat/releases)を見ることもできます。

## 高度な設定 :id=advanced-configuration

以下を含む高度な設定オプション：
- インストールオプション（LaTeX、Pythonライブラリなど）
- サーバーモード設定
- 再ビルド手順
- 環境変数

詳細は[高度な設定](../advanced-topics/advanced-configuration.md)を参照してください。

## トラブルシューティング :id=troubleshooting

問題が発生した場合は、以下のFAQセクションを参照してください：
- [セットアップと設定FAQ](../faq/faq-settings.md)
- [基本アプリケーションFAQ](../faq/faq-basic-apps.md)
- [ユーザーインターフェースFAQ](../faq/faq-user-interface.md)
