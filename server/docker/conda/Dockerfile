FROM continuumio/miniconda3
# based on debian:bullseye-slim

ENV WORKSPACE /monadic
WORKDIR $WORKSPACE

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    git \
    pandoc \
    fonts-takao-gothic \
    graphviz \
    gnupg \
    ffmpeg\
    fonts-noto-cjk \
    libmagick++-dev \
    librsvg2-dev \
    libcairo2-dev \
    libgdk-pixbuf2.0-dev \
    ruby-full \
    libghc-gi-gobject-dev \
    mecab libmecab-dev mecab-utils \
    wget \
    imagemagick \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN conda install -y \
    numpy \
    scipy \
    pandas \
    seaborn \
    plotly \
    matplotlib \
    scikit-learn \
    jupyterlab

RUN conda install -y -c conda-forge \
    statsmodels \
    geopandas \
    r r-irkernel r-ggplot2 r-dplyr

RUN conda clean -i -t -y

RUN pip install -U pip && pip install --no-cache-dir \
    setuptools \
    wheel \
    selenium \
    japanize-matplotlib \
    graphviz \
    folium \
    pydotplus \
    spacy \
    openpyxl \
    python-docx \
    python-pptx \
    wikipedia \
    pypdf \
    wordcloud \
    mecab-python3 \
    gensim \
    html2text \
    librosa==0.10.1 && \
    python -m spacy download en_core_web_sm

    # dlib \
    # pymc3 \
    # pdfminer.six \
    # opencv-contrib-python \
    # pydub \
    # Pillow \
    # ffmpeg-python\

RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - && \
    apt-get update && \
    apt-get install -y nodejs

COPY Gemfile /monadic/Gemfile
RUN gem install bundler && bundle install -j4

RUN rm -rf /var/lib/apt/lists/*
RUN ln -s /monadic/data /data

RUN mkdir -p /root/.jupyter/lab/user-settings
COPY @jupyterlab /root/.jupyter/lab/user-settings/@jupyterlab

RUN mkdir -p /root/.config/matplotlib
COPY matplotlibrc /root/.config/matplotlib/matplotlibrc

COPY scripts /monadic/scripts
RUN chmod +x /monadic/scripts/*
