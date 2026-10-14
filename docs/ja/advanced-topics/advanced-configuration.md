# 高度な設定

このページでは、Install Options、起動、ビルドのログ、ブラウザーのタブ、環境変数について説明します。

## インストールオプション :id=install-options

**Actions → Install Options** で、Settings ウィンドウの **Install Options** の項目が開きます。ここで、追加のコンポーネントを選べます。

- **LaTeX**：**Install LaTeX (minimal set for diagrams)**。Concept Visualizer と Syntax Tree に必要です
- **Python Libraries (CPU)**：nltk、spaCy、gensim、mediapipe、transformers
- **Music Analysis**：librosa + madmom。音楽の分析のアプリに必要です
- **System Tools (CLI)**：ImageMagick（`convert` / `mogrify`）
- **Privacy Filter — Additional Languages**：Privacy Filter で英語のほかに扱う言語。保存すると効き、再ビルドは要りません
- **Knowledge Base Quality Pack (Docling)**：レイアウトの解析と OCR で PDF からテキストを取り出す、別のコンテナ。OCR の言語も選べます

オプションの一覧は[設定リファレンス](/ja/reference/configuration.md)の表にあります。

### パネルの動作

- **Save** を押してもウィンドウは閉じません。Save のボタンに、少しの間チェックの印が出ます。
- 保存していない変更があるままウィンドウを閉じると、ダイアログで **Close**（変更を捨てる）と **Save and Close** を選べます。
- ラベル、説明、ダイアログは、UI の言語で表示されます。

### 再ビルド処理

オプションを保存しても、再ビルドは始まりません。Python のオプションを反映するには、**Actions → Build Python Container** を実行します。新しいイメージはまずビルドされて確認され、確認に通ったときだけ今のイメージと入れ替わります。進み具合はメインのコンソールに表示されます。

保存したオプションがまだイメージに入っていないと、次の **Start** で再ビルドするかを尋ねられます。選べるのは **Rebuild and Start**、**Start Anyway**、**Cancel** です。

### NLTKとspaCyのセットアップ

- `nltk` をオンにすると、ライブラリだけが入ります（データセットやコーパスは自動ではダウンロードされません）
- `spacy` をオンにすると、ライブラリだけが入ります（言語モデルはダウンロードされません）

データやモデルをダウンロードするには、`~/monadic/config/pysetup.sh` を書きます。このスクリプトは Python コンテナのビルドの最後に実行されるので、入れたものはイメージに含まれます。このファイルがあると、Python コンテナは配布されているイメージを使わず、お使いのコンピューターでビルドされます。

```sh
#!/usr/bin/env bash
set -euo pipefail

# NLTK packages
python - <<'PY'
import nltk
for pkg in ["punkt","stopwords","averaged_perceptron_tagger","wordnet","omw-1.4","vader_lexicon"]:
    nltk.download(pkg, raise_on_error=True)
PY

# spaCy models
python -m spacy download en_core_web_sm
python -m spacy download en_core_web_lg
```

#### 日本語と追加コーパス用

```sh
#!/usr/bin/env bash
set -euo pipefail

# spaCy Japanese models (pick one)
python -m spacy download ja_core_news_sm
# or: ja_core_news_md / ja_core_news_lg

# NLTK extra corpora
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

python - <<'PY'
import nltk
nltk.download('all')
PY
```

?> "all" のダウンロードは数 GB あり、長い時間がかかります。`/monadic/data` にはダウンロードしないでください。コンテナが動くときはそこに共有フォルダがマウントされるので、ビルドのときにそこへ置いたファイルは見えなくなります。

## 起動時ヘルスチューニング :id=startup-health-tuning

**Start** をクリックすると、Monadic Chat はコンテナが応答するかを確かめます。Ruby コンテナの準備が整わず、Docker がそのコンテナを unhealthy と報告したときは、Docker のキャッシュを使って 1 回だけ再ビルドし、起動し直します（`AUTO_REFRESH_RUBY_ON_HEALTH_FAIL=false` でオフにできます）。緑の「Ready」が出たら、起動は終わっています。

### プローブ調整

確認の動作は、`~/monadic/config/env` の `START_HEALTH_TRIES` と `START_HEALTH_INTERVAL` で調整できます。下の[環境変数](#environment-variables)を参照してください。

## 依存関係を認識したRuby再ビルド :id=ruby-rebuild

Ruby のイメージは、Gem の依存関係の指紋（`Gemfile` と `monadic.gemspec` の SHA256）を `com.monadic.gems_hash` というラベルで持っています。これが今のファイルと違うと、Docker のキャッシュを使って Ruby コンテナを再ビルドします。そのため、できるかぎり bundle の層が使い回されます。

### クリーン再ビルドの強制

問題の切り分けのために、`~/monadic/config/env` の `FORCE_RUBY_REBUILD_NO_CACHE` で、キャッシュを使わない再ビルドを強制できます。下の[環境変数](#environment-variables)を参照してください。

## ビルドログ :id=build-logs

ログはビルドのたびに上書きされます。

### Pythonビルドログ

- `~/monadic/log/docker_build_python.log`（`pysetup.sh` の出力も含みます）
- `~/monadic/log/python_health.json`
- `~/monadic/log/python_meta.json`

### その他のビルドログ

- Ruby とユーザーのコンテナ：`~/monadic/log/docker_build.log`

## マルチタブセッション管理 :id=multi-tab-sessions

Monadic Chat は、ブラウザーのいくつものタブで同時に開けます。タブごとに別の会話のセッションになります。

**セッションの分離：**
- タブごとに固有のタブ ID があり（`sessionStorage` に保存）、サーバー側の WebSocket のセッションを特定します
- 会話の状態（メッセージ、アプリの選択、パラメーターの変更）はタブごとで、ほかのタブに漏れません
- タブを再読み込みしてもセッションは続き、新しいタブを開くと新しいセッションが始まります
- 別のブラウザー、別のブラウザーのプロファイル、シークレットウィンドウやプライベートウィンドウも、それぞれ別のセッションです

**ブラウザーごとに共有されるもの：**
- ブラウザーに保存される設定（たとえば UI の言語と音声認識のモデル。Cookie に保存されます）は、同じブラウザーのプロファイルのすべてのタブで共有されます

## 環境変数 :id=environment-variables

`~/monadic/config/env` で設定できる項目です。

### Dockerビルド制御

```
# Force Ruby rebuild without cache
FORCE_RUBY_REBUILD_NO_CACHE=true

# Health probe settings
START_HEALTH_TRIES=20
START_HEALTH_INTERVAL=2

# Rebuild Ruby once when it is unhealthy at Start (default true)
AUTO_REFRESH_RUBY_ON_HEALTH_FAIL=true
```

### ロギング

```
# Enable extra logging
EXTRA_LOGGING=true
```

### MCPサーバー

```
# Enable MCP server
MCP_SERVER_ENABLED=true
MCP_SERVER_PORT=3100
```

環境変数の一覧は[設定リファレンス](/ja/reference/configuration.md)を参照してください。
