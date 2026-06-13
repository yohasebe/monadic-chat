# Pin to stable version for reproducible builds
# Update version periodically to get security updates
# See: https://github.com/SeleniumHQ/docker-selenium/releases
FROM selenium/standalone-chromium:4.40.0-20260202

# Default needed: the CI publish workflow builds without build-args, and
# the project label drives label-filtered cleanup (remove_project_dangling_images).
ARG PROJECT_TAG=monadic-chat
LABEL project=$PROJECT_TAG

ENV WORKSPACE=/monadic
WORKDIR $WORKSPACE
COPY Dockerfile $WORKSPACE/Dockerfile

