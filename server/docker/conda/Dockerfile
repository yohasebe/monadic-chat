FROM continuumio/miniconda3
ENV WORKSPACE /monadic
WORKDIR $WORKSPACE

RUN apt-get update && \
    apt-get install -y build-essential \
    curl \
    fonts-takao-gothic \
    graphviz

RUN apt-get install -y ruby-full \
    libmagick++-dev \
    librsvg2-dev \
    libcairo2-dev \
    libgdk-pixbuf2.0-dev \
    libghc-gi-gobject-dev

# RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - && \
#     apt-get update && \
#     apt-get install -y --no-install-recommends nodejs && \
#     npm install -g @mermaid-js/mermaid-cli && \
#     rm -rf /var/lib/apt/lists/*

RUN conda install -y \
    pandas \
    matplotlib \
    scikit-learn 

RUN conda install -y -c conda-forge \
    statsmodels \
    r-ggplot2 

RUN pip install -U pip setuptools wheel && \
    pip install japanize-matplotlib && \
    pip install graphviz && \
    pip install pymc3 && \
    pip install folium && \
    pip install pydotplus && \
    pip install spacy

RUN python -m spacy download en_core_web_sm

RUN gem install bundler rsyntaxtree

RUN mkdir -p /root/.config/matplotlib
COPY matplotlibrc /root/.config/matplotlib/matplotlibrc

