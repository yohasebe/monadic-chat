FROM ruby:3.3.0-slim-bullseye

RUN apt update && \
    apt install -y --no-install-recommends \
    build-essential wget curl git pandoc \
    ca-certificates curl gnupg lsb-release \
    postgresql postgresql-contrib libpq-dev \
    imagemagick libmagickwand-dev \
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

COPY Gemfile monadic.gemspec $WORKSPACE/
COPY config.ru $WORKSPACE/

RUN bundle install -j4 --without development test && \
    rm -rf /usr/local/bundle/cache/*

COPY apps/ $WORKSPACE/apps/
COPY lib/ $WORKSPACE/lib/
COPY public/ $WORKSPACE/public/
COPY views/ $WORKSPACE/views/

COPY scripts/ $WORKSPACE/scripts/
RUN chmod +x $WORKSPACE/scripts/*
ENV PATH="/monadic/scripts:${PATH}"
