# Standard Python Container

Monadic Chat allows you to run Python code using Python containers. The standard Python container is provided under the name `monadic-chat-python-container`. By using the Python container, AI agents can execute Python code and return the results.

The standard Python container is built with the following Dockerfile.

?> The Dockerfile shown on this page directly reference the code in the [monadic-chat](https://github.com/yohasebe/monadic-chat) repository (`main` branch).

![](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/python/Dockerfile ':include :type=code dockerfile')

## Pre-installed LaTeX Packages

The Python container includes comprehensive LaTeX support for diagram generation apps like Concept Visualizer and Syntax Tree:

### Core LaTeX Packages
- `texlive-latex-base` - Basic LaTeX functionality
- `texlive-latex-extra` - Additional LaTeX packages and tools
- `texlive-fonts-recommended` - Standard LaTeX fonts
- `texlive-lang-chinese`, `texlive-lang-japanese`, `texlive-lang-korean` - CJK language support
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
- Configuration file: `/monadic/matplotlibrc`
- This enables proper rendering of Japanese text in matplotlib plots and figures

When generating charts or plots with Japanese text, the font will be automatically used without additional configuration.

## Adding Programs and Libraries

If you want to install additional programs and libraries, you can do one of the following:

- Add an installation script to `pysetup.sh` in the shared folder to install the library during Monadic Chat environment setup (see the example below).
- Refer to [Docker Container Access](./docker-access) to log in to the Python container and install the library after setting up the Monadic Chat environment.
- Refer to [Adding Containers](./adding-containers) to add a customized Python container.
- Submit a request via [GitHub Issues](https://github.com/yohasebe/monadic-chat/issues).

## Usage of `pysetup.sh`

To install additional libraries in the Python container, add an installation script to `pysetup.sh`. `pysetup.sh` is automatically created in the shared folder during the Monadic Chat build process. By adding an installation script, the script is executed at the end of the `Dockerfile` during the Monadic Chat build process, and the library is installed. The following are examples of scripts.

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

### Customizing Matplotlib Settings

If you need to customize matplotlib settings further, you can create or modify the `matplotlibrc` file in the shared folder. This file will be copied to the appropriate location during container setup:

```ini
# Example matplotlibrc settings
font.family: Noto Sans CJK JP
font.size: 12
axes.unicode_minus: False
```

