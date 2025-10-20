# Dockerコンテナへのアクセス

Dockerコンテナにアクセスする方法は2つあります。

## Dockerコマンド

Dockerコンテナにアクセスするためには、`docker exec`コマンドを使用します。以下のコンテナが利用可能です：

Monadic Chatを起動すると、各コンテナの利用可能性がメインウィンドウのコンソールに表示されます。

### 利用可能なコンテナ

- **Rubyコンテナ** (`monadic-chat-ruby-container`): メインアプリケーションコンテナ
  ```shell
  docker exec -it monadic-chat-ruby-container bash
  ```

- **Pythonコンテナ** (`monadic-chat-python-container`): コード実行とデータ分析
  ```shell
  docker exec -it monadic-chat-python-container bash
  ```

- **PostgreSQL/pgvectorコンテナ** (`monadic-chat-pgvector-container`): RAG用ベクトルデータベース
  ```shell
  docker exec -it monadic-chat-pgvector-container bash
  ```

- **Seleniumコンテナ** (`monadic-chat-selenium-container`): Webスクレイピングとブラウザ自動化
  ```shell
  docker exec -it monadic-chat-selenium-container bash
  ```

- **Ollamaコンテナ** (`monadic-chat-ollama-container`): ローカルLLMサポート（ビルド時）
  ```shell
  docker exec -it monadic-chat-ollama-container bash
  ```

?> **開発のヒント**: ローカルで開発する際、Rubyコンテナを停止してホストマシンでアプリケーションを実行しながら、他のコンテナは稼働させ続けることができます。

## JupyterLab

Monadic Chatコンソールの`Actions/Start JupyterLab`メニューを使用してJupyterLabを起動すると、Pythonコンテナ上の`/monadic/data`をカレントディレクトリとしてJupyterLabが起動します。JupyterLabのLauncher画面で`Terminal`をクリックすると、Pythonコンテナにアクセスできます。

![JupyterLab Terminal](../assets/images/jupyterlab-terminal.png ':size=600')

## 一般的な使用例

### Pythonコンテナ
- 追加のPythonパッケージをインストール:
  - `uv pip install --no-cache package_name` (推奨)
  - `pip install package_name`
- 共有データにアクセス: `cd /monadic/data`
- Pythonスクリプトを実行: `python /monadic/data/scripts/my_script.py`

### PostgreSQLコンテナ
- データベースにアクセス: `psql -U postgres`
- データベース一覧を表示: `psql -U postgres -l`
- monadic_chatデータベースにアクセス: `psql -U postgres -d monadic_chat`

### Rubyコンテナ
- Ruby gemsを確認: `bundle list`
- ログを表示: `tail -f /monadic/logs/sinatra.log`
- 設定にアクセス: `cd /monadic/config`

## 関連ドキュメント
- [基本アーキテクチャ](basic-architecture.md) - すべてのコンテナの概要
- [Pythonコンテナ](python-container.md) - Pythonコンテナの詳細ドキュメント
