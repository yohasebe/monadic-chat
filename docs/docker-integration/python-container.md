# Standard Python Container

Monadic Chat allows you to run Python code using Python containers. The standard Python container is provided under the name `monadic-chat-python-container`. By using the Python container, AI agents can execute Python code and return the results.


The standard Python container is built with the following Dockerfile:

```dockerfile
FROM python:3.10-slim-bookworm
ARG PROJECT_TAG
LABEL project=$PROJECT_TAG

# Install necessary packages
# LaTeX packages for Concept Visualizer:
# - texlive-latex-base: Basic LaTeX
# - texlive-latex-extra: Additional LaTeX packages
# - texlive-pictures: TikZ and PGF
# - texlive-science: Scientific diagrams (including tikz-3dplot)
# - texlive-pstricks: PSTricks for advanced graphics
# - texlive-latex-recommended: Recommended packages
# - texlive-fonts-extra: Additional fonts
# - texlive-plain-generic: Generic packages
# - texlive-lang-cjk: CJK language support
# - latex-cjk-all: Complete CJK support
# - dvisvgm: DVI to SVG converter
# - pdf2svg: PDF to SVG converter (backup option)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential wget curl git gnupg \
    python3-dev graphviz libgraphviz-dev pkg-config \
    libxml2-dev libxslt-dev \
    pandoc ffmpeg fonts-noto-cjk fonts-ipafont \
    imagemagick libmagickwand-dev \
    texlive-xetex texlive-latex-base texlive-fonts-recommended \
    texlive-latex-extra texlive-pictures texlive-lang-cjk latex-cjk-all \
    texlive-science texlive-pstricks texlive-latex-recommended \
    texlive-fonts-extra texlive-plain-generic \
    pdf2svg dvisvgm \
    && fc-cache -fv \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Python packages
RUN pip install -U pip && \
    pip install --no-cache-dir --default-timeout=1000 \
    setuptools \
    wheel \
    jupyterlab ipywidgets plotly \
    numpy  pandas statsmodels \
    matplotlib seaborn \
    gunicorn tiktoken flask \
    pymupdf pymupdf4llm \
    selenium html2text \
    openpyxl python-docx python-pptx \
    requests beautifulsoup4 \
    lxml pygraphviz graphviz pydotplus networkx pyvis \
    svgwrite cairosvg tinycss cssselect pygal \
    pyecharts pyecharts-snapshot \
    opencv-python moviepy==2.0.0.dev2

# Set up JupyterLab user settings
RUN mkdir -p /root/.jupyter/lab/user-settings
COPY @jupyterlab /root/.jupyter/lab/user-settings/@jupyterlab

# Set up Matplotlib configuration
ENV MPLCONFIGDIR=/root/.config/matplotlib
RUN mkdir -p /root/.config/matplotlib
COPY matplotlibrc /root/.config/matplotlib/matplotlibrc

# Copy scripts and set permissions
COPY scripts /monadic/scripts
RUN find /monadic/scripts -type f \( -name "*.sh" -o -name "*.py" \) -exec chmod +x {} \;
RUN mkdir -p /monadic/data/scripts

# Set environment variables (visible to LLM)
ENV PATH="/monadic/data/scripts:/monadic/scripts:/monadic/scripts/utilities:/monadic/scripts/services:/monadic/scripts/cli_tools:/monadic/scripts/converters:${PATH}"
ENV FONT_PATH=/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc
ENV PIP_ROOT_USER_ACTION=ignore

# Copy Flask application
COPY flask /monadic/flask

# Create symbolic link for data directory
RUN ln -s /monadic/data /data

COPY Dockerfile /monadic/Dockerfile

# copy `pysetup.sh` to `/monadic` and run it
COPY pysetup.sh /monadic/pysetup.sh
RUN chmod +x /monadic/pysetup.sh
RUN /monadic/pysetup.sh
```

## Pre-installed LaTeX Packages

The Python container includes comprehensive LaTeX support for diagram generation apps like Concept Visualizer and Syntax Tree:

### Core LaTeX Packages
- `texlive-latex-base` - Basic LaTeX functionality
- `texlive-latex-extra` - Additional LaTeX packages and tools
- `texlive-fonts-recommended` - Standard LaTeX fonts
- `texlive-lang-cjk` - CJK language support
- `latex-cjk-all` - Complete CJK support for LaTeX

