# アンインストール

## 基本的な手順 :id=basic-steps

Monadic Chatをアンインストールする基本的な手順は以下の通りです。

- メニューから Monadic Chat の Docker コンテナとイメージを削除
- Monadic Chatの終了
- Monadic Chatのアンインストール

<!-- tabs:start -->

### **macOS**

1. File メニュー（macOS では Monadic Chat メニュー）の `Remove Images/Containers/Data` を選びます。下に示す Monadic Chat の Docker コンテナ、イメージ、ボリューム（Knowledge Base のデータ）が削除されます。`~/monadic` のファイルは残ります。
2. Monadic Chatを終了します。
3. Finderで`Applications`フォルダーを開き、Monadic Chatをゴミ箱にドラッグします。

### **Windows**

1. File メニューの `Remove Images/Containers/Data` を選びます。下に示す Monadic Chat の Docker コンテナ、イメージ、ボリューム（Knowledge Base のデータ）が削除されます。`~/monadic` のファイルは残ります。
2. Monadic Chatを終了します。
3. Windows の設定の［アプリ］から Monadic Chat をアンインストールします。

### **Linux**

1. File メニューの `Remove Images/Containers/Data` を選びます。下に示す Monadic Chat の Docker コンテナ、イメージ、ボリューム（Knowledge Base のデータ）が削除されます。`~/monadic` のファイルは残ります。
2. Monadic Chatを終了します。
3. ダウンロードした AppImage ファイルを削除します。

Monadic Chat の Linux 版は AppImage で配布されており、システムにインストールされないため、削除すべきパッケージはありません：

```shell
$ rm monadic-chat_*.AppImage
```

デスクトップ環境が AppImage をアプリケーションメニューに統合していた場合は、作成されたエントリ（通常は `~/.local/share/applications/` 配下）も削除してください。

<!-- tabs:end -->

<!-- SCREENSHOT: Monadic Chatメニュー - FileメニューにRemove Images/Containers/Dataがある様子 -->

## ユーザーデータ :id=user-data

アンインストール後も、データと設定は次の2箇所に残ります：

- `~/monadic/`：設定ファイル、共有フォルダ、ログ。Windows では、このフォルダは Windows 側ではなく WSL の Linux（Ubuntu）のホームフォルダにあります
- アプリ自身の保存領域（Cookie、キャッシュ、ウィンドウ状態）:
  - macOS: `~/Library/Application Support/Monadic Chat`
  - Linux: `~/.config/Monadic Chat`
  - Windows: `%APPDATA%\Monadic Chat`

Monadic Chat のデータと設定を削除するには、両方のフォルダを削除してください。

## クリーンアップ（任意） :id=cleanup

万が一`Remove Images/Containers/Data`を実行してもコンテナ、イメージ、データが削除されなかったり、アップデート時またはアンインストール時に問題が生じた場合は、以下の2つの方法があります：

### 方法1: すべてのDockerデータをクリーン/パージ :id=clean-purge-docker-data

Docker Desktopのメニューから `Troubleshoot` → `Clean/Purge data`を使用して、すべてのDockerイメージとコンテナを削除できます。**警告**: これはシステム上のすべてのDockerデータを削除します（Monadic Chatだけでなく、他のアプリケーションのデータも含む）。

### 方法2: 手動削除 :id=manual-removal

または、Monadic Chat関連のDockerコンテナとイメージのみを手動で削除できます：

### Dockerコンテナとイメージ :id=docker-containers-images

#### コンテナ

- `monadic-chat-ruby-container`
- `monadic-chat-python-container`
- `monadic-chat-selenium-container`
- `monadic-chat-qdrant-container`
- `monadic-chat-embeddings-container`
- `monadic-chat-privacy-container`（`PRIVACY_FILTER=false` にしていなければ存在します）
- `monadic-chat-extractor-container`（Knowledge Base Quality Pack をインストールしている場合のみ）

#### イメージ

- `yohasebe/monadic-chat`
- `yohasebe/python`
- `ghcr.io/yohasebe/monadic-embeddings`
- `ghcr.io/yohasebe/monadic-qdrant`
- `ghcr.io/yohasebe/monadic-selenium`
- `ghcr.io/yohasebe/monadic-privacy`（`PRIVACY_FILTER=false` にしていない場合）
- `ghcr.io/yohasebe/monadic-extractor`（Knowledge Base Quality Pack インストール時のみ）
- `ghcr.io/yohasebe/monadic-python`（Python コンテナのビルドのキャッシュとしてダウンロード）

#### ボリューム

- `monadic-chat-qdrant-data`

### 手動削除コマンド :id=manual-removal-commands

Dockerリソースを手動で削除するには、以下のコマンドを使用します：

```bash
# コンテナの削除
docker rm -f monadic-chat-ruby-container
docker rm -f monadic-chat-python-container
# ... (他のコンテナも同様に)

# イメージの削除（それぞれのすべてのタグ）
docker rmi -f $(docker images -q yohasebe/monadic-chat)
docker rmi -f $(docker images -q yohasebe/python)
# ... (他のイメージも同様に)

# ボリュームの削除
docker volume rm monadic-chat-qdrant-data
```

**注意**: Linuxで権限エラーが発生する場合は、コマンドの前に`sudo`を付けてください。コンテナが実行中で削除できない場合は、先に`docker stop <コンテナ名>`で停止してください。
