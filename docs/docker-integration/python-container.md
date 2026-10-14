# Standard Python Container

Monadic Chat runs Python tools in `monadic-chat-python-container`. AI agents execute Python code inside this container and return the results.

## Install Options

**Actions → Install Options** in the console lets you add optional components to the Python container:

- **LaTeX**: Install LaTeX (minimal set for diagrams). TeX Live with CJK support, needed by Concept Visualizer and Syntax Tree. These two apps are available only when LaTeX is installed and an OpenAI or Anthropic API key is set
- **Python Libraries (CPU)**: nltk, spaCy (3.7.5), gensim, mediapipe (CPU), transformers (CPU only). `scikit-learn` is always included
- **Music Analysis**: librosa + madmom, used by Music Lab
- **System Tools (CLI)**: ImageMagick (`convert`/`mogrify`)

Saving the options does not rebuild the container. At the next Start, Monadic Chat offers **Rebuild and Start**; **Actions → Build Python Container** rebuilds right away. The new image replaces the current one only when the build succeeds. Progress is shown in the console, and these files are written to `~/monadic/log/`:

- `docker_build_python.log`: the output of the latest Python container build (**Rebuild and Start** or **Build Python Container**). When the Python container is built as part of a full build at Start, the output goes to `docker_build.log` instead
- `python_health.json`: which tools (`pdflatex`, `convert`) and libraries are available in the new image, written after a successful build
- `python_meta.json`: the version, build options, and other details of the latest successful build

The nltk and spaCy options install the libraries only. NLTK data and spaCy language models (such as `en_core_web_sm`) are not downloaded; add them with `pysetup.sh` (below).

## Adding libraries with pysetup.sh :id=adding-libraries-with-pysetupsh

Create `~/monadic/config/pysetup.sh` to add your own libraries, data, or OS packages to the Python container. The script is run as the last step of the Python container build, so what it installs is part of the image.

- After creating or editing the script, choose **Actions → Build Python Container**
- The script runs as root during the build. If it exits with an error, the build fails and the current image is kept; the output is in the build log above. Start the script with `set -euo pipefail` so that a failed command stops it
- The shared folder is not available during the build, so install into the image itself (for example, the default locations of `uv pip`, `nltk.download`, and `spacy download`)

You can use either `uv` (faster) or `pip`:

**Using uv:**

```sh
#!/usr/bin/env bash
set -euo pipefail

# Example: NLP libraries and models
uv pip install --no-cache \
  wordcloud textblob
python -m nltk.downloader popular
python -m spacy download en_core_web_lg
```

**Using pip:**

```sh
#!/usr/bin/env bash
set -euo pipefail

# Example: NLP libraries and models
pip install --no-cache-dir --default-timeout=1000 \
  wordcloud textblob
python -m nltk.downloader popular
python -m spacy download en_core_web_lg
```

The `nltk` and `spaCy` lines need the corresponding Install Options turned on.

Commonly used NLTK data and English spaCy models:

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

Japanese spaCy models and more NLTK corpora:

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

`python -m nltk.downloader all` downloads all NLTK data. It is several GB, so make sure there is enough disk space for Docker.

OS packages can be installed with `apt-get`, for example MeCab:

```sh
apt-get update && apt-get install -y --no-install-recommends \
  mecab libmecab-dev mecab-utils mecab-ipadic-utf8 \
  && apt-get clean && rm -rf /var/lib/apt/lists/*
uv pip install --no-cache mecab-python3
```

## Japanese fonts

The container includes Noto CJK fonts, and matplotlib is configured to use them, so Japanese text in plots is displayed correctly.

## Bundled scripts

The tools that come with Monadic Chat are in `/monadic/scripts/` and are on the PATH, so they can be run by name in the container:

```text
/monadic/scripts/
├── utilities/          # System utilities (e.g., sysinfo.sh, run_jupyter.sh)
├── cli_tools/          # CLI tools (e.g., content_fetcher.py)
├── converters/         # Converters (pdf2txt.py, office2txt.py, etc.)
├── music/              # Music Lab tools (music_analyzer.py, etc.)
└── services/           # Services (jupyter_controller.py)
```

Your own scripts go in the shared folder's `scripts` folder; see [Shared Folder](shared-folder.md).
