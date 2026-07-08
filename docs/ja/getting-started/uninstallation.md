# アンインストール

## 基本的な手順 :id=basic-steps

Monadic Chatをアンインストールする基本的な手順は以下の通りです。

- Monadic Chatの終了
- Dockerコンテナとイメージの削除
- Monadic Chatのアンインストール

<!-- tabs:start -->

### **macOS**

1. メニューの`Remove Images/Containers/Data`を実行します。これにより、下に示すDockerコンテナ、イメージ、および保存データ（PDFベクトル埋め込みを含む）が削除されます。
2. Monadic Chatを終了します。
3. Finderで`Applications`フォルダーを開き、Monadic Chatをゴミ箱にドラッグします。

### **Windows**

1. メニューの`Remove Images/Containers/Data`を実行します。これにより、下に示すDockerコンテナ、イメージ、および保存データ（PDFベクトル埋め込みを含む）が削除されます。
2. Monadic Chatを終了します。
3. `プログラムの追加と削除`からMonadic Chatをアンインストールします。

### **Linux**

1. メニューの`Remove Images/Containers/Data`を実行します。これにより、下に示すDockerコンテナ、イメージ、および保存データ（PDFベクトル埋め込みを含む）が削除されます。
2. Monadic Chatを終了します。
3. ターミナルで以下のコマンドを実行します。

```shell
$ sudo apt remove monadic-chat
```

<!-- tabs:end -->

<!-- SCREENSHOT: Monadic Chatメニュー - File、View、Actions、Helpの各メニュー項目が表示され、Actionsメニューに「Remove Images/Containers/Data」オプションがある様子 -->

## ユーザーデータ :id=user-data

アンインストール後も、個人データと設定は以下のディレクトリに残ります：
- `~/monadic/` (macOS/Linux) または `%USERPROFILE%\monadic\` (Windows)

これには設定ファイル、チャットログ、生成されたデータが含まれます。Monadic Chatの痕跡を完全に削除したい場合は、このディレクトリを手動で削除してください。

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
- `monadic-chat-privacy-container`（Privacy Filter をインストールしている場合のみ）
- `monadic-chat-extractor-container`（Knowledge Base Quality Pack をインストールしている場合のみ）
- `monadic-chat-pgvector-container`（1.0.0-beta.14 以前からアップグレードした場合のみ存在）
- `monadic-chat-web-container` (レガシー)
- `monadic-chat-container` (レガシー)

#### イメージ

- `yohasebe/monadic-chat`
- `yohasebe/python`
- `ghcr.io/yohasebe/monadic-embeddings`
- `ghcr.io/yohasebe/monadic-qdrant`
- `ghcr.io/yohasebe/monadic-selenium`
- `ghcr.io/yohasebe/monadic-privacy`（Privacy Filter インストール時のみ）
- `ghcr.io/yohasebe/monadic-extractor`（Knowledge Base Quality Pack インストール時のみ）
- `ghcr.io/yohasebe/monadic-python`（プリビルトのデフォルト Python イメージ。インストールオプション未選択時、またはビルドキャッシュとして存在）
- `yohasebe/selenium`、`qdrant/qdrant`（ghcr.io 統一以前のバージョンのイメージ）
- `yohasebe/monadic-embeddings`、`yohasebe/monadic-privacy`、`yohasebe/monadic-extractor`（ghcr.io プリビルト配布以前のバージョンでローカルビルドされたイメージ）
- `yohasebe/pgvector`（1.0.0-beta.14 以前からアップグレードした場合のみ存在）

#### ボリューム

- `monadic-chat-qdrant-data`
- `monadic-chat-embeddings-models`
- `monadic-chat-pgvector-data`（1.0.0-beta.14 以前からアップグレードした場合のみ存在）

### 手動削除コマンド :id=manual-removal-commands

Dockerリソースを手動で削除するには、以下のコマンドを使用します：

```bash
# コンテナの削除
docker rm -f monadic-chat-ruby-container
docker rm -f monadic-chat-python-container
# ... (他のコンテナも同様に)

# イメージの削除
docker rmi -f yohasebe/monadic-chat
docker rmi -f yohasebe/python
# ... (他のイメージも同様に)

# ボリュームの削除
docker volume rm monadic-chat-qdrant-data
docker volume rm monadic-chat-embeddings-models
# レガシーボリューム（旧バージョンからアップグレードした環境のみ存在）
docker volume rm monadic-chat-pgvector-data 2>/dev/null || true
```

**注意**: Linuxで権限エラーが発生する場合は、コマンドの前に`sudo`を付けてください。コンテナが実行中で削除できない場合は、先に`docker stop <コンテナ名>`で停止してください。
