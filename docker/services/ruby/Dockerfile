FROM ruby:3.3.0-alpine3.19
ENV WORKSPACE /monadic
WORKDIR $WORKSPACE

RUN apk update && apk add --no-cache \
    linux-headers libxml2-dev make gcc libc-dev bash git \
    build-base pkgconfig\
    postgresql-dev postgresql-client postgresql-contrib \
    curl-dev curl wget gcompat \
    ca-certificates docker-cli && \
    rm -rf /var/cache/apk/*

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
