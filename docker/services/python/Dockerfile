FROM python:3.10-slim-bookworm
ARG PROJECT_TAG
LABEL project=$PROJECT_TAG

# Install necessary packages
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential wget curl git gnupg \
    pandoc graphviz ffmpeg fonts-noto-cjk \
    imagemagick libmagickwand-dev \
    mecab libmecab-dev mecab-utils mecab-ipadic-utf8 \
    ruby ruby-dev\
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s /etc/mecabrc /usr/local/etc/mecabrc

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
    pymupdf4llm \
    selenium \
    statsmodels \
    graphviz \
    pydotplus \
    openpyxl \
    python-docx \
    python-pptx \
    html2text \
    flask \
    opencv-python \
    moviepy \
    librosa \
    mecab-python3 \
    wordcloud \
    gensim\
    scikit-learn

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

# Set environment variables (visible to LLM)
ENV PATH="/monadic/data/scripts:/monadic/scripts:${PATH}"
ENV FONT_PATH=/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc
ENV PIP_ROOT_USER_ACTION=ignore

# Copy Flask application
COPY flask /monadic/flask

# Create symbolic link for data directory
RUN ln -s /monadic/data /data

COPY Dockerfile /monadic/Dockerfile
