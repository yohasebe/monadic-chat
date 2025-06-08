FROM ollama/ollama:latest
ARG PROJECT_TAG
LABEL project=$PROJECT_TAG

ENV WORKSPACE=/monadic
WORKDIR $WORKSPACE

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

COPY Dockerfile $WORKSPACE/Dockerfile
