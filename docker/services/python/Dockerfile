FROM python:3.10-slim-bookworm
ARG PROJECT_TAG
LABEL project=$PROJECT_TAG

# Install uv - fast Python package installer
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# Configure uv to use system Python and optimize for Docker
ENV UV_SYSTEM_PYTHON=1
ENV UV_COMPILE_BYTECODE=1
ENV UV_LINK_MODE=copy

# Optional feature toggles (defaults are lean)
ARG INSTALL_LATEX=false
ARG PYOPT_NLTK=false
ARG PYOPT_SPACY=false
ARG PYOPT_SCIKIT=false
ARG PYOPT_GENSIM=false
ARG PYOPT_LIBROSA=false
ARG PYOPT_MEDIAPIPE=false
ARG PYOPT_TRANSFORMERS=false
ARG IMGOPT_IMAGEMAGICK=false

# Base OS packages (lean by default)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      build-essential wget curl git gnupg \
      python3-dev graphviz libgraphviz-dev pkg-config \
      libxml2-dev libxslt-dev \
      pandoc ffmpeg fonts-noto-cjk fonts-ipafont \
    && fc-cache -fv && apt-get autoremove -y && apt-get clean && rm -rf /var/lib/apt/lists/*

# Optional: ImageMagick (convert/mogrify)
RUN if [ "$IMGOPT_IMAGEMAGICK" = "true" ]; then \
      apt-get update && apt-get install -y --no-install-recommends imagemagick && \
      apt-get clean && rm -rf /var/lib/apt/lists/*; \
    fi

# Optional: LaTeX minimal set for Concept Visualizer / Syntax Tree
RUN if [ "$INSTALL_LATEX" = "true" ]; then \
      apt-get update && apt-get install -y --no-install-recommends \
        texlive-xetex texlive-luatex texlive-latex-base texlive-latex-recommended \
        texlive-latex-extra texlive-pictures \
        texlive-fonts-recommended texlive-fonts-extra texlive-plain-generic \
        texlive-lang-cjk latex-cjk-all texlive-lang-japanese \
        texlive-science texlive-pstricks \
        latexmk ghostscript dvisvgm pdf2svg && \
      fc-cache -fv && apt-get autoremove -y && apt-get clean && rm -rf /var/lib/apt/lists/*; \
    fi

# Install base Python packages (stable, cached)
RUN uv pip install --no-cache \
      setuptools wheel \
      jupyterlab ipywidgets plotly \
      numpy pandas statsmodels \
      matplotlib seaborn \
      gunicorn tiktoken flask \
      pymupdf pymupdf4llm \
      selenium html2text \
      openpyxl python-docx python-pptx \
      requests beautifulsoup4 \
      lxml pygraphviz graphviz pydotplus networkx pyvis \
      svgwrite cairosvg tinycss cssselect pygal \
      pyecharts pyecharts-snapshot \
      opencv-python moviepy==2.0.0.dev2

# Optional Python libs (each in its own layer for cache efficiency)
RUN if [ "$PYOPT_NLTK" = "true" ]; then uv pip install --no-cache nltk || true; else echo "skip nltk"; fi
RUN if [ "$PYOPT_SPACY" = "true" ]; then uv pip install --no-cache spacy==3.7.5 || true; else echo "skip spacy"; fi
RUN if [ "$PYOPT_SCIKIT" = "true" ]; then uv pip install --no-cache scikit-learn || true; else echo "skip scikit"; fi
RUN if [ "$PYOPT_GENSIM" = "true" ]; then uv pip install --no-cache gensim || true; else echo "skip gensim"; fi
RUN if [ "$PYOPT_LIBROSA" = "true" ]; then uv pip install --no-cache librosa || true; else echo "skip librosa"; fi
RUN if [ "$PYOPT_MEDIAPIPE" = "true" ]; then uv pip install --no-cache mediapipe || echo 'mediapipe wheel not available; skipped'; else echo "skip mediapipe"; fi
RUN if [ "$PYOPT_TRANSFORMERS" = "true" ]; then uv pip install --no-cache transformers accelerate onnxruntime || true; else echo "skip transformers"; fi

# Set up JupyterLab user settings
RUN mkdir -p /root/.jupyter/lab/user-settings
COPY @jupyterlab /root/.jupyter/lab/user-settings/@jupyterlab

# Set up Matplotlib configuration
ENV MPLCONFIGDIR=/root/.config/matplotlib
RUN mkdir -p /root/.config/matplotlib
COPY matplotlibrc /root/.config/matplotlib/matplotlibrc

# Copy scripts and set permissions
COPY scripts /monadic/scripts
RUN find /monadic/scripts -type f \( -name "*.sh" -o -name "*.py" \) -exec chmod +x {} \;
RUN mkdir -p /monadic/data/scripts

# Set environment variables (visible to LLM)
ENV PATH="/monadic/data/scripts:/monadic/scripts:/monadic/scripts/utilities:/monadic/scripts/services:/monadic/scripts/cli_tools:/monadic/scripts/converters:${PATH}"
ENV FONT_PATH=/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc
ENV PIP_ROOT_USER_ACTION=ignore

# Copy Flask application
COPY flask /monadic/flask

# Create symbolic link for data directory
RUN ln -s /monadic/data /data

COPY Dockerfile /monadic/Dockerfile
