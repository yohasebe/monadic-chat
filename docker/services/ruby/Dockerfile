# Stage 1: Build environment
FROM ruby:3.3.1-slim-bookworm AS build

RUN apt update && \
    apt install -y --no-install-recommends \
    build-essential wget curl git pandoc \
    ca-certificates gnupg lsb-release \
    postgresql postgresql-contrib libpq-dev \
    imagemagick libmagickwand-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /monadic

COPY Gemfile monadic.gemspec ./
COPY config.ru ./

ENV BUNDLER_WITHOUT development test
RUN bundle install -j4 && \
    rm -rf /usr/local/bundle/cache/*

COPY apps/ ./apps/
COPY lib/ ./lib/
COPY public/ ./public/
COPY views/ ./views/

# Stage 2: Runtime environment
FROM ruby:3.3.1-slim-bookworm

RUN apt update && \
    apt install -y --no-install-recommends \
    ca-certificates curl gnupg lsb-release \
    postgresql-client \
    imagemagick \
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

ENV WORKSPACE /monadic
WORKDIR $WORKSPACE

COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /monadic /monadic

COPY scripts/ $WORKSPACE/scripts/
RUN chmod +x $WORKSPACE/scripts/*
ENV PATH="/monadic/scripts:${PATH}"
