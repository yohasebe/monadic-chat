# Docker コンテナへのアクセス

コンテナの中では、`docker exec` コマンドか、JupyterLab のターミナルで作業できます。

## Docker コマンド

Start の後、コンソールには動いているコンテナと、それぞれの `docker exec` コマンドが表示されます。

### 利用できるコンテナ

標準のコンテナの一覧です。それぞれの役割は[基本構成](basic-architecture.md#standard-containers)を参照してください。

- **Ruby コンテナ**（`monadic-chat-ruby-container`）：Monadic Chat のサーバー
  ```shell
  docker exec -it monadic-chat-ruby-container bash
  ```

- **Python コンテナ**（`monadic-chat-python-container`）：コードの実行とデータの分析
  ```shell
  docker exec -it monadic-chat-python-container bash
  ```

- **Qdrant コンテナ**（`monadic-chat-qdrant-container`）：ベクトルデータベース
  ```shell
  docker exec -it monadic-chat-qdrant-container bash
  ```

- **Embeddings コンテナ**（`monadic-chat-embeddings-container`）：検索のためのテキストの埋め込み
  ```shell
  docker exec -it monadic-chat-embeddings-container bash
  ```

- **Selenium コンテナ**（`monadic-chat-selenium-container`）：ブラウザーの自動操作
  ```shell
  docker exec -it monadic-chat-selenium-container bash
  ```

- **Privacy コンテナ**（`monadic-chat-privacy-container`）：Privacy Filter のための個人情報の検出
  ```shell
  docker exec -it monadic-chat-privacy-container bash
  ```

- **Extractor コンテナ**（`monadic-chat-extractor-container`）：Knowledge Base Quality Pack の文書の抽出（インストールしたときだけあります）
  ```shell
  docker exec -it monadic-chat-extractor-container bash
  ```

## JupyterLab

**Actions → Start JupyterLab** で、Python コンテナの共有フォルダ（`/monadic/data`）で JupyterLab が起動します。JupyterLab の Launcher で `Terminal` をクリックすると、コンテナのシェルが開きます。[JupyterLab との連携](jupyterlab.md)を参照してください。

## よく使う操作

### Python コンテナ
- 今のコンテナに Python のパッケージを入れる：`uv pip install --no-cache package_name`（再ビルドの後も残すには[Python コンテナ](python-container.md)を参照）
- 共有フォルダへ移る：`cd /monadic/data`
- 自分のスクリプトを実行する：`python /monadic/data/scripts/my_script.py`

### Ruby コンテナ
- インストールされている gem の一覧：`bundle list`
- サーバーのログを追う：`tail -f /monadic/log/server.log`
- 設定のフォルダへ移る：`cd /monadic/config`

## 関連ドキュメント
- [基本構成](basic-architecture.md) - すべてのコンテナの概要
- [Python コンテナ](python-container.md) - Python コンテナの詳細
