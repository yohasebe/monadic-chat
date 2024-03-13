FROM continuumio/miniconda3
ENV WORKSPACE /monadic
WORKDIR $WORKSPACE

RUN apt-get update && \
    apt-get install -y build-essential \
    curl \
    git \
    pandoc \
    fonts-takao-gothic \
    graphviz \
    gnupg

RUN apt-get install -y ruby-full \
    libmagick++-dev \
    librsvg2-dev \
    libcairo2-dev \
    libgdk-pixbuf2.0-dev \
    libghc-gi-gobject-dev

RUN conda install -y \
    numpy \
    scipy \
    pandas \
    seaborn \
    plotly \
    matplotlib \
    scikit-learn \
    opencv

RUN conda install -y -c conda-forge \
    statsmodels \
    r-ggplot2 

RUN pip install -U pip setuptools wheel \
    japanize-matplotlib \
    graphviz \
    pymc3 \
    folium \
    pydotplus \
    spacy \
    openpyxl \
    python-docx \
    wikipedia \
    pypdf

RUN python -m spacy download en_core_web_sm

RUN gem install bundler rsyntaxtree

RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - && \
    apt-get update && \
    apt-get install -y nodejs

RUN rm -rf /var/lib/apt/lists/*

RUN mkdir -p /root/.config/matplotlib
COPY matplotlibrc /root/.config/matplotlib/matplotlibrc

