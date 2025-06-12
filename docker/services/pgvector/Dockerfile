FROM ankane/pgvector
ARG PROJECT_TAG
LABEL project=$PROJECT_TAG

# Install Python for JSON processing during import
RUN apt-get update && \
    apt-get install -y python3 python3-psycopg2 && \
    rm -rf /var/lib/apt/lists/*

ENV WORKSPACE=/monadic
WORKDIR $WORKSPACE

# Copy help data if it exists
COPY help_data/ /help_data/

# Copy import script to init directory for first-time setup
COPY import_help_data.sh /docker-entrypoint-initdb.d/20-import-help-data.sh
RUN chmod +x /docker-entrypoint-initdb.d/20-import-help-data.sh

# Copy export ID for MD5 checking
# This will be used to determine if container needs rebuilding
ARG HELP_EXPORT_ID=""
RUN echo "${HELP_EXPORT_ID}" > /help_export_id.txt

COPY Dockerfile /monadic/Dockerfile

# Copy custom entrypoint
COPY custom-entrypoint.sh /custom-entrypoint.sh
RUN chmod +x /custom-entrypoint.sh

# Use custom entrypoint
ENTRYPOINT ["/custom-entrypoint.sh"]
