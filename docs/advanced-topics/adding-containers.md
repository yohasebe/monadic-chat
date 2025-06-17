# Adding Docker Containers

?> The program examples shown on this page directly reference the code in the [monadic-chat](https://github.com/yohasebe/monadic-chat) repository (`main` branch) on GitHub. If you find any issues, please submit a pull request.

## How to Add Containers

To make a new Docker container available, create a new folder within `~/monadic/data/services` or `~/monadic/data/plugins` and place the following files inside:

- `compose.yml`
- `Dockerfile`
- Any additional files needed by your container

To build your container, use the `Build User Containers` option in the Actions menu. This process:
1. Searches for user containers in both `services` and `plugins` directories
2. Builds each container with the `--no-cache` flag
3. Automatically configures networking and volume mounts
4. Logs the build process to `~/monadic/log/docker_build.log`

?> **Important**: User-defined containers are not automatically built when starting Monadic Chat. After adding or modifying user container definitions, you must use the `Build User Containers` menu option to build them manually.

When user containers are present, Monadic Chat automatically generates a `~/monadic/config/compose.yml` file that includes both system containers and user containers. This file is used by Docker Compose to manage all containers together.

## Minimal Example

Here's a minimal example of what you need:

### compose.yml
```yaml
services:
  my_service:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: my-custom-container
    networks:
      - monadic-chat-network
    volumes:
      - data:/data
    environment:
      - MY_ENV_VAR=value

networks:
  monadic-chat-network:
    external: true

volumes:
  data:
    external: true
    name: monadic-chat_data
```

### Dockerfile
```dockerfile
FROM ubuntu:22.04

# Install your dependencies
RUN apt-get update && apt-get install -y \
    your-packages-here && \
    rm -rf /var/lib/apt/lists/*

# Copy your files
COPY your-script.sh /usr/local/bin/

# Set working directory
WORKDIR /data

# Keep container running
CMD ["tail", "-f", "/dev/null"]
```

## Important Requirements

1. **Network**: Your container must connect to `monadic-chat-network` to communicate with other services
2. **Volume**: Mount the shared `data` volume to access files in `~/monadic/data`
3. **Container Name**: Use a unique, descriptive container name
4. **Keep Alive**: Use a command like `tail -f /dev/null` to keep the container running

## Full Example

For a complete working example, see the Python container included with Monadic Chat:

### compose.yml

<details>
<summary>Python Container compose.yml</summary>

```yaml
services:
  python_service:
    image: yohasebe/python
    build:
      context: .
      dockerfile: Dockerfile
      args:
        PROJECT_TAG: "monadic-chat"
    ports:
      - "8889:8889"
      - "5070:5070"
    container_name: monadic-chat-python-container
    volumes:
      - data:/monadic/data
      - ~/monadic/data:/monadic/data
    command: /bin/sh -c "cd /monadic/flask && gunicorn --timeout 300 -b 0.0.0.0:5070 flask_server:app"
    networks:
      - monadic-chat-network
    depends_on:
      selenium_service:
        condition: service_started
```

</details>

### Dockerfile

<details>
<summary>Python Container Dockerfile</summary>

```dockerfile
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
```

</details>

## Troubleshooting

- **Build fails**: Check `~/monadic/log/docker_build.log` for error messages
- **Container not starting**: Verify your `compose.yml` syntax and network configuration
- **Cannot access shared files**: Ensure the volume mount is correctly configured
- **Network issues**: Confirm your container is on the `monadic-chat-network`

## Notes

- User containers are built with `--no-cache` to ensure fresh builds
- Build logs are saved to `~/monadic/log/docker_build.log`
- If no user containers are found, the build process will notify you
- User containers are managed separately from system containers
