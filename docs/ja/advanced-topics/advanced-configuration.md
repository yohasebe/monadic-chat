# 高度な設定

このページでは、インストールオプション、サーバーモード、コンテナ管理など、Monadic Chatの高度な設定オプションについて説明します。

## インストールオプション :id=install-options

アプリのメニュー **アクション → インストールオプション…** から、Pythonコンテナ用のオプションコンポーネントを選択できます。

### 利用可能なオプション

- **LaTeX**（TeX Live + CJK付き）: Concept Visualizer / Syntax Treeで日本語/中国語/韓国語サポートを有効化（OpenAIまたはAnthropicキーが必要）
- **Pythonライブラリ（CPU）**: `nltk`、`spacy`、`gensim`、`mediapipe`、`transformers`（`librosa`/`madmom`はMusicグループとして提供。`scikit-learn`はベースイメージに含まれます。オプション一覧は[設定リファレンス](/ja/reference/configuration.md)の表を参照）
- **ツール**: ImageMagick（`convert`/`mogrify`）

### パネルの動作

- インストールオプションウィンドウはモーダルで、設定パネルと同じサイズです
- 「保存」してもウィンドウは閉じません。保存成功は緑色のチェックで短く通知されます
- 未保存の変更がある状態で「閉じる」をクリックすると、確認ダイアログが「保存して閉じる」または「キャンセル」を提示します
- すべてのラベル、説明、ダイアログはUI言語（英/日/中/韓/西/独/仏）に対応しています

### 再ビルド処理

オプションの保存は自動的に再ビルドをトリガーしません。準備ができたら、アプリメニューから**アクション → Pythonコンテナビルド**を実行してPythonイメージを更新してください。

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

ヘルスプローブの動作は`~/monadic/config/env`の`START_HEALTH_TRIES`と`START_HEALTH_INTERVAL`で調整できます。下記の[環境変数](#environment-variables)を参照してください。

## 依存関係を認識したRuby再ビルド :id=ruby-rebuild

RubyはGem依存関係の指紋（`Gemfile` + `monadic.gemspec`のSHA256）が変更された場合にのみ再ビルドされます。

イメージはこの値を`com.monadic.gems_hash`として保持します。作業コピーと異なる場合、Dockerキャッシュを使用してリフレッシュが実行されるため、bundleレイヤーは可能な限り再利用されます。

### クリーン再ビルドの強制

トラブルシューティング用には、`~/monadic/config/env`の`FORCE_RUBY_REBUILD_NO_CACHE`でクリーン再ビルドを強制できます。下記の[環境変数](#environment-variables)を参照してください。

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

### マルチタブセッション管理

Monadic Chatは、複数のブラウザタブを同時に開くことをサポートします。各タブは独立した会話セッションです：

**セッション分離：**
- 各タブは一意のタブID（`sessionStorage`に保持）を持ち、これがサーバー上のWebSocketセッションを識別します
- 会話状態（メッセージ、アプリ選択、パラメータ変更）はタブ単位で管理され、他のタブに漏れることはありません
- タブをリロードしてもセッションは維持され、新しいタブを開くと新しいセッションが始まります
- 異なるブラウザ、ブラウザプロファイル、シークレット/プライベートウィンドウ、デバイスも同様に別セッションです
- サーバーモードでは、各クライアントのセッションは他のクライアントから分離されます

**ブラウザ単位で共有されるもの：**
- Cookieに保存される設定（UI言語や音声設定など）は、同じブラウザプロファイル内の全タブで共有されます

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

環境変数の完全な一覧は[設定リファレンス](/ja/reference/configuration.md)を参照してください。
