# 高度な設定

このページでは、インストールオプション、サーバーモード、コンテナ管理など、Monadic Chatの高度な設定オプションについて説明します。

## インストールオプション :id=install-options

アプリのメニュー **アクション → インストールオプション…** から、Pythonコンテナ用のオプションコンポーネントを選択できます。

### 利用可能なオプション

- **LaTeX**（TeX Live + CJK付き）: Concept Visualizer / Syntax Treeで日本語/中国語/韓国語サポートを有効化（OpenAIまたはAnthropicキーが必要）
- **Pythonライブラリ（CPU）**: `nltk`、`spacy`、`scikit-learn`、`gensim`、`librosa`、`transformers`
- **ツール**: ImageMagick（`convert`/`mogrify`）

### パネルの動作

- インストールオプションウィンドウはモーダルで、設定パネルと同じサイズです
- 「保存」してもウィンドウは閉じません。保存成功は緑色のチェックで短く通知されます
- 未保存の変更がある状態で「閉じる」をクリックすると、確認ダイアログが「保存して閉じる」または「キャンセル」を提示します
- すべてのラベル、説明、ダイアログはUI言語（英/日/中/韓/西/独/仏）に対応しています

### 再ビルド処理

オプションの保存は自動的に再ビルドをトリガーしません。準備ができたら、メインコンソールから**Rebuild**を実行してPythonイメージを更新してください。

更新はアトミックです（ビルド → 検証 → 成功時のみ昇格）。進捗とログはメインコンソールに表示されます。実行ごとのサマリーとヘルスチェックはログと一緒に書き込まれます。

### NLTKとspaCyのセットアップ

- `nltk`を有効にすると、ライブラリのみがインストールされます（データセット/コーパスは自動ダウンロードされません）
- `spacy`を有効にすると、ライブラリのみがインストールされます（言語モデルはダウンロードされません）

**推奨**: `~/monadic/config/pysetup.sh`を追加して、セットアップ後に必要なものを取得してください：

```sh
#!/usr/bin/env bash
set -euo pipefail

# NLTKパッケージ
python - <<'PY'
import nltk
for pkg in ["punkt","stopwords","averaged_perceptron_tagger","wordnet","omw-1.4","vader_lexicon"]:
    nltk.download(pkg, raise_on_error=True)
PY

# spaCyモデル
python -m spacy download en_core_web_sm
python -m spacy download en_core_web_lg
```

#### 日本語と追加コーパス用

```sh
#!/usr/bin/env bash
set -euo pipefail

# spaCy日本語モデル（いずれかを選択）
python -m spacy download ja_core_news_sm
# または: ja_core_news_md / ja_core_news_lg

# NLTK追加コーパス
python - <<'PY'
import nltk
for pkg in ["brown","reuters","movie_reviews","conll2000","wordnet_ic"]:
    nltk.download(pkg, raise_on_error=True)
PY
```

#### 完全なNLTKダウンロード（すべてのデータセット）

```sh
#!/usr/bin/env bash
set -euo pipefail

export NLTK_DATA=/monadic/data/nltk_data
mkdir -p "$NLTK_DATA"

python - <<'PY'
import nltk, os
nltk.download('all', download_dir=os.environ.get('NLTK_DATA','/monadic/data/nltk_data'))
PY
```

?> **注意**: 「all」のダウンロードは大容量（数GB）で、かなりの時間がかかる場合があります。

## 起動時ヘルスチューニング :id=startup-health-tuning

**Start**をクリックすると、システムはオーケストレーションヘルスチェックを実行します。必要に応じて、Ruby制御プレーンが自動的に一度リフレッシュされ（キャッシュフレンドリー）、起動が続行されます。

これは情報プロンプトとして表示され、最終的に緑色の「Ready」が成功を示します。

### プローブ調整

`~/monadic/config/env`でヘルスプローブの動作を調整できます：

```
# ヘルスプローブウィンドウ
START_HEALTH_TRIES=20
START_HEALTH_INTERVAL=2
```

## 依存関係を認識したRuby再ビルド :id=ruby-rebuild

RubyはGem依存関係の指紋（`Gemfile` + `monadic.gemspec`のSHA256）が変更された場合にのみ再ビルドされます。

イメージはこの値を`com.monadic.gems_hash`として保持します。作業コピーと異なる場合、Dockerキャッシュを使用してリフレッシュが実行されるため、bundleレイヤーは可能な限り再利用されます。

### クリーン再ビルドの強制

トラブルシューティング用にクリーン再ビルドを強制するには、`~/monadic/config/env`に設定：

```
FORCE_RUBY_REBUILD_NO_CACHE=true
```

## ビルドログ :id=build-logs

ログは実行ごとに上書きされます：

### Pythonビルドログ

- `~/monadic/log/docker_build_python.log`
- `~/monadic/log/post_install_python.log`
- `~/monadic/log/python_health.json`
- `~/monadic/log/python_meta.json`

### その他のビルドログ

- Ruby/User/Ollamaビルド: `~/monadic/log/docker_build.log`

## サーバーモード設定 :id=server-mode

?> **注意: Monadic Chatは主にスタンドアロンモード向けに設計されています。サーバーモードは、ローカルネットワーク上の複数ユーザーとサービスを共有する必要がある場合にのみ使用してください。**

デフォルトでは、Monadic Chatは単一マシン上のすべてのコンポーネントを使用するスタンドアロンモードで実行されます。

### サーバーモードの有効化

1. 歯車アイコンをクリックして設定を開く
2. 「アプリケーションモード」ドロップダウンで「サーバーモード」を選択
3. 「保存」をクリック
4. アプリケーションを再起動

### サーバーモードの動作

サーバーモードでは：
- サーバーがすべてのDockerコンテナとWebサービスをホスト
- 複数のクライアントがWebブラウザ経由で接続可能
- ネットワークURL（Jupyterノートブックなど）はサーバーの外部IPアドレスを使用
- クライアントはサーバーでホストされているリソースにアクセス可能

詳細は[サーバーモードアーキテクチャ](../docker-integration/basic-architecture.md#server-mode)を参照してください。

## 環境変数 :id=environment-variables

`~/monadic/config/env`による高度な設定：

### Dockerビルド制御

```
# キャッシュなしでRuby再ビルドを強制
FORCE_RUBY_REBUILD_NO_CACHE=true

# ヘルスプローブ設定
START_HEALTH_TRIES=20
START_HEALTH_INTERVAL=2
```

### PDFストレージ

```
# PDFストレージモード (local|cloud)
PDF_STORAGE_MODE=local

# 後方互換性のためのフォールバック
PDF_DEFAULT_STORAGE=local
```

### ロギング

```
# 追加ロギングを有効化
EXTRA_LOGGING=true
```

### MCPサーバー

```
# MCPサーバーを有効化
MCP_SERVER_ENABLED=true
MCP_SERVER_PORT=3100
```

完全な設定リファレンスについては[設定項目](setting-items.md)を参照してください。
