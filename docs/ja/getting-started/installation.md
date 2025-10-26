# インストール

## システム要件 :id=system-requirements

- **Docker Desktop**: 最新版を推奨
- **メモリ**: 最低8GB RAM（16GB推奨）
- **ストレージ**: Dockerイメージとユーザーデータ用の十分な空き容量

## 基本的な手順 :id=basic-steps

<!-- tabs:start -->

### **macOS**

1. **Docker Desktop for Macのインストール**

CPUタイプを確認：
```shell
$ sysctl -n machdep.cpu.brand_string
```

[Docker Desktop](https://docs.docker.com/desktop/)からダウンロード：
- Intel Mac: `Docker Desktop Installer.dmg`
- Apple Silicon: `Docker Desktop Installer Apple Silicon.dmg`

![](../assets/images/mac-docker-download.png ':size=800')

Dockerアイコンをアプリケーションフォルダにドラッグして起動。サービス契約に同意し、推奨設定を使用してください。

2. **Monadic Chatのダウンロードとインストール**

📦 [macOS用の最新リリースをダウンロード](https://github.com/yohasebe/monadic-chat/releases/latest)

### **Windows**

1. **WSL2のインストール**

PowerShellを管理者として開き、以下を実行：
```shell
> wsl --install -d Ubuntu
```

![](../assets/images/win-wsl-install.png ':size=800')

コンピューターを再起動。プロンプトが表示されたらUbuntuのユーザー名とパスワードを設定してください。

2. **Docker Desktopのインストール**

[Docker Desktop](https://docs.docker.com/desktop/)からダウンロードしてインストール。

![](../assets/images/win-docker-download.png ':size=800')

サービス契約に同意し、推奨設定を使用してください。

3. **Monadic Chatのダウンロードとインストール**

📦 [Windows用の最新リリースをダウンロード](https://github.com/yohasebe/monadic-chat/releases/latest)

### **Linux**

1. **Docker Desktop for Linuxのインストール**

Dockerドキュメントを参照：
- [Debian用](https://docs.docker.jp/desktop/install/debian.html)
- [Ubuntu用](https://docs.docker.jp/desktop/install/ubuntu.html)

2. **Monadic Chatのダウンロード**

📦 [Linux用の最新リリースをダウンロード](https://github.com/yohasebe/monadic-chat/releases/latest)

3. **パッケージのインストール**

```shell
$ sudo apt install ./monadic-chat-*.deb
```

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

![](../assets/images/monadic-chat-menu.png ':size=240')

Monadic Chatは起動時に自動的に更新をチェックします。

**更新手順:**

1. 更新がある場合、メインコンソールに通知が表示されます
2. `ファイル` → `アップデートを確認`を選択
3. 「今すぐダウンロード」を選択してプラットフォーム用のインストーラーを取得
4. Monadic Chatを終了し、新しいインストーラーを実行
5. 新しいバージョンが既存のインストールを置き換えます

[GitHubリリースページ](https://github.com/yohasebe/monadic-chat/releases/latest)から手動でダウンロードすることもできます。

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
