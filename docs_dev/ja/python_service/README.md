# Pythonサービスドキュメント

このセクションには、計算ツールとJupyter Notebook統合を提供するMonadic ChatのPythonサービスの内部ドキュメントが含まれています。

## コンテンツ

- [Jupyterコントローラーテスト](jupyter_controller_tests.md) - Jupyter統合のテストインフラストラクチャ

## 概要

PythonサービスはFlaskベースのAPIサーバーで、以下を提供します：

- **トークンカウント** - tiktokenライブラリを使用したテキストのトークン数計算
- **エンコーディング管理** - エンコーディング名の取得とトークンシーケンスのデコード
- **JupyterLabアクセス** - ポート8889での直接JupyterLabインターフェース（Flask APIとは別）
- **科学計算ライブラリ** - JupyterLab環境でNumPy、Pandas、Matplotlibが利用可能
- **オプションパッケージ** - LaTeX、NLTK、spaCyなど（インストールオプションで設定可能）

## アーキテクチャ

- **Flask APIサーバー** (`docker/services/python/flask/flask_server.py`) - トークンカウントREST API
- **JupyterLabサーバー** - 直接ノートブックインターフェース（ポート8889）
- **実行環境** - 科学ライブラリを含む分離されたPythonランタイム
- **Dockerコンテナ** - オプション依存関係を持つスタンドアロンサービス

## 主要Flask APIエンドポイント

- `GET /health` - サービス可用性のヘルスチェック
- `GET /warmup` - 一般的なエンコーディングを事前ロードしてレイテンシを削減
- `POST /get_encoding_name` - モデルのtiktokenエンコーディング名を取得
- `POST /count_tokens` - テキストのトークン数をカウント
- `POST /get_tokens_sequence` - カンマ区切りのトークンシーケンスを取得
- `POST /decode_tokens` - トークンを元のテキストにデコード

## インストールオプション

Pythonコンテナは**アクション → インストールオプション**を介してオプションパッケージのインストールをサポート：

- **LaTeX** - ドキュメント組版（texlive-xetex、texlive-fonts-recommended、cm-super）
- **NLTK** - 一般的なコーパスを含む自然言語ツールキット
- **spaCy** - 産業レベルのNLP（en_core_web_smモデル付き）
- **scikit-learn** - 機械学習ライブラリ
- **transformers** - Hugging Face transformersライブラリ

設定は`~/monadic/config/env`に保存され、スマートリビルド検出のために追跡されます。

## 関連ドキュメント

- [Dockerビルドキャッシング](../docker-build-caching.md) - Pythonコンテナビルドのスマートキャッシング
- [Dockerアーキテクチャ](../docker-architecture.md) - マルチコンテナオーケストレーション

参照：
- `docker/services/python/` - Pythonサービスソースコード
- `docker/services/python/Dockerfile` - Python依存関係（Dockerfile内でuvを使用してインストール）
