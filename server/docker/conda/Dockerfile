FROM continuumio/miniconda3
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
    libghc-gi-gobject-dev \
    ruby-full \
    mecab libmecab-dev mecab-utils \
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
    librosa==0.10.1

    # dlib \
    # pymc3 \
    # pdfminer.six \
    # opencv-contrib-python \
    # pydub \
    # Pillow \
    # ffmpeg-python\

RUN python -m spacy download en_core_web_sm
RUN gem install bundler rsyntaxtree

RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - && \
    apt-get update && \
    apt-get install -y nodejs

RUN rm -rf /var/lib/apt/lists/*
RUN ln -s /monadic/data /data

RUN mkdir -p /root/.jupyter/lab/user-settings
COPY @jupyterlab /root/.jupyter/lab/user-settings/@jupyterlab
COPY run_jupyter.sh /monadic/run_jupyter.sh
RUN chmod +x /monadic/run_jupyter.sh

RUN mkdir -p /root/.config/matplotlib
COPY matplotlibrc /root/.config/matplotlib/matplotlibrc
