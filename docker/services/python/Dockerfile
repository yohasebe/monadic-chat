FROM python:3.10.14-slim-bookworm
ARG PROJECT_TAG
LABEL project=$PROJECT_TAG

ENV WORKSPACE /monadic
WORKDIR $WORKSPACE

# Install necessary packages
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential wget curl git gnupg \
    pandoc graphviz ffmpeg fonts-noto-cjk \
    imagemagick libmagickwand-dev \
    mecab libmecab-dev mecab-utils \
    ruby ruby-dev\
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Python packages
RUN pip install -U pip && pip install --no-cache-dir --default-timeout=1000 \
    setuptools \
    wheel \
    numpy \
    pandas \
    matplotlib \
    seaborn \
    jupyterlab \
    gunicorn \
    tiktoken \
    pymupdf \
    selenium \
    statsmodels \
    japanize-matplotlib \
    graphviz \
    pydotplus \
    openpyxl \
    python-docx \
    python-pptx \
    html2text \
    flask \
    opencv-python \
    moviepy

    # librosa \
    # mecab-python3 \
    # wordcloud \
    # textblob \
    # nltk \
    # gensim

# Set up JupyterLab user settings
RUN mkdir -p /root/.jupyter/lab/user-settings
COPY @jupyterlab /root/.jupyter/lab/user-settings/@jupyterlab

# Set up Matplotlib configuration
RUN mkdir -p /root/.config/matplotlib
COPY matplotlibrc /root/.config/matplotlib/matplotlibrc

# Copy scripts and set permissions
COPY scripts /monadic/scripts
RUN chmod +x /monadic/scripts/*
RUN mkdir -p /monadic/data/scripts

# Set environment variables
ENV PATH="/monadic/data/scripts:/monadic/scripts:${PATH}"
ENV PIP_ROOT_USER_ACTION=ignore

# Copy Flask application
COPY flask /monadic/flask

# Create symbolic link for data directory
RUN ln -s /monadic/data /data

COPY Dockerfile /monadic/Dockerfile

# Install NLTK modules (failure to install these modules will skip the installation)
# RUN python -m nltk.downloader all || true
