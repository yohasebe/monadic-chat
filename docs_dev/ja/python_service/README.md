# Pythonサービスドキュメント

このセクションには、計算ツールとJupyter Notebook統合を提供するMonadic ChatのPythonサービスの内部ドキュメントが含まれています。

## コンテンツ

- [Jupyterコントローラーテスト](jupyter_controller_tests.md) - Jupyter統合のテストインフラストラクチャ

## 概要

Pythonサービスは計算ツールとJupyterLab環境を提供します：

- **JupyterLabアクセス** - ポート8889での直接JupyterLabインターフェース
- **科学計算ライブラリ** - JupyterLab環境でNumPy、Pandas、Matplotlibが利用可能
- **オプションパッケージ** - LaTeX、NLTK、spaCyなど（インストールオプションで設定可能）

## アーキテクチャ

- **JupyterLabサーバー** - 直接ノートブックインターフェース（ポート8889）
- **実行環境** - 科学ライブラリを含む分離されたPythonランタイム
- **Dockerコンテナ** - オプション依存関係を持つスタンドアロンサービス

注意：トークンカウントは以前このコンテナのFlask APIサーバーで処理されていましたが、パフォーマンス向上のためネイティブRuby実装（`tiktoken_ruby` gem）に移行されました。

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
