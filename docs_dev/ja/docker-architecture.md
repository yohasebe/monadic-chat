# Dockerアーキテクチャとコンテナ管理

## コンテナ構成

Monadic Chatは、異なる機能のために複数のDockerコンテナを使用します：

- **Ruby**（`monadic-chat-ruby-container`）：メインアプリケーションサーバー（Thin/Rack）
- **Python**（`monadic-chat-python-container`）：PythonツールとエンベディングのためのFlask API
- **PostgreSQL/PGVector**（`monadic-chat-pgvector-container`）：エンベディング用ベクトルデータベース
- **Selenium**（`monadic-chat-selenium-container`）：キャプチャ/検索のためのWeb自動化
- **Ollama**（`monadic-chat-ollama-container`）：ローカルLLMサポート（オプション）

## コンテナのライフサイクル

### 開発モード（`rake server:debug`）
- Rubyコンテナは使用しない（ローカルRuby環境を使用）
- 他のコンテナは必要に応じて起動
- Rubyコードの反復開発に便利

### 本番モード
- すべてのコンテナはDocker Compose（`docker/services/compose.yml`）で管理
- RubyアプリはRubyコンテナ内で実行
- 障害時に自動再起動（composeポリシー）

### Pythonイメージビルド（検証済みプロモーション）
- 再ビルドは`docker/monadic.sh build_python_container`経由で実行。
- 一時タグにビルド → post-setupがあれば実行（`~/monadic/config/pysetup.sh`） → ヘルスチェック → 成功時のみバージョン/latestにretagする。
- 失敗時は現在のイメージが保持される（ロールバック不要）。
- 各実行ごとにログ/メタデータ/ヘルスは`~/monadic/log/build/python/<timestamp>/`配下に保存される。

## コンテナコマンド

```bash
# 実行中のコンテナを表示
docker ps | grep monadic

# コンテナログを表示
docker logs monadic_ruby -f

# コンテナシェルに入る
docker exec -it monadic_ruby /bin/bash

# 特定のコンテナを再起動
docker restart monadic_python

# クリーン再ビルド（compose）
docker compose --project-directory docker/services -f docker/services/compose.yml down
docker compose --project-directory docker/services -f docker/services/compose.yml build --no-cache
docker compose --project-directory docker/services -f docker/services/compose.yml up -d
```

## ボリュームマウント

- `~/monadic/data` → `/monadic/data`（共有データ）
- `~/monadic/config` → `/monadic/config`（APIキー、設定）
- `~/monadic/log` → `/monadic/log`（ログ）
  - Python再ビルド実行ごと：`~/monadic/log/build/python/<timestamp>/`

## ポートマッピング（デフォルト）

- 4567：Rubyウェブサーバー
- 5070：Python Flask API（ドキュメントの`PYTHON_PORT`を参照）
- 5433：PostgreSQL/PGVector
- 4444：Selenium Grid
- 11434：Ollama API（有効時）

## トラブルシューティング

### コンテナが起動しない
```bash
# ログを確認（Rubyの例）
docker logs monadic-chat-ruby-container --tail 100

# composeで再作成（プロジェクトディレクトリはdocker/services）
docker compose --project-directory docker/services -f docker/services/compose.yml down
docker compose --project-directory docker/services -f docker/services/compose.yml build --no-cache
docker compose --project-directory docker/services -f docker/services/compose.yml up -d
```

### ポートの競合
```bash
# ポートを使用しているプロセスを検索
lsof -i :4567

# 必要に応じてdocker/compose.ymlでポートを変更
```

### 再ビルドが遅い / キャッシュミス
- Python Dockerfileは、キャッシュを活用するためにベースpipレイヤーとオプションごとのレイヤー（ライブラリごとに1つのRUN）に分割されている。
- オプションやLaTeX/ImageMagickの切り替えは、影響を受けるレイヤーのみを再実行し、完全な再ビルドを回避する。
