# Dockerアーキテクチャとコンテナ管理

## コンテナ構成

Monadic Chatは、異なる機能のために複数のDockerコンテナを使用します。
サービスセットの正は`docker/services/`ディレクトリです（サービスごとに
1サブディレクトリ、それぞれ独自のDockerfileとcomposeファイルを持ち、
`docker/services/compose.yml`からincludeされます）：

- **Ruby**（`monadic-chat-ruby-container`）：メインアプリケーションサーバー（Falcon/Rackで個人利用向けに2ワーカー）
- **Qdrant**（`monadic-chat-qdrant-container`）：エンベディング用ベクトルデータベース（Helpシステム、PDF Library / Knowledge Base）
- **Embeddings**（`monadic-chat-embeddings-container`）：ローカル埋め込みサービス（`multilingual-e5-base`）
- **Python**（`monadic-chat-python-container`）：JupyterLab、Pythonツールとスクリプト実行
- **Selenium**（`monadic-chat-selenium-container`）：キャプチャ/検索のためのWeb自動化
- **Privacy**（`monadic-chat-privacy-container`）：Privacy Filter用のPIIマスキングサービス
- **Extractor**（`monadic-chat-extractor-container`）：ドキュメント抽出サービス（Docling + RapidOCR）

ネイティブOllamaはコンテナではありません：Rubyサービスはホストの
Ollamaに`host.docker.internal:11434`経由で接続します。

PostgreSQL/PGVectorはbeta.16で削除されました（Qdrant + embeddings
コンテナに置換）。`docs_dev/qdrant_embeddings_migration.md`を参照。

## コンテナのライフサイクル

### 開発モード（`rake server:debug`）
- Rubyコンテナは使用しない（ローカルRuby環境を使用。Rubyコンテナは停止される）
- ピアコンテナ（Qdrant、embeddings、Python等）は必要に応じて起動
- Rubyコードの反復開発に便利

### 本番モード
- すべてのコンテナはDocker Compose（`docker/services/compose.yml`）で管理
- RubyアプリはRubyコンテナ内で実行

### オンデマンドコンテナ起動（Composeプロファイル）

オプションのコンテナはDocker Composeの**プロファイル**を使い、デフォルト
では起動しません。`docker compose up`で起動するのはデフォルトサービス
（Ruby + `lib/monadic/utils/container_dependencies.rb`の`BASE_SERVICES`
— 現在はQdrant + embeddings。これによりHelpシステムは常に動作）のみです。

| コンテナ | プロファイル | 起動条件 |
|----------|------------|---------|
| Ruby | （なし） | 常に起動 |
| Qdrant | （なし） | 常に起動（ベースサービス） |
| Embeddings | （なし） | 常に起動（ベースサービス） |
| Python | `python` | アプリがコード実行・Jupyter・データ分析を必要とするとき |
| Selenium | `selenium` | アプリがWeb自動化を必要とするとき（Web Insight、AutoForge等） |
| Privacy | `privacy` | セッションでPrivacy Filterが有効なとき |
| Extractor | `extractor` | アプリがドキュメント抽出を必要とするとき |

コンテナ起動は、ユーザーがそれを必要とするアプリを選択したとき自動的に
トリガーされます。`ContainerDependencies`モジュール
（`lib/monadic/utils/container_dependencies.rb`）が、MDSL設定
（ツールグループ、jupyterフラグ、pdf_vector_storage）に基づいて各アプリの
必要サービスを決定します。

手動起動：`monadic.sh ensure-service <name>`（例：`python`、`selenium`、`privacy`）

**例外 — フルライフサイクル操作は全プロファイルを含む**：`build`（Build All）、
`update`、`down_docker_compose`、`stop_docker_compose`、`remove_containers`は、
オンデマンド起動とは無関係にすべてのサービスを対象にする必要があります。
これらのコマンドは`${ALL_PROFILES}`（`monadic.sh`冒頭で一度定義。現在の
プロファイルリストはその定義を参照）を使い、プロファイル付きサービスも
デフォルトサービスと一緒にビルド・停止・削除されることを保証します。

### 再起動ポリシー

すべてのコンテナはDockerデフォルトの再起動ポリシー（`no`）を使います：
ライフサイクルはElectron/Composeが所有し、Docker Resource Saverの阻害も
防ぎます。オンデマンドコンテナに独立したライフサイクルはありません。

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
docker logs monadic-chat-ruby-container -f

# コンテナシェルに入る
docker exec -it monadic-chat-ruby-container /bin/bash

# 特定のコンテナを再起動
docker restart monadic-chat-python-container

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

ホストに公開されるポート（正は各サービスの`compose.yml`を参照）：

- 4567：Rubyウェブサーバー
- 8889：JupyterLab（Pythonコンテナ）
- 4444 / 5900 / 7900：Selenium Grid / VNC
- 11434：Ollama API（ホストネイティブ、コンテナではない）

Qdrant・embeddings・Privacy・Extractorはホストポートを公開せず、内部の
`monadic-chat-network`経由でのみ到達できます。

公開ポートは`HOST_BINDING`環境変数でバインドアドレスを制御します：
- **デフォルト**（`127.0.0.1`）：ポートはlocalhostからのみアクセス可能（Standaloneモード）
- **サーバーモード**（`0.0.0.0`）：ポートはネットワークからアクセス可能（`~/monadic/config/env`で`HOST_BINDING=0.0.0.0`を設定）

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

# 必要に応じて該当サービスのcompose.ymlでポートを変更
```
### 再ビルドが遅い / キャッシュミス
- Python Dockerfileは、キャッシュを活用するためにベースpipレイヤーとオプションごとのレイヤー（ライブラリごとに1つのRUN）に分割されている。
- オプションやLaTeX/ImageMagickの切り替えは、影響を受けるレイヤーのみを再実行し、完全な再ビルドを回避する。
