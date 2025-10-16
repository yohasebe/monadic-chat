# Pythonサービスドキュメント

このセクションには、計算ツールとJupyter Notebook統合を提供するMonadic ChatのPythonサービスの内部ドキュメントが含まれています。

## コンテンツ

- [Jupyterコントローラーテスト](jupyter_controller_tests.md) - Jupyter統合のテストインフラストラクチャ

## 概要

PythonサービスはFlaskベースのAPIサーバーで、以下を提供します：

- **コード実行** - 分離環境でのPythonコードの安全な実行
- **Jupyter統合** - ノートブックの作成、実行、管理
- **科学計算** - NumPy、Pandas、Matplotlibなどのライブラリ
- **オプションパッケージ** - LaTeX、NLTK、spaCyなど（インストールオプションで設定可能）

## アーキテクチャ

- **Flask APIサーバー** (`docker/services/python/app.py`) - HTTP REST API
- **Jupyterコントローラー** - ノートブックライフサイクル管理
- **実行環境** - 科学ライブラリを含む分離されたPythonランタイム
- **Dockerコンテナ** - オプション依存関係を持つスタンドアロンサービス

## 主要エンドポイント

- `POST /execute` - Pythonコードを実行
- `POST /notebook/create` - 新しいJupyter Notebookを作成
- `POST /notebook/execute` - ノートブックセルを実行
- `GET /notebook/status` - ノートブック実行ステータスを確認

## インストールオプション

Pythonコンテナは**アクション → インストールオプション**を介してオプションパッケージのインストールをサポート：

- **LaTeX** - ドキュメント組版（texlive-xetex、texlive-fonts-recommended、cm-super）
- **NLTK** - 一般的なコーパスを含む自然言語ツールキット
- **spaCy** - 産業レベルのNLP（en_core_web_smモデル付き）
- **scikit-learn** - 機械学習ライブラリ
- **transformers** - Hugging Face transformersライブラリ

設定は`~/monadic/config/env`に保存され、スマートリビルド検出のために追跡されます。

## 関連ドキュメント

- [Dockerビルドキャッシング](/ja/docker-build-caching.md) - Pythonコンテナビルドのスマートキャッシング
- [Dockerアーキテクチャ](/ja/docker-architecture.md) - マルチコンテナオーケストレーション

参照：
- `docker/services/python/` - Pythonサービスソースコード
- `docker/services/python/requirements.txt` - Python依存関係
