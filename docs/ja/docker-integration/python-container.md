# 標準 Python コンテナ

Monadic Chat は `monadic-chat-python-container` で Python のツールを動かします。AI エージェントはこのコンテナで Python のコードを実行し、結果を返します。

## Install Options

コンソールの **Actions → Install Options** で、Python コンテナに追加のコンポーネントを加えられます。

- **LaTeX**：Install LaTeX (minimal set for diagrams)。CJK に対応した TeX Live で、Concept Visualizer と Syntax Tree に必要です。この 2 つのアプリは、LaTeX をインストールし、OpenAI か Anthropic の API キーを設定したときだけ使えます
- **Python Libraries (CPU)**：nltk、spaCy (3.7.5)、gensim、mediapipe (CPU)、transformers (CPU only)。`scikit-learn` は常に入っています
- **Music Analysis**：librosa + madmom。Music Lab が使います
- **System Tools (CLI)**：ImageMagick（`convert`/`mogrify`）

オプションを保存しても、コンテナは再ビルドされません。次の Start で **Rebuild and Start** が示されます。**Actions → Build Python Container** なら、すぐに再ビルドします。新しいイメージは、ビルドが成功したときだけ今のイメージと入れ替わります。進み具合はコンソールに表示され、`~/monadic/log/` に次のファイルが書かれます。

- `docker_build_python.log`：最後に行った Python コンテナのビルド（**Rebuild and Start** か **Build Python Container**）の出力。Start のときの全体のビルドで Python コンテナを作るときは、出力は `docker_build.log` に入ります
- `python_health.json`：新しいイメージで使えるツール（`pdflatex`、`convert`）とライブラリ。ビルドが成功した後に書かれます
- `python_meta.json`：最後に成功したビルドの版、オプションなどの詳細

nltk と spaCy のオプションは、ライブラリだけを入れます。NLTK のデータと spaCy の言語モデル（`en_core_web_sm` など）はダウンロードされないので、`pysetup.sh`（下記）で加えてください。

## pysetup.sh によるライブラリの追加 :id=adding-libraries-with-pysetupsh

`~/monadic/config/pysetup.sh` を作ると、自分で選んだライブラリ、データ、OS のパッケージを Python コンテナに加えられます。このスクリプトは Python コンテナのビルドの最後の手順として実行されるので、入れたものはイメージに含まれます。

- スクリプトを作ったり直したりした後は、**Actions → Build Python Container** を選んでください
- スクリプトはビルドの中で root として実行されます。エラーで終わるとビルドが失敗し、今のイメージがそのまま残ります。出力は上記のビルドのログにあります。コマンドの失敗で止まるよう、スクリプトの最初に `set -euo pipefail` を書いてください
- ビルドの間は共有フォルダを使えないので、イメージの中に入れてください（たとえば `uv pip`、`nltk.download`、`spacy download` の既定の場所）

`uv`（速い）と `pip` のどちらでも使えます。

**uv を使う場合：**

```sh
#!/usr/bin/env bash
set -euo pipefail

# Example: NLP libraries and models
uv pip install --no-cache \
  wordcloud textblob
python -m nltk.downloader popular
python -m spacy download en_core_web_lg
```

**pip を使う場合：**

```sh
#!/usr/bin/env bash
set -euo pipefail

# Example: NLP libraries and models
pip install --no-cache-dir --default-timeout=1000 \
  wordcloud textblob
python -m nltk.downloader popular
python -m spacy download en_core_web_lg
```

`nltk` と `spaCy` の行には、対応する Install Options をオンにしておく必要があります。

よく使う NLTK のデータと、英語の spaCy のモデル：

```sh
#!/usr/bin/env bash
set -euo pipefail

# NLTK: commonly used lightweight set
python - <<'PY'
import nltk
for pkg in [
  "punkt","stopwords","averaged_perceptron_tagger","wordnet","omw-1.4","vader_lexicon"
]:
    nltk.download(pkg, raise_on_error=True)
print("NLTK datasets downloaded.")
PY

# spaCy: English models (small + large)
python -m spacy download en_core_web_sm
python -m spacy download en_core_web_lg
echo "spaCy en_core_web_sm/lg downloaded."
```

日本語の spaCy のモデルと、追加の NLTK のコーパス：

```sh
#!/usr/bin/env bash
set -euo pipefail

# spaCy: Japanese models (choose size as needed)
python -m spacy download ja_core_news_sm
# or
python -m spacy download ja_core_news_md
# or
python -m spacy download ja_core_news_lg

# NLTK: additional corpora commonly used in examples and tutorials
python - <<'PY'
import nltk
for pkg in [
  # tokenizers + taggers
  "punkt","averaged_perceptron_tagger",
  # lexical resources
  "wordnet","omw-1.4","wordnet_ic",
  # corpora for experiments
  "brown","reuters","movie_reviews",
  # chunking / parsing datasets
  "conll2000"
]:
    nltk.download(pkg, raise_on_error=True)
print("Extra NLTK corpora downloaded.")
PY
```

`python -m nltk.downloader all` で、NLTK のデータをすべてダウンロードできます。数 GB あるので、Docker のディスクの空きを確かめてください。

OS のパッケージは `apt-get` で入れられます。たとえば MeCab の場合：

```sh
apt-get update && apt-get install -y --no-install-recommends \
  mecab libmecab-dev mecab-utils mecab-ipadic-utf8 \
  && apt-get clean && rm -rf /var/lib/apt/lists/*
uv pip install --no-cache mecab-python3
```

## 日本語のフォント

コンテナには Noto CJK のフォントが入っており、matplotlib もそれを使うように設定されているので、グラフの日本語は正しく表示されます。

## 付属のスクリプト

Monadic Chat に付属するツールは `/monadic/scripts/` にあり、PATH が通っているので、コンテナの中で名前だけで実行できます。

```text
/monadic/scripts/
├── utilities/          # System utilities (e.g., sysinfo.sh, run_jupyter.sh)
├── cli_tools/          # CLI tools (e.g., content_fetcher.py)
├── converters/         # Converters (pdf2txt.py, office2txt.py, etc.)
├── music/              # Music Lab tools (music_analyzer.py, etc.)
└── services/           # Services (jupyter_controller.py)
```

自分のスクリプトは共有フォルダの `scripts` フォルダに置きます。[共有フォルダ](shared-folder.md)を参照してください。
