FROM python:3.10-slim-bullseye

ENV WORKSPACE /monadic
WORKDIR $WORKSPACE

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential \
    wget \
    curl \
    git \
    pandoc \
    graphviz \
    gnupg \
    ffmpeg\
    fonts-noto-cjk \
    # libmagick++-dev \
    # librsvg2-dev \
    # libcairo2-dev \
    # libgdk-pixbuf2.0-dev \
    # libghc-gi-gobject-dev \
    # imagemagick \
    # ruby-full \
    mecab libmecab-dev mecab-utils \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN pip install -U pip && pip install --no-cache-dir --default-timeout=100 \
    setuptools \
    wheel \
    numpy \
    pandas \
    matplotlib \
    jupyterlab \
    statsmodels \
    selenium \
    japanize-matplotlib \
    graphviz \
    pydotplus \
    openpyxl \
    python-docx \
    python-pptx \
    pypdf \
    wordcloud \
    mecab-python3 \
    html2text \
    librosa \
    flask \
    tiktoken \
    spacy && python -m spacy download en_core_web_sm

RUN ln -s /monadic/data /data

RUN mkdir -p /root/.jupyter/lab/user-settings
COPY @jupyterlab /root/.jupyter/lab/user-settings/@jupyterlab

RUN mkdir -p /root/.config/matplotlib
COPY matplotlibrc /root/.config/matplotlib/matplotlibrc

COPY scripts /monadic/scripts
RUN chmod +x /monadic/scripts/*

COPY flask /monadic/flask
