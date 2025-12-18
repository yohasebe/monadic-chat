# Pin to stable Chrome version for reproducible builds
# Update version periodically to get security updates
FROM selenium/standalone-chromium:131.0

ARG PROJECT_TAG
LABEL project=$PROJECT_TAG

ENV WORKSPACE=/monadic
WORKDIR $WORKSPACE
COPY Dockerfile $WORKSPACE/Dockerfile

