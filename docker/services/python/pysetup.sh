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
python -m spacy download en_core_web_sm
python -m spacy download en_core_web_lg

# Install MeCab
apt-get update && apt-get install -y --no-install-recommends \
    mecab libmecab-dev mecab-utils mecab-ipadic-utf8 \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s /etc/mecabrc /usr/local/etc/mecabrc
    #
# Install mecab-python3
pip install --no-cache-dir --default-timeout=1000 \
    mecab-python3 unidic-lite

# Install Rust so that spaCy can handle Japanese
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source "$HOME/.cargo/env"
export PATH="$HOME/.cargo/bin:$PATH"
pip install setuptools-rust
pip install sudachipy==0.6.8

# Download spaCy models
python -m spacy download ja_core_news_sm
python -m spacy download ja_core_news_md
