# Standard Python Container

Monadic Chat allows you to run Python code using Python containers. The standard Python container is provided under the name `monadic-chat-python-container`. By using the Python container, AI agents can execute Python code and return the results.

The standard Python container is built with the following Dockerfile.

?> The Dockerfile shown on this page directly reference the code in the [monadic-chat](https//github.com/yohasebe/monadic-chat) repository (`main` branch).

![](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/python/Dockerfile ':include :type=code dockerfile')

## Adding Programs and Libraries

If you want to install additional programs and libraries, you can do one of the following:

- Add an installation script to `pysetup.sh` in the shared folder to install the library during Monadic Chat environment setup (see the example below).
- Refer to [Docker Container Access](/docker-access) to log in to the Python container and install the library after setting up the Monadic Chat environment.
- Refer to [Adding Containers](/ja/adding-containers) to add a customized Python container.
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
    spacy \
    nltk \
    textblob
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

