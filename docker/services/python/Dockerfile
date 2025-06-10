FROM python:3.10-slim-bookworm
ARG PROJECT_TAG
LABEL project=$PROJECT_TAG

# Install necessary packages
# LaTeX packages for Concept Visualizer:
# - texlive-latex-base: Basic LaTeX
# - texlive-latex-extra: Additional LaTeX packages
# - texlive-pictures: TikZ and PGF
# - texlive-science: Scientific diagrams (including tikz-3dplot)
# - texlive-pstricks: PSTricks for advanced graphics
# - texlive-latex-recommended: Recommended packages
# - texlive-fonts-extra: Additional fonts
# - texlive-plain-generic: Generic packages
# - texlive-lang-cjk: CJK language support
# - latex-cjk-all: Complete CJK support
# - dvisvgm: DVI to SVG converter
# - pdf2svg: PDF to SVG converter (backup option)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential wget curl git gnupg \
    python3-dev graphviz libgraphviz-dev pkg-config \
    libxml2-dev libxslt-dev \
    pandoc ffmpeg fonts-noto-cjk fonts-ipafont \
    imagemagick libmagickwand-dev \
    texlive-xetex texlive-latex-base texlive-fonts-recommended \
    texlive-latex-extra texlive-pictures texlive-lang-cjk latex-cjk-all \
    texlive-science texlive-pstricks texlive-latex-recommended \
    texlive-fonts-extra texlive-plain-generic \
    pdf2svg dvisvgm \
    && fc-cache -fv \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Python packages
RUN pip install -U pip && \
    pip install --no-cache-dir --default-timeout=1000 \
    setuptools \
    wheel \
    jupyterlab ipywidgets plotly \
    numpy  pandas statsmodels \
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

# copy `pysetup.sh` to `/monadic` and run it
COPY pysetup.sh /monadic/pysetup.sh
RUN chmod +x /monadic/pysetup.sh
RUN /monadic/pysetup.sh
