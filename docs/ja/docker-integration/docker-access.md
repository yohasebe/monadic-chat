# Dockerコンテナへのアクセス

Dockerコンテナにアクセスする方法は2つあります。

## Dockerコマンド

Dockerコンテナにアクセスするためには、`docker exec`コマンドを使用します。以下のコンテナが利用可能です：

Monadic Chatを起動すると、各コンテナの利用可能性がメインウィンドウのコンソールに表示されます。

### 利用可能なコンテナ

この一覧はほとんどの環境に共通するコンテナを示しています。全コンテナと各コンテナの役割については[基本アーキテクチャ](basic-architecture.md#standard-containers)を参照してください。

- **Rubyコンテナ** (`monadic-chat-ruby-container`): メインアプリケーションコンテナ
  ```shell
  docker exec -it monadic-chat-ruby-container bash
  ```

- **Pythonコンテナ** (`monadic-chat-python-container`): コード実行とデータ分析
  ```shell
  docker exec -it monadic-chat-python-container bash
  ```

- **Qdrantコンテナ** (`monadic-chat-qdrant-container`): RAG（PDF + ヘルプ）用ベクトルデータベース
  ```shell
  docker exec -it monadic-chat-qdrant-container sh
  ```

- **Embeddingsコンテナ** (`monadic-chat-embeddings-container`): RAG クエリ用のローカル `multilingual-e5-base` 推論
  ```shell
  docker exec -it monadic-chat-embeddings-container bash
  ```

- **Seleniumコンテナ** (`monadic-chat-selenium-container`): Webスクレイピングとブラウザ自動化
  ```shell
  docker exec -it monadic-chat-selenium-container bash
  ```

- **Privacyコンテナ** (`monadic-chat-privacy-container`): Privacy Filter 用のローカル個人情報マスキング（デフォルトで起動）
  ```shell
  docker exec -it monadic-chat-privacy-container bash
  ```

- **Extractorコンテナ** (`monadic-chat-extractor-container`): Knowledge Base Quality Pack のドキュメント抽出（オプトイン。インストールオプションで導入した場合のみ存在）
  ```shell
  docker exec -it monadic-chat-extractor-container bash
  ```

?> **開発のヒント**: ローカルで開発する際、Rubyコンテナを停止してホストマシンでアプリケーションを実行しながら、他のコンテナは稼働させ続けることができます。

## JupyterLab

`Actions/Start JupyterLab`メニューを使用すると、Pythonコンテナ上の`/monadic/data`をカレントディレクトリとしてJupyterLabが起動します。JupyterLabのLauncher画面で`Terminal`をクリックすると、Pythonコンテナにアクセスできます。詳細は[JupyterLabとの連携](jupyterlab.md)を参照してください。

## 一般的な使用例

### Pythonコンテナ
- 追加のPythonパッケージをインストール: `uv pip install --no-cache package_name`（永続的なインストール方法は[Pythonコンテナ](python-container.md)を参照）
- 共有データにアクセス: `cd /monadic/data`
- Pythonスクリプトを実行: `python /monadic/data/scripts/my_script.py`

### Qdrantコンテナ
- コレクション一覧: `curl http://localhost:6333/collections`（dev モード時、ホストから）
- コレクション詳細: `curl http://localhost:6333/collections/help_docs`
- 内蔵 Web UI（dev モードのみ）: `http://localhost:6333/dashboard`

### Embeddingsコンテナ
- ヘルスチェック: `curl http://localhost:8002/v1/health`（dev モード時、ホストから）
- モデル情報: `curl http://localhost:8002/v1/info`

### Rubyコンテナ
- Ruby gemsを確認: `bundle list`
- ログを表示: `tail -f /monadic/log/server.log`
- 設定にアクセス: `cd /monadic/config`

## 関連ドキュメント
- [基本アーキテクチャ](basic-architecture.md) - すべてのコンテナの概要
- [Pythonコンテナ](python-container.md) - Pythonコンテナの詳細ドキュメント