### Specialized Packages
- `texlive-science` - Scientific packages including `tikz-3dplot` for 3D visualizations
- `texlive-pstricks` - PSTricks graphics package
- `texlive-latex-recommended` - Recommended LaTeX packages
- `texlive-pictures` - Picture drawing packages including TikZ
- `dvisvgm` - DVI to SVG converter for generating vector graphics

These packages enable generation of complex diagrams, flowcharts, 3D visualizations, and mathematical figures.

## Japanese Font Support

The Python container includes Japanese font support for matplotlib and other visualization libraries. The Noto Sans CJK JP font is installed and configured through `matplotlibrc` settings:

- Font family: Noto Sans CJK JP
- Configuration file: `/root/.config/matplotlib/matplotlibrc`
- This enables proper rendering of Japanese text in matplotlib plots and figures

When generating charts or plots with Japanese text, the font will be automatically used without additional configuration.

## Adding Programs and Libraries

If you want to install additional programs and libraries, you can do one of the following:

- Add an installation script to `pysetup.sh` in the config folder (`~/monadic/config/pysetup.sh`) to install the library during Monadic Chat environment setup (see the example below).
- Refer to [Docker Container Access](./docker-access) to log in to the Python container and install the library after setting up the Monadic Chat environment.
- Refer to [Adding Containers](../advanced-topics/adding-containers) to add a customized Python container.
- Submit a request via [GitHub Issues](https://github.com/yohasebe/monadic-chat/issues).

## Usage of `pysetup.sh`

To install additional libraries in the Python container, create a `pysetup.sh` file in the config folder (`~/monadic/config/`) and add installation commands. When this file exists, the script is executed at the end of the `Dockerfile` during the container build process, and the libraries are installed. After creating or modifying the file, you need to rebuild the container for the changes to take effect.

### Setup Scripts Overview

Monadic Chat supports three optional setup scripts in the config folder:

- `rbsetup.sh` - For installing additional Ruby gems in the Ruby container
- `pysetup.sh` - For installing additional Python packages in the Python container  
- `olsetup.sh` - For downloading Ollama models when building the Ollama container

These scripts are not created automatically. You need to create them manually if you want to customize the container environments. The following are examples of `pysetup.sh` scripts.

### Installing Natural Language Processing Libraries

```sh
# Install NLP libraries, data, and models
pip install --no-cache-dir --default-timeout=1000 \
    scikit-learn \
    gensim\
    librosa \
    wordcloud \
    nltk \
    textblob \
    spacy==3.7.5

# Download NLTK data
python -m nltk.downloader all
# Download spaCy models
python -m spacy download en_core_web_lg
```

### Installing Japanese Morphological Analysis Libraries

```sh
# Install MeCab
apt-get update && apt-get install -y --no-install-recommends \
    mecab libmecab-dev mecab-utils mecab-ipadic-utf8 \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
# Install mecab-python3
pip install --no-cache-dir --default-timeout=1000 mecab-python3
```

### Installing spaCy Japanese Models

```sh
# Install Rust so that spaCy can handle Japanese
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source "$HOME/.cargo/env"
export PATH="$HOME/.cargo/bin:$PATH"
pip install setuptools-rust
pip install sudachipy==0.6.8

# Download spaCy models
python -m spacy download ja_core_news_md
```


## Flask API Server

The Python container runs a Flask API server on port 5070 that provides tokenization services:

- **Location**: `/monadic/flask/flask_server.py`
- **Port**: 5070
- **Endpoints**:
  - `/health` - Health check endpoint
  - `/warmup` - Pre-load tokenizer encodings
  - `/count_tokens` - Count tokens in text
  - `/get_tokens_sequence` - Get token sequence from text
  - `/decode_tokens` - Decode tokens back to text
  - `/get_encoding_name` - Get encoding name for a model

The Flask server is automatically started when the container launches and provides essential tokenization services used by the Ruby backend.

## Scripts Directory Structure

The Python container includes various utility scripts organized in subdirectories under `/monadic/scripts/`:

```
/monadic/scripts/
├── utilities/          # System utilities (sysinfo.sh, run_jupyter.sh)
├── cli_tools/          # CLI tools (content_fetcher.py, webpage_fetcher.py)
├── converters/         # File converters (pdf2txt.py, office2txt.py, extract_frames.py)
└── services/           # API services (jupyter_controller.py)
```

These scripts are added to the PATH and can be executed as commands within the container. All Python and shell scripts in these subdirectories have execute permissions set during container build.

