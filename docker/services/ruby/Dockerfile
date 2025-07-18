# Stage 1: Build environment

FROM ruby:3.4.1-slim-bookworm AS build
ARG PROJECT_TAG="monadic-chat"
LABEL project=$PROJECT_TAG

RUN apt update && \
    apt install -y --no-install-recommends \
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

FROM ruby:3.4.1-slim-bookworm
ARG PROJECT_TAG="monadic-chat"
LABEL project=$PROJECT_TAG

RUN apt update && \
    apt install -y --no-install-recommends \
    ca-certificates curl gnupg lsb-release \
    postgresql-client \
    # Add ImageMagick runtime libraries needed by RMagick gem
    # Uncommend to use RSyntaxTree
    # imagemagick libmagickwand-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*


RUN curl -fsSL https://download.docker.com/linux/debian/gpg | \
    gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

RUN echo "deb [arch=$(dpkg --print-architecture) \
         signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
         https://download.docker.com/linux/debian \
         $(lsb_release -cs) stable" | \
         tee /etc/apt/sources.list.d/docker.list > /dev/null

RUN apt update && \
    apt install -y --no-install-recommends \
    docker-ce docker-ce-cli containerd.io docker-compose-plugin

ENV WORKSPACE="/monadic"
WORKDIR $WORKSPACE

COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build $WORKSPACE $WORKSPACE

COPY apps/ $WORKSPACE/apps/
COPY lib/ $WORKSPACE/lib/
COPY public/ $WORKSPACE/public/
COPY views/ $WORKSPACE/views/

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
