# Pin to stable version for reproducible builds
# Update version periodically to get security updates
# See: https://github.com/SeleniumHQ/docker-selenium/releases
FROM selenium/standalone-chromium:4.40.0-20260202

ARG PROJECT_TAG
LABEL project=$PROJECT_TAG

ENV WORKSPACE=/monadic
WORKDIR $WORKSPACE
COPY Dockerfile $WORKSPACE/Dockerfile

