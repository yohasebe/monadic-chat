# Base stage: Common environment setup
FROM python:3.10.14-slim-bookworm AS base

ENV WORKSPACE /monadic
WORKDIR $WORKSPACE

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential wget curl git gnupg \
    pandoc graphviz ffmpeg fonts-noto-cjk \
    mecab libmecab-dev mecab-utils \
    ruby \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Stage 1: Build environment
FROM base AS build

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
    wordcloud \
    mecab-python3 \
    html2text \
    librosa \
    flask \
    tiktoken \
    opencv-python \
    moviepy \
    'pdfminer.six[image]' \
    spacy && python -m spacy download en_core_web_sm

# Stage 2: Runtime environment
FROM base

# Copy only the necessary files from the build stage
COPY --from=build /usr/local/lib/python3.10/site-packages /usr/local/lib/python3.10/site-packages
COPY --from=build /usr/local/bin /usr/local/bin

RUN ln -s /monadic/data /data

RUN mkdir -p /root/.jupyter/lab/user-settings
COPY @jupyterlab /root/.jupyter/lab/user-settings/@jupyterlab

RUN mkdir -p /root/.config/matplotlib
COPY matplotlibrc /root/.config/matplotlib/matplotlibrc

COPY scripts /monadic/scripts
RUN chmod +x /monadic/scripts/*
RUN mkdir -p /monadic/data/scripts

ENV PATH="/monadic/data/scripts:/monadic/scripts:${PATH}"
ENV PIP_ROOT_USER_ACTION=ignore

COPY flask /monadic/flask

