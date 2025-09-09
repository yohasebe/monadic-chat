# 標準 Python コンテナ

Monadic Chat は `monadic-chat-python-container` 内で Python ツールを実行します。AI エージェントはこのコンテナでコードを実行し、結果を返します。

## Install Options（オプション機能）

アプリの「Actions → Install Options…」から、Python コンテナに含める追加機能を選択できます。

- LaTeX（最小構成）：Concept Visualizer / Syntax Tree 用（有効時のみUI表示、要 OpenAI/Anthropic キー）
- Python ライブラリ（CPU）：`nltk` / `spacy(3.7.5)` / `scikit-learn` / `gensim` / `librosa` / `transformers`
- Tools：ImageMagick（`convert`/`mogrify`）
- Selenium：有効時は従来通りSeleniumを使用。無効かつ Tavily キーありなら From URL は Tavily 使用。どちらもなければ #url/#doc は非表示。

保存後に表示されるダイアログで「Rebuild now」を選ぶと、Python コンテナを成功時のみ本番に反映して再ビルドします。進捗と要約は Install Options ウィンドウに表示され、ログは `~/monadic/log/build/python/<timestamp>/` に保存されます。

NLTK と spaCy について:
- `nltk` オプションはライブラリのみをインストールします。コーパス/データは自動ダウンロードされません。
- `spacy` オプションは `spacy==3.7.5` のみをインストールします。`en_core_web_sm` や `en_core_web_lg` などの言語モデルは自動ダウンロードされません。
- 推奨: `~/monadic/config/pysetup.sh` にダウンロード処理を記述し、ポストセットアップで取得してください（下記例）。

## 検証後反映のビルドとヘルスチェック

- 一時タグでビルド → ポストセットアップ（`~/monadic/config/pysetup.sh` があれば実行）→ ヘルスチェック → 成功時のみ本番タグ（version/latest）へ差し替え。
- ヘルスチェックでは `pdflatex`、`convert`、主要 Python ライブラリ（nltk, spacy, scikit-learn, gensim, librosa, mediapipe, transformers）を確認し、`health.json` に保存します。

## キャッシュ最適化

- Dockerfile はベース層（共通 pip）とオプション層（ライブラリごと RUN）に分割し、キャッシュを最大限活用。
- オプション変更・LaTeX/ImageMagick 切替でも必要な層だけ再実行され、フル再ビルドを回避。

## 追加ライブラリ（pysetup.sh）

`~/monadic/config/pysetup.sh` を作成すると、Rebuild 後の「ポストセットアップ」で自動実行されます（Dockerfile 内に組み込みません）。

例：

```sh
pip install --no-cache-dir --default-timeout=1000 \
  scikit-learn gensim librosa wordcloud nltk textblob spacy==3.7.5
python -m nltk.downloader all
python -m spacy download en_core_web_lg
```

推奨される最小セットの例

```sh
#!/usr/bin/env bash
set -euo pipefail

# NLTK: よく使う軽量セット
python - <<'PY'
import nltk
for pkg in [
  "punkt","stopwords","averaged_perceptron_tagger","wordnet","omw-1.4","vader_lexicon"
]:
    nltk.download(pkg, raise_on_error=True)
print("NLTK datasets downloaded.")
PY

# spaCy: 英語モデル（small/large）
python -m spacy download en_core_web_sm
python -m spacy download en_core_web_lg
echo "spaCy en_core_web_sm/lg downloaded."
```

自動ダウンロードしない理由
- ベースイメージを小さく保ち、再ビルドを高速化するため
- 環境ごとに必要なデータ/モデルのみ選んで導入できるため

日本語モデル（spaCy）と追加のNLTKコーパス

```sh
#!/usr/bin/env bash
set -euo pipefail

# spaCy: 日本語モデル（用途に応じて選択）
python -m spacy download ja_core_news_sm
# または
python -m spacy download ja_core_news_md
# または
python -m spacy download ja_core_news_lg

# NLTK: 例やチュートリアルでよく使われる追加コーパス
python - <<'PY'
import nltk
for pkg in [
  # トークナイザー/品詞タグ付け
  "punkt","averaged_perceptron_tagger",
  # 語彙資源
  "wordnet","omw-1.4","wordnet_ic",
  # 実験用のコーパス
  "brown","reuters","movie_reviews",
  # チャンク/構文解析データ
  "conll2000"
]:
    nltk.download(pkg, raise_on_error=True)
print("Extra NLTK corpora downloaded.")
PY
```

NLTKをすべてダウンロード（フル）

```sh
#!/usr/bin/env bash
set -euo pipefail

# 共有データ配下に保存して永続化するのがおすすめ
export NLTK_DATA=/monadic/data/nltk_data
mkdir -p "$NLTK_DATA"

python - <<'PY'
import nltk, os
target = os.environ.get('NLTK_DATA', '/monadic/data/nltk_data')
nltk.download('all', download_dir=target)
print(f"Downloaded all NLTK datasets to {target}")
PY
```

注意: NLTKの全データはサイズが大きく（数GB）、ダウンロードに時間がかかります。空き容量にご注意ください。

MeCab など追加の OS パッケージが必要な場合：

```sh
apt-get update && apt-get install -y --no-install-recommends \
  mecab libmecab-dev mecab-utils mecab-ipadic-utf8 \
  && apt-get clean && rm -rf /var/lib/apt/lists/*
pip install --no-cache-dir mecab-python3
```

## 日本語フォント

matplotlib 等で日本語表示できるよう、Noto CJK 系フォントと `matplotlibrc` を設定済みです。

## Flask API サーバー（ポート 5070）

- 位置: `/monadic/flask/flask_server.py`
- エンドポイント: `/health`, `/warmup`, `/count_tokens`, `/get_tokens_sequence`, `/decode_tokens`, `/get_encoding_name` など
- コンテナ起動時に自動起動し、Ruby 側から利用されます。

## スクリプト構成

```
/monadic/scripts/
├── utilities/          # システムユーティリティ (sysinfo.sh 等)
├── cli_tools/          # CLIツール (content_fetcher.py 等)
├── converters/         # 変換 (pdf2txt.py, office2txt.py 等)
└── services/           # APIサービス (jupyter_controller.py)
```

PATH に追加され、コンテナ内で直接実行できます。
