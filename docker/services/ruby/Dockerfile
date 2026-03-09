# Stage 1: Build environment

FROM ruby:3.4.7-slim-bookworm AS build
ARG PROJECT_TAG="monadic-chat"
LABEL project=$PROJECT_TAG

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential wget curl git pandoc \
    ca-certificates gnupg lsb-release \
    postgresql postgresql-contrib libpq-dev \
    # libglib2.0-dev libgirepository1.0-dev \
    # imagemagick libmagickwand-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

ENV WORKSPACE=/monadic
WORKDIR $WORKSPACE

COPY Gemfile monadic.gemspec $WORKSPACE/
COPY config.ru $WORKSPACE/

ENV BUNDLER_WITHOUT="development test"
RUN bundle install -j4 && \
    rm -rf /usr/local/bundle/cache/*

# Stage 2: Runtime environment

FROM ruby:3.4.7-slim-bookworm
ARG PROJECT_TAG="monadic-chat"
LABEL project=$PROJECT_TAG

# Fingerprint for Gem dependencies to enable smart cache/refresh
ARG GEMS_FINGERPRINT=""
LABEL com.monadic.gems_hash=$GEMS_FINGERPRINT

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg lsb-release \
    postgresql-client \
    # Add ImageMagick runtime libraries needed by RMagick gem
    # Uncomment to use RSyntaxTree
    # imagemagick libmagickwand-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 20.x for ABC notation validation (uses downloaded abcjs from vendor assets)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*


RUN curl -fsSL https://download.docker.com/linux/debian/gpg | \
    gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

RUN echo "deb [arch=$(dpkg --print-architecture) \
         signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
         https://download.docker.com/linux/debian \
         $(lsb_release -cs) stable" | \
         tee /etc/apt/sources.list.d/docker.list > /dev/null

# Refresh package list and install Docker components
# Pin containerd.io to 1.7.x stable series to avoid transient repository issues
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    containerd.io=1.7* \
    docker-ce docker-ce-cli docker-compose-plugin && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ENV WORKSPACE="/monadic"
WORKDIR $WORKSPACE

COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build $WORKSPACE $WORKSPACE

COPY apps/ $WORKSPACE/apps/
COPY lib/ $WORKSPACE/lib/
COPY public/ $WORKSPACE/public/

# Build JS bundle if not pre-built on host (concatenates 68 scripts into 1).
# Normally monadic.sh runs `npm run build:js` before docker build.
# This fallback uses plain concatenation (no minification) when esbuild is unavailable.
RUN if [ ! -f $WORKSPACE/public/js/monadic.bundle.min.js ]; then \
      echo "Building JS bundle inside container (concatenation only)..." && \
      node -e " \
        const fs = require('fs'); \
        const p = '$WORKSPACE/public/'; \
        const files = fs.readFileSync(p + 'js/monadic.bundle.files.txt', 'utf8').trim().split('\n'); \
        const out = files.map(f => '/* === ' + f + ' === */\n' + fs.readFileSync(p + f, 'utf8')).join(';\n'); \
        fs.writeFileSync(p + 'js/monadic.bundle.min.js', out); \
        console.log('Bundle: ' + files.length + ' files, ' + Math.round(out.length/1024) + ' KB'); \
      " || echo "WARN: JS bundle build failed, individual files will be used"; \
    fi
COPY views/ $WORKSPACE/views/
RUN mkdir -p $WORKSPACE/internal_config

# create directories log/, public/, tmp/, and tmp/pids/

RUN mkdir -p log/ bin/

COPY scripts/ $WORKSPACE/scripts/
RUN find $WORKSPACE/scripts -type f \( -name "*.sh" -o -name "*.rb" \) -exec chmod +x {} \;
ENV PATH="$WORKSPACE/scripts:$WORKSPACE/scripts/utilities:$WORKSPACE/scripts/cli_tools:$WORKSPACE/scripts/generators:$WORKSPACE/scripts/diagnostics:$WORKSPACE/scripts/diagnostics/apps:$WORKSPACE/scripts/diagnostics/apps/concept_visualizer:$WORKSPACE/scripts/diagnostics/apps/wikipedia:/usr/local/bundle/bin:${PATH}"

# Copy assets list for vendor assets
COPY bin/assets_list.sh $WORKSPACE/bin/assets_list.sh

COPY Dockerfile $WORKSPACE/Dockerfile

# Copy the entrypoint script into the container

COPY entrypoint.sh /usr/local/bin/entrypoint.sh

# Give execute permission to the script

RUN chmod +x /usr/local/bin/entrypoint.sh

# copy `rbsetup.sh` to `/monadic` and run it

COPY rbsetup.sh /monadic/rbsetup.sh
RUN chmod +x /monadic/rbsetup.sh
RUN /monadic/rbsetup.sh

# Download vendor assets for offline use
RUN /monadic/scripts/download_assets.sh

# Set the entrypoint to start the Falcon server
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
