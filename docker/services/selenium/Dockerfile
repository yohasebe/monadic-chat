FROM selenium/standalone-chromium:latest

ARG PROJECT_TAG
LABEL project=$PROJECT_TAG

ENV WORKSPACE=/monadic
WORKDIR $WORKSPACE
COPY Dockerfile $WORKSPACE/Dockerfile

