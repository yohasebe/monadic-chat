# Standard Python Container

Monadic Chat runs Python tools in `monadic-chat-python-container`. AI agents execute Python code inside this container and return results.

## Install Options

Use the Electron app “Actions → Install Options…” to choose optional components for the Python container:

- LaTeX (with CJK support): Enables Concept Visualizer / Syntax Tree. Installs TeX Live (xelatex/luatex), CJK packages, ghostscript, dvisvgm/pdf2svg so Japanese/Chinese/Korean trees render out of the box (only shown in UI when enabled)
- Python libraries (CPU): `nltk`, `spacy (3.7.5)`, `scikit-learn`, `gensim`, `librosa`, `transformers`
- Tools: ImageMagick (`convert`/`mogrify`)
- Selenium toggle: When disabled and Tavily key exists, From URL uses Tavily; otherwise #url/#doc is hidden

Saving does not auto-rebuild. When you explicitly run Rebuild from the main console, the Python image is built to a temporary tag, verified, and promoted only on success. Progress output appears in the main console. Logs and artifacts are saved under `~/monadic/log/build/python/<timestamp>/`.

Notes on NLTK and spaCy:
- Turning on the `nltk` option installs the package only. NLTK datasets/corpora are not downloaded automatically.
- Turning on the `spacy` option installs `spacy==3.7.5` only. Language models (e.g., `en_core_web_sm`, `en_core_web_lg`) are not downloaded automatically.
- Recommended: use `~/monadic/config/pysetup.sh` to fetch NLTK datasets and spaCy models during post-setup (see below for an example).

## Verified build and health checks

- Build to a temporary tag → verify → retag to version/latest only on success (keep current image on failure)
- Immediately run health checks and write results to `health.json`:
  - `pdflatex` (when LaTeX is enabled)
  - `convert` (when ImageMagick is enabled)
  - Python library import availability

## Cache optimization

- Dockerfile split into a base layer (common pip set) and per-option layers (one RUN per library)
- Toggling options reuses base layers and rebuilds only the affected layers

## Adding libraries with pysetup.sh

Create `~/monadic/config/pysetup.sh` to run a post-setup step after rebuild (not embedded into the Dockerfile).

You can use either `pip` or `uv` (recommended for faster installation):

**Using uv (recommended, 10-100x faster):**

```sh
# Example: NLP libraries and models
uv pip install --no-cache \
  scikit-learn gensim librosa wordcloud nltk textblob spacy==3.7.5
python -m nltk.downloader all
python -m spacy download en_core_web_lg
```

**Using pip (traditional):**

```sh
# Example: NLP libraries and models
pip install --no-cache-dir --default-timeout=1000 \
  scikit-learn gensim librosa wordcloud nltk textblob spacy==3.7.5
python -m nltk.downloader all
python -m spacy download en_core_web_lg
```

Recommended minimal datasets/models

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

Why not auto-download in Dockerfile?
- Keeps base images lean and rebuilds fast
- Lets you choose exactly which datasets/models to include per environment

Japanese models (spaCy) and additional corpora (NLTK)

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

Download all NLTK datasets (full)

```sh
#!/usr/bin/env bash
set -euo pipefail

# Recommended: save under shared data so it persists
export NLTK_DATA=/monadic/data/nltk_data
mkdir -p "$NLTK_DATA"

python - <<'PY'
import nltk, os
target = os.environ.get('NLTK_DATA', '/monadic/data/nltk_data')
nltk.download('all', download_dir=target)
print(f"Downloaded all NLTK datasets to {target}")
PY
```

Note: Full NLTK data is large (several GB) and takes time to download. Ensure sufficient disk space.

If additional OS packages are required (e.g., ImageMagick tools or MeCab), include apt commands:

```sh
apt-get update && apt-get install -y --no-install-recommends \
  mecab libmecab-dev mecab-utils mecab-ipadic-utf8 \
  && apt-get clean && rm -rf /var/lib/apt/lists/*
pip install --no-cache-dir mecab-python3
```

## Japanese fonts

Noto CJK fonts and a configured `matplotlibrc` are included so matplotlib can render Japanese text properly.

## Flask API Server (port 5070)

- Entry: `/monadic/flask/flask_server.py`
- Endpoints: `/health`, `/count_tokens`, `/get_tokens_sequence`, `/decode_tokens`, `/get_encoding_name`, etc.
- Auto-starts with the container and is consumed by the Ruby backend.

## Script layout

```
/monadic/scripts/
├── utilities/          # System utilities (e.g., sysinfo.sh)
├── cli_tools/          # CLI tools (e.g., content_fetcher.py)
├── converters/         # Converters (pdf2txt.py, office2txt.py, etc.)
└── services/           # API services (jupyter_controller.py)
```

These directories are added to PATH so tools can be invoked directly inside the container.
