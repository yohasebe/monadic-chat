FROM ruby:3.2.2-alpine3.17
ENV WORKSPACE /monadic
WORKDIR $WORKSPACE

RUN apk update && \
    apk add --no-cache linux-headers libxml2-dev make gcc libc-dev bash git \
        build-base pkgconfig poppler-dev cairo-dev pango-dev gdk-pixbuf-dev \
        postgresql-dev postgresql-client postgresql-contrib tzdata glib-dev \
        gobject-introspection-dev curl-dev curl wget gcompat && \
    rm -rf /var/cache/apk/*

COPY Gemfile monadic.gemspec $WORKSPACE/
RUN bundle install -j4 --without development test && \
    rm -rf /usr/local/bundle/cache/*

COPY bin/ $WORKSPACE/bin/
COPY lib/ $WORKSPACE/lib/
COPY tmp/ $WORKSPACE/tmp/
COPY views/ $WORKSPACE/views/
COPY config.ru Gemfile LICENSE Rakefile README.md $WORKSPACE/

COPY docker/wait-for-postgres.sh /usr/local/bin/wait-for-postgres.sh
RUN chmod +x /usr/local/bin/wait-for-postgres.sh
