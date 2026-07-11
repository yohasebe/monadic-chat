# Adding Docker Containers

?> The program examples shown on this page directly reference the code in the [monadic-chat](https://github.com/yohasebe/monadic-chat) repository (`main` branch) on GitHub. If you find any issues, please submit a pull request.

## How to Add Containers

To make a new Docker container available, create a new folder within `~/monadic/data/services` or `~/monadic/data/apps/<your_app>/services` and place the following files inside:

- `compose.yml`
- `Dockerfile`
- Any additional files needed by your container

To build your container, use the `Build User Containers` option in the Actions menu. This process:
1. Searches for user containers in `services` directories and app-specific `services` folders
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

For a complete working example, see the Python container included with Monadic Chat (`docker/services/python/` in the repository). The listings below abbreviate repetitive sections with comments; consult the repository for the full files. Note that some settings shown here are specific to system containers (compose `profiles`, `cache_from`, build args driven by Install Options) and are not needed for user containers.

### compose.yml

<details>
<summary>Python Container compose.yml</summary>

```yaml
services:
  python_service:
    profiles: ["python"]
    image: yohasebe/python
    build:
      context: .
      dockerfile: Dockerfile
      # Reuse the prebuilt default image as a layer cache so a local
      # build only pays for the enabled option layers
      cache_from:
        - ghcr.io/yohasebe/monadic-python:${MONADIC_IMAGE_TAG:-latest}
      args:
        PROJECT_TAG: "monadic-chat"
        INSTALL_LATEX: ${INSTALL_LATEX:-false}
        # ... one build arg per install option (PYOPT_NLTK, PYOPT_SPACY,
        # PYOPT_GENSIM, PYOPT_LIBROSA, PYOPT_MEDIAPIPE, PYOPT_TRANSFORMERS,
        # IMGOPT_IMAGEMAGICK)
    ports:
      - "${HOST_BINDING:-127.0.0.1}:8889:8889"
    container_name: monadic-chat-python-container
    volumes:
      - data:/monadic/data
      - ~/monadic/data:/monadic/data
    command: ["sleep", "infinity"]
    networks:
      - monadic-chat-network
```

</details>

### Dockerfile

<details>
<summary>Python Container Dockerfile</summary>

```dockerfile
FROM python:3.12-slim-bookworm
ARG PROJECT_TAG=monadic-chat
LABEL project=$PROJECT_TAG

# Install uv - fast Python package installer (pinned for reproducibility)
COPY --from=ghcr.io/astral-sh/uv:0.9.18 /uv /usr/local/bin/uv
ENV UV_SYSTEM_PYTHON=1
ENV UV_COMPILE_BYTECODE=1
ENV UV_LINK_MODE=copy

# Optional feature toggles (defaults are lean; set by the compose
# build args listed above, driven by Actions → Install Options)
ARG INSTALL_LATEX=false
ARG PYOPT_NLTK=false
# ... one ARG per remaining install option

# Base OS packages (lean by default)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      build-essential wget curl git gnupg \
      python3-dev graphviz libgraphviz-dev pkg-config \
      libxml2-dev libxslt-dev \
      pandoc ffmpeg fonts-noto-cjk fonts-ipafont \
    && fc-cache -fv && apt-get autoremove -y && apt-get clean && rm -rf /var/lib/apt/lists/*

# Base Python packages, pinned for reproducibility (abbreviated here:
# jupyterlab, numpy, pandas, matplotlib, scikit-learn, pdfplumber,
# selenium, opencv-python, ... — see the repository Dockerfile)
RUN uv pip install --no-cache \
      jupyterlab~=4.5 numpy~=1.26 pandas~=2.3 matplotlib~=3.10 \
      scikit-learn~=1.5 pdfplumber~=0.11 selenium~=4.39 \
      opencv-python~=4.11
      # ... (abbreviated)

# Optional: LaTeX set for Concept Visualizer / Syntax Tree,
# installed only when the Install Option is enabled
RUN if [ "$INSTALL_LATEX" = "true" ]; then \
      apt-get update && apt-get install -y --no-install-recommends \
        texlive-xetex texlive-latex-base texlive-pictures \
        texlive-lang-cjk latex-cjk-all dvisvgm pdf2svg \
        # ... (abbreviated) \
      && apt-get clean && rm -rf /var/lib/apt/lists/*; \
    fi

# Optional Python libs — each option in its own conditional RUN
# so unchanged options reuse the layer cache
RUN if [ "$PYOPT_NLTK" = "true" ]; then uv pip install --no-cache nltk || true; else echo "skip nltk"; fi
# ... one RUN per remaining option (spacy, gensim, librosa+madmom,
# mediapipe, transformers, ImageMagick)

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
ENV PATH="/monadic/data/scripts:/monadic/scripts:/monadic/scripts/utilities:/monadic/scripts/services:/monadic/scripts/cli_tools:/monadic/scripts/converters:/monadic/scripts/music:${PATH}"
ENV FONT_PATH=/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc
ENV PIP_ROOT_USER_ACTION=ignore

# Create symbolic link for data directory
RUN ln -s /monadic/data /data

COPY Dockerfile /monadic/Dockerfile
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
