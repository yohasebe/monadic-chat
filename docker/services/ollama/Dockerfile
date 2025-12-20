# Pin to stable version for reproducible builds
# Update version periodically to get new model support
# v0.13+ adds Vulkan acceleration, BERT support, DeepSeek-V3.1 tool parsing
FROM ollama/ollama:0.13
ARG PROJECT_TAG
LABEL project=$PROJECT_TAG

ENV WORKSPACE=/monadic
WORKDIR $WORKSPACE

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Copy olsetup.sh to /monadic (it will be overwritten if user provides custom one)
COPY olsetup.sh $WORKSPACE/olsetup.sh
RUN chmod +x $WORKSPACE/olsetup.sh

COPY Dockerfile $WORKSPACE/Dockerfile
